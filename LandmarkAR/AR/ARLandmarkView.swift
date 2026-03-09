import ARKit
import CoreLocation
import RealityKit
import SwiftUI
import UIKit

// MARK: - ARLandmarkView
// SwiftUI wrapper around our UIKit ARViewController.
// (ARKit requires UIKit, so we bridge using UIViewControllerRepresentable)

struct ARLandmarkView: UIViewControllerRepresentable {
    let landmarks: [Landmark]
    let userLocation: CLLocation?
    let heading: CLHeading?
    let labelDisplaySize: LabelDisplaySize
    let distanceUnit: DistanceUnit
    @Binding var selectedLandmark: Landmark?

    func makeUIViewController(context: Context) -> ARLandmarkViewController {
        ARLandmarkViewController()
    }

    func updateUIViewController(_ vc: ARLandmarkViewController, context: Context) {
        vc.update(landmarks: landmarks, userLocation: userLocation, heading: heading,
                  labelDisplaySize: labelDisplaySize, distanceUnit: distanceUnit) { landmark in
            selectedLandmark = landmark
        }
    }
}

// MARK: - ARLandmarkViewController
// The main AR view controller. Handles ARSession + floating label placement.

class ARLandmarkViewController: UIViewController, ARSessionDelegate {

    private var arView: ARView!
    private var labelViews: [String: LandmarkLabelView] = [:]

    private var landmarks: [Landmark] = []
    private var userLocation: CLLocation?
    private var heading: CLHeading?
    private var onSelect: ((Landmark) -> Void)?
    private var labelDisplaySize: LabelDisplaySize = .medium
    private var distanceUnit: DistanceUnit = .kilometers

    // LAR-46: Maximum number of landmark labels that may appear on screen simultaneously.
    // Landmarks outside the field of view do not count against this limit.
    // Increase WikipediaService.geoSearchLimit proportionally if this is raised.
    static let maxVisibleLabels = 10

    // Cached farthest-first ordering for z-sort. Recomputed only when `landmarks` changes.
    private var sortedFarthestFirst: [Landmark] = []

    private var frameCount = 0
    private let updateInterval = 30

    override func viewDidLoad() {
        super.viewDidLoad()
        setupARView()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        arView.session.pause()
    }

    // MARK: - Setup

    private func setupARView() {
        arView = ARView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)

        let config = ARWorldTrackingConfiguration()
        config.worldAlignment = .gravityAndHeading

        // LAR-20: Pick the video format whose aspect ratio best matches the device screen,
        // so the camera feed fills the display with minimal cropping or letterboxing.
        if let format = Self.bestVideoFormat() {
            config.videoFormat = format
        }

        arView.session.run(config)
        arView.session.delegate = self
    }

    // LAR-20: Returns the supported video format whose aspect ratio is closest to the screen's.
    private static func bestVideoFormat() -> ARConfiguration.VideoFormat? {
        let screen = UIScreen.main.bounds.size
        let screenAspect = max(screen.width, screen.height) / min(screen.width, screen.height)
        return ARWorldTrackingConfiguration.supportedVideoFormats.min { a, b in
            let aAspect = a.imageResolution.width / a.imageResolution.height
            let bAspect = b.imageResolution.width / b.imageResolution.height
            return abs(aAspect - screenAspect) < abs(bAspect - screenAspect)
        }
    }

    // MARK: - Update from SwiftUI

    func update(landmarks: [Landmark],
                userLocation: CLLocation?,
                heading: CLHeading?,
                labelDisplaySize: LabelDisplaySize,
                distanceUnit: DistanceUnit,
                onSelect: @escaping (Landmark) -> Void) {
        let landmarksChanged = landmarks.map(\.id) != self.landmarks.map(\.id)
        self.landmarks = landmarks
        self.userLocation = userLocation
        self.heading = heading
        self.onSelect = onSelect

        // Recompute the farthest-first sort only when the landmark set actually changes,
        // not on every heading/location tick that calls update().
        if landmarksChanged {
            sortedFarthestFirst = landmarks.sorted { $0.distance > $1.distance }
        }

        // LAR-29: If size changed, remove all labels so they rebuild with the new size
        if labelDisplaySize != self.labelDisplaySize {
            self.labelDisplaySize = labelDisplaySize
            labelViews.values.forEach { $0.removeFromSuperview() }
            labelViews.removeAll()
        }

        // Rebuild labels when the distance unit changes so the distance text is reformatted.
        if distanceUnit != self.distanceUnit {
            self.distanceUnit = distanceUnit
            labelViews.values.forEach { $0.removeFromSuperview() }
            labelViews.removeAll()
        }

        // Remove labels for landmarks that are no longer in the list
        let currentIDs = Set(landmarks.map { $0.id })
        for id in labelViews.keys where !currentIDs.contains(id) {
            labelViews[id]?.removeFromSuperview()
            labelViews.removeValue(forKey: id)
        }

        refreshLabels()
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCount += 1
        guard frameCount % updateInterval == 0 else { return }
        refreshLabels()
    }

    // MARK: - Label Placement

    private func refreshLabels() {
        guard let userLocation = userLocation,
              let arFrame = arView.session.currentFrame else { return }

        // LAR-20: Use the actual interface orientation so the projection matches
        // the device's current display orientation rather than assuming landscape.
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        // LAR-22: Use viewMatrix(for:) instead of camera.transform.inverse so that the
        // orientation rotation is included. In landscape the two differ by 90°, which
        // was causing labels to move WITH the pan direction instead of against it.
        let viewMatrix = arFrame.camera.viewMatrix(for: orientation)
        let projectionMatrix = arFrame.camera.projectionMatrix(
            for: orientation,
            viewportSize: arView.bounds.size,
            zNear: 0.1,
            zFar: 1000
        )

        // LAR-42: Visible region with inset so labels near the edge don't clip.
        let edgeInset: CGFloat = 75
        let visibleRect = arView.bounds.insetBy(dx: edgeInset, dy: edgeInset)

        // Pass 1: project all landmarks; separate on-screen from off-screen.
        // `landmarks` is pre-sorted by significance descending (WikipediaService), so
        // the first maxVisibleLabels on-screen entries are already highest-priority.
        var onScreen: [(landmark: Landmark, point: CGPoint)] = []
        for landmark in landmarks {
            guard let worldPos = worldPosition(for: landmark, relativeTo: userLocation),
                  let screenPt = project(worldPos,
                                         camera: viewMatrix,
                                         projection: projectionMatrix,
                                         viewSize: arView.bounds.size),
                  visibleRect.contains(screenPt) else {
                labelViews[landmark.id]?.isHidden = true
                continue
            }
            onScreen.append((landmark, screenPt))
        }

        // LAR-46: Cap visible labels at maxVisibleLabels. Labels beyond the cap are
        // hidden but not removed, so they reappear instantly when a higher-ranked
        // label pans out of view.
        let allowedIDs = Set(onScreen.prefix(ARLandmarkViewController.maxVisibleLabels).map { $0.landmark.id })

        for entry in onScreen {
            if allowedIDs.contains(entry.landmark.id) {
                showLabel(for: entry.landmark, at: entry.point)
            } else {
                labelViews[entry.landmark.id]?.isHidden = true
            }
        }

        // LAR-40: Sample luma beneath each visible label and apply a WCAG-compliant color scheme.
        // Falls back to .dark (the previous default) if the pixel buffer is inaccessible.
        for entry in onScreen where allowedIDs.contains(entry.landmark.id) {
            guard let label = labelViews[entry.landmark.id], !label.isHidden else { continue }
            let luma = sampleLuma(at: entry.point,
                                  in: arFrame.capturedImage,
                                  viewSize: arView.bounds.size,
                                  orientation: orientation)
            let scheme: LabelColorScheme = (luma ?? 0) > LabelColorScheme.lumaThreshold ? .light : .dark
            label.applyColorScheme(scheme)
        }

        // LAR-14: Z-order labels so the closest landmark renders on top when pins overlap.
        // Iterate farthest-first so each bringSubviewToFront call leaves the closest on top.
        // Uses the cached sort (updated in update() when landmarks change) to avoid re-sorting every 30 frames.
        for landmark in sortedFarthestFirst {
            if let label = labelViews[landmark.id], !label.isHidden {
                arView.bringSubviewToFront(label)
            }
        }
    }

    private func worldPosition(for landmark: Landmark, relativeTo userLocation: CLLocation) -> SIMD3<Float>? {
        let bearing = landmark.bearing
        let bearingRad = Float(bearing.toRadians())
        let displayDistance: Float = 80

        let x = displayDistance * sin(bearingRad)
        let z = -displayDistance * cos(bearingRad)

        // LAR-15: Use elevation delta to tilt labels up/down toward actual terrain height.
        // Scale the real altitude difference by the same display/real-distance ratio so
        // the vertical angle in AR matches the true angle to the landmark.
        let y: Float
        if let landmarkAlt = landmark.altitude {
            let altitudeDelta = Float(landmarkAlt - userLocation.altitude)
            let realDistance = Float(max(landmark.distance, 1))
            y = altitudeDelta * (displayDistance / realDistance)
        } else {
            y = 0
        }

        return SIMD3<Float>(x, y, z)
    }

    private func project(_ worldPoint: SIMD3<Float>,
                         camera: float4x4,
                         projection: float4x4,
                         viewSize: CGSize) -> CGPoint? {
        let worldPoint4 = SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let viewSpace = camera * worldPoint4

        guard viewSpace.z < 0 else { return nil }

        let clipSpace = projection * viewSpace
        guard clipSpace.w != 0 else { return nil }

        let ndc = SIMD2<Float>(clipSpace.x / clipSpace.w, clipSpace.y / clipSpace.w)
        let screenX = CGFloat((ndc.x + 1) / 2) * viewSize.width
        let screenY = CGFloat((1 - ndc.y) / 2) * viewSize.height

        return CGPoint(x: screenX, y: screenY)
    }

    // MARK: - Label UI

    private func showLabel(for landmark: Landmark, at point: CGPoint) {
        if let existingLabel = labelViews[landmark.id] {
            existingLabel.isHidden = false
            existingLabel.center = point
            // LAR-8: Update scale whenever position refreshes
            existingLabel.applyDistanceScale(landmark.distance)
        } else {
            let label = LandmarkLabelView(landmark: landmark, displaySize: labelDisplaySize, distanceUnit: distanceUnit)
            label.center = point
            label.onTap = { [weak self] in
                self?.onSelect?(landmark)
            }
            arView.addSubview(label)
            labelViews[landmark.id] = label
        }
    }

    // MARK: - LAR-40: Luma Sampling

    // Samples the average Y (luma) value of a LabelColorScheme.sampleSize × sampleSize region
    // of the captured camera frame centered on the given screen point.
    // The capturedImage is always in sensor (landscape) orientation; screen coordinates are
    // remapped to buffer coordinates based on the current interface orientation.
    // Returns nil if the pixel buffer cannot be accessed, which the caller treats as dark.
    private func sampleLuma(at screenPoint: CGPoint,
                            in pixelBuffer: CVPixelBuffer,
                            viewSize: CGSize,
                            orientation: UIInterfaceOrientation) -> UInt8? {
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        // Plane 0 is the Y (luma) channel in YCbCr format.
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        let bufferWidth  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let bufferHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow  = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard bufferWidth > 0, bufferHeight > 0 else { return nil }

        // Normalised screen fractions in [0, 1]
        let nx = screenPoint.x / viewSize.width
        let ny = screenPoint.y / viewSize.height

        // The captured image sensor is always landscape. Map the screen-space fraction
        // to the corresponding buffer coordinate for each device orientation.
        let bufferX: Int
        let bufferY: Int
        switch orientation {
        case .portrait:
            bufferX = Int(ny * CGFloat(bufferWidth))
            bufferY = Int((1 - nx) * CGFloat(bufferHeight))
        case .portraitUpsideDown:
            bufferX = Int((1 - ny) * CGFloat(bufferWidth))
            bufferY = Int(nx * CGFloat(bufferHeight))
        case .landscapeLeft:
            bufferX = Int((1 - nx) * CGFloat(bufferWidth))
            bufferY = Int((1 - ny) * CGFloat(bufferHeight))
        default: // landscapeRight or unknown
            bufferX = Int(nx * CGFloat(bufferWidth))
            bufferY = Int(ny * CGFloat(bufferHeight))
        }

        let half   = LabelColorScheme.sampleSize / 2
        let startX = max(0, bufferX - half)
        let endX   = min(bufferWidth  - 1, bufferX + half)
        let startY = max(0, bufferY - half)
        let endY   = min(bufferHeight - 1, bufferY + half)
        guard endX > startX, endY > startY else { return nil }

        let yPlane = baseAddress.assumingMemoryBound(to: UInt8.self)
        var sum = 0
        var count = 0
        for row in startY...endY {
            for col in startX...endX {
                sum += Int(yPlane[row * bytesPerRow + col])
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return UInt8(sum / count)
    }
}

// MARK: - LabelColorScheme
// LAR-40: Defines the two color states for AR labels based on background luminance.
// light — for bright backgrounds (sky, snow): dark text on a white pill
// dark  — for dark backgrounds (buildings, foliage): white text on a black pill (previous default)

enum LabelColorScheme {
    case light
    case dark

    // Y-channel threshold (0–255). Values above this indicate a bright background.
    static let lumaThreshold: UInt8 = 128

    // Side length (in pixel-buffer pixels) of the region sampled beneath each label.
    static let sampleSize = 20

    var textColor: UIColor {
        switch self {
        case .light: return UIColor(white: 0.1, alpha: 1.0)
        case .dark:  return .white
        }
    }

    var distanceTextColor: UIColor {
        switch self {
        case .light: return UIColor(white: 0.1, alpha: 0.9)
        case .dark:  return UIColor.white.withAlphaComponent(0.9)
        }
    }

    var iconTintColor: UIColor {
        switch self {
        case .light: return UIColor(white: 0.1, alpha: 1.0)
        case .dark:  return .white
        }
    }
}

// MARK: - LandmarkLabelView
// The floating label that appears in AR for each nearby landmark.
// LAR-7: No background bubble — text-only with shadow for legibility.
// LAR-8: Scaled relative to distance from user.
// LAR-9: Distance displayed prominently below landmark name.
// LAR-14: Red pin indicator shown above the label text.
// LAR-27: Opacity decreases with distance so the closest label reads clearly when labels overlap.
// LAR-40: Background pill and text color adapt to background luminance for WCAG 2.1 contrast.

class LandmarkLabelView: UIView {

    var onTap: (() -> Void)?
    private let landmark: Landmark
    private let displaySize: LabelDisplaySize
    private let distanceUnit: DistanceUnit
    private let nameLabel = UILabel()
    private let distanceLabel = UILabel()
    private let pinImageView = UIImageView()
    private var lastAppliedDistance: CLLocationDistance = -1

    init(landmark: Landmark, displaySize: LabelDisplaySize, distanceUnit: DistanceUnit) {
        self.landmark = landmark
        self.displaySize = displaySize
        self.distanceUnit = distanceUnit
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // LAR-7: No background — text-only with shadow for legibility.
        backgroundColor = .clear

        // LAR-43: Use max sizes from LabelDisplaySize — these are the full sizes applied at ≤200m.
        let pinConfig = UIImage.SymbolConfiguration(pointSize: displaySize.iconSize, weight: .bold)
        pinImageView.image = UIImage(systemName: landmark.category.systemImageName, withConfiguration: pinConfig)
        pinImageView.contentMode = .scaleAspectFit

        // Name label
        nameLabel.text = landmark.title
        nameLabel.font = UIFont.boldSystemFont(ofSize: displaySize.maxTitleFontSize)
        nameLabel.numberOfLines = 2
        nameLabel.textAlignment = .center
        nameLabel.applyShadow()

        // LAR-9: Distance label — formatted and shown below name
        distanceLabel.text = formattedDistance(landmark.distance)
        distanceLabel.font = UIFont.systemFont(ofSize: displaySize.maxDistanceFontSize, weight: .medium)
        distanceLabel.textAlignment = .center
        distanceLabel.applyShadow()

        let stack = UIStackView(arrangedSubviews: [pinImageView, nameLabel, distanceLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let targetWidth = displaySize.maxLabelWidth
        nameLabel.preferredMaxLayoutWidth = targetWidth

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: targetWidth),
        ])

        let size = stack.systemLayoutSizeFitting(
            CGSize(width: targetWidth, height: UIView.layoutFittingCompressedSize.height)
        )
        frame = CGRect(origin: .zero, size: CGSize(width: targetWidth, height: size.height + 8))

        // Apply default dark scheme before the first luma sample arrives.
        applyColorScheme(.dark)

        // LAR-43: Apply initial distance-based scale
        applyDistanceScale(landmark.distance)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    // LAR-40: Update text and icon colors to match the sampled background luminance.
    func applyColorScheme(_ scheme: LabelColorScheme) {
        nameLabel.textColor = scheme.textColor
        distanceLabel.textColor = scheme.distanceTextColor
        pinImageView.tintColor = scheme.iconTintColor
    }

    // LAR-43: Scale the label using an inverse logarithmic curve so closer landmarks appear larger.
    // The user's LabelDisplaySize defines the max size at ≤200m; LabelDisplaySize.minTitleFontSize
    // is the floor at ≥5,000m. Between those distances the scale interpolates on a log curve.
    // LAR-27: Opacity step-table kept unchanged — fades distant labels so the closest reads first.
    func applyDistanceScale(_ distanceMeters: CLLocationDistance) {
        // Landmark distance only changes on a new fetch, not every AR frame — skip redundant work.
        guard distanceMeters != lastAppliedDistance else { return }
        lastAppliedDistance = distanceMeters

        let factor = LabelDisplaySize.scaleFactor(for: distanceMeters)
        let minScale = LabelDisplaySize.minTitleFontSize / displaySize.maxTitleFontSize
        let scale = minScale + (1.0 - minScale) * factor
        transform = CGAffineTransform(scaleX: scale, y: scale)

        // LAR-27: Opacity decreases with distance so the closest landmark is visually dominant.
        let opacity: CGFloat
        switch distanceMeters {
        case ..<300:      opacity = 1.00
        case 300..<800:   opacity = 0.90
        case 800..<2000:  opacity = 0.75
        case 2000..<5000: opacity = 0.55
        default:          opacity = 0.40
        }
        alpha = opacity
    }

    @objc private func tapped() {
        onTap?()
    }

    // LAR-9: Human-readable distance string — delegates to DistanceUnit for unit-aware formatting.
    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        distanceUnit.formatted(meters)
    }
}

// MARK: - UILabel Shadow Helper

private extension UILabel {
    func applyShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 1)
        layer.shadowOpacity = 0.9
        layer.shadowRadius = 3
        layer.masksToBounds = false
    }
}

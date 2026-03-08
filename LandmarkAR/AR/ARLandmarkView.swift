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
    @Binding var selectedLandmark: Landmark?

    func makeUIViewController(context: Context) -> ARLandmarkViewController {
        ARLandmarkViewController()
    }

    func updateUIViewController(_ vc: ARLandmarkViewController, context: Context) {
        vc.update(landmarks: landmarks, userLocation: userLocation, heading: heading,
                  labelDisplaySize: labelDisplaySize) { landmark in
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

        for landmark in landmarks {
            guard let worldPosition = worldPosition(for: landmark, relativeTo: userLocation) else { continue }

            guard let screenPoint = project(worldPosition,
                                            camera: viewMatrix,
                                            projection: projectionMatrix,
                                            viewSize: arView.bounds.size) else {
                labelViews[landmark.id]?.isHidden = true
                continue
            }

            showLabel(for: landmark, at: screenPoint)
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
        let padding: CGFloat = 80
        let clampedX = max(padding, min(arView.bounds.width - padding, point.x))
        let clampedY = max(padding, min(arView.bounds.height - padding, point.y))
        let clampedPoint = CGPoint(x: clampedX, y: clampedY)

        if let existingLabel = labelViews[landmark.id] {
            existingLabel.isHidden = false
            existingLabel.center = clampedPoint
            // LAR-8: Update scale whenever position refreshes
            existingLabel.applyDistanceScale(landmark.distance)
        } else {
            let label = LandmarkLabelView(landmark: landmark, displaySize: labelDisplaySize)
            label.center = clampedPoint
            label.onTap = { [weak self] in
                self?.onSelect?(landmark)
            }
            arView.addSubview(label)
            labelViews[landmark.id] = label
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

class LandmarkLabelView: UIView {

    var onTap: (() -> Void)?
    private let landmark: Landmark
    private let nameLabel = UILabel()
    private let distanceLabel = UILabel()
    private var lastAppliedDistance: CLLocationDistance = -1

    init(landmark: Landmark, displaySize: LabelDisplaySize) {
        self.landmark = landmark
        super.init(frame: .zero)
        setup(displaySize: displaySize)
    }

    required init?(coder: NSCoder) { fatalError() }

    // LAR-29: Font and icon sizes per display size setting.
    private static func sizes(for displaySize: LabelDisplaySize) -> (icon: CGFloat, name: CGFloat, distance: CGFloat) {
        switch displaySize {
        case .small:  return (16, 12, 10)
        case .medium: return (22, 15, 12)
        case .large:  return (30, 20, 16)
        }
    }

    private func setup(displaySize: LabelDisplaySize) {
        // LAR-7: No background or border — transparent view, text only
        backgroundColor = .clear

        let sz = Self.sizes(for: displaySize)

        // LAR-14: Category icon above the landmark name, matching the icons in Settings
        let pinImageView = UIImageView()
        let pinConfig = UIImage.SymbolConfiguration(pointSize: sz.icon, weight: .bold)
        pinImageView.image = UIImage(systemName: landmark.category.systemImageName, withConfiguration: pinConfig)
        pinImageView.tintColor = .white
        pinImageView.contentMode = .scaleAspectFit

        // Name label
        nameLabel.text = landmark.title
        nameLabel.textColor = .white
        nameLabel.font = UIFont.boldSystemFont(ofSize: sz.name)
        nameLabel.numberOfLines = 2
        nameLabel.textAlignment = .center
        nameLabel.applyShadow()

        // LAR-9: Distance label — formatted and shown below name
        distanceLabel.text = formattedDistance(landmark.distance)
        distanceLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        distanceLabel.font = UIFont.systemFont(ofSize: sz.distance, weight: .medium)
        distanceLabel.textAlignment = .center
        distanceLabel.applyShadow()

        let stack = UIStackView(arrangedSubviews: [pinImageView, nameLabel, distanceLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let targetWidth: CGFloat = 160
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

        // LAR-8: Apply initial distance-based scale
        applyDistanceScale(landmark.distance)

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    // LAR-8: Scale the label so closer landmarks appear larger.
    // LAR-27: Also fade distant labels so the closest landmark is visually dominant
    // when multiple labels overlap in the same screen area.
    func applyDistanceScale(_ distanceMeters: CLLocationDistance) {
        // Landmark distance only changes on a new fetch, not every AR frame — skip redundant work.
        guard distanceMeters != lastAppliedDistance else { return }
        lastAppliedDistance = distanceMeters

        let scale: CGFloat
        let opacity: CGFloat
        switch distanceMeters {
        case ..<300:        scale = 1.4; opacity = 1.00
        case 300..<800:     scale = 1.2; opacity = 0.90
        case 800..<2000:    scale = 1.0; opacity = 0.75
        case 2000..<5000:   scale = 0.85; opacity = 0.55
        default:            scale = 0.70; opacity = 0.40
        }
        transform = CGAffineTransform(scaleX: scale, y: scale)
        alpha = opacity
    }

    @objc private func tapped() {
        onTap?()
    }

    // LAR-9: Human-readable distance string
    private func formattedDistance(_ meters: CLLocationDistance) -> String {
        if meters < 100 {
            return "< 100 m away"
        } else if meters < 1000 {
            return "\(Int((meters / 100).rounded() * 100)) m away"
        } else {
            return String(format: "%.1f km away", meters / 1000)
        }
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

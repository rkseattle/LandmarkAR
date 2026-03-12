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

    // LAR-48: Edge fade constants. Labels within edgeInset pts of the viewport edge are
    // fully hidden; they fade in over the fadeZoneWidth region beyond that.
    static let edgeInset: CGFloat = 75
    static let fadeZoneWidth: CGFloat = 60

    // LAR-51: Labels whose bounding rects intersect are grouped into a cluster badge.
    // detectClusters(from:labelSize:) uses the rendered label dimensions passed by the
    // caller; the unit-test default (20 × 20) exercises boundary behaviour in isolation.
    // fanRadius — radius (pt) of the radial fan arc when a cluster is expanded.
    // fanAnimationDuration — open/close animation time (250 ms, ease-in-out).
    // maxFanLabels — labels shown in the fan before an overflow badge appears.
    static let fanRadius: CGFloat = 80
    static let fanAnimationDuration: TimeInterval = 0.25
    static let maxFanLabels = 6

    // LAR-48: Returns an opacity in [0, 1] that fades labels near the viewport edges.
    // Full opacity at >= edgeInset + fadeZoneWidth pts from each edge; zero at <= edgeInset.
    static func edgeFadeOpacity(at point: CGPoint, in viewSize: CGSize) -> CGFloat {
        let d = min(point.x, point.y, viewSize.width - point.x, viewSize.height - point.y)
        return max(0, min(1, (d - edgeInset) / fadeZoneWidth))
    }

    // Cached farthest-first ordering for z-sort. Recomputed only when `landmarks` changes.
    private var sortedFarthestFirst: [Landmark] = []

    // LAR-51: Cluster state and supporting views.
    private var clusterState: ClusterState = .none
    private var clusterBadgeViews: [String: ClusterBadgeView] = [:]
    private var overflowBadgeView: UIView?

    private lazy var scrimView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        v.alpha = 0
        v.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(scrimTapped))
        v.addGestureRecognizer(tap)
        return v
    }()

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
            // LAR-51: Dismiss any open cluster list and clear stale badges when the
            // landmark set changes — the old cluster IDs are no longer meaningful.
            collapseCluster(animated: false)
            clearClusterBadges()
        }

        // LAR-29: If size changed, remove all labels so they rebuild with the new size
        if labelDisplaySize != self.labelDisplaySize {
            self.labelDisplaySize = labelDisplaySize
            collapseCluster(animated: false)
            labelViews.values.forEach { $0.removeFromSuperview() }
            labelViews.removeAll()
            clearClusterBadges()
        }

        // Rebuild labels when the distance unit changes so the distance text is reformatted.
        if distanceUnit != self.distanceUnit {
            self.distanceUnit = distanceUnit
            collapseCluster(animated: false)
            labelViews.values.forEach { $0.removeFromSuperview() }
            labelViews.removeAll()
            clearClusterBadges()
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
        // ARSession delegate fires on a background queue; all UIKit work must be on main.
        DispatchQueue.main.async { [weak self] in self?.refreshLabels() }
    }

    // MARK: - Label Placement

    private func refreshLabels() {
        // LAR-51: While a fan is expanded, freeze label positions to avoid fighting
        // with the in-flight animations.
        if case .expanded = clusterState { return }

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

        // LAR-42/LAR-48: Visible region with inset so labels near the edge don't clip.
        let visibleRect = arView.bounds.insetBy(dx: Self.edgeInset, dy: Self.edgeInset)

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
        let allowedEntries = Array(onScreen.prefix(ARLandmarkViewController.maxVisibleLabels))
        let allowedIDs = Set(allowedEntries.map { $0.landmark.id })

        for entry in onScreen where !allowedIDs.contains(entry.landmark.id) {
            labelViews[entry.landmark.id]?.isHidden = true
        }

        // LAR-51: Detect clusters using actual label bounding-rect intersection.
        // Labels whose rendered frames overlap (any amount) belong to the same cluster.
        let approxHeight = labelDisplaySize.iconSize + labelDisplaySize.maxTitleFontSize
            + labelDisplaySize.maxDistanceFontSize + 20
        let labelSize = CGSize(width: labelDisplaySize.maxLabelWidth, height: approxHeight)
        let clusterEntries = allowedEntries.map { (id: $0.landmark.id, point: $0.point) }
        let clusters = ARLandmarkViewController.detectClusters(from: clusterEntries,
                                                               labelSize: labelSize)
        let clusteredIDs = Set(clusters.flatMap { $0.landmarkIDs })

        // Non-clustered allowed labels: show normally.
        for entry in allowedEntries where !clusteredIDs.contains(entry.landmark.id) {
            showLabel(for: entry.landmark, at: entry.point)
        }

        // Clustered labels: ensure the view exists (needed for fan expansion) but keep hidden.
        for entry in allowedEntries where clusteredIDs.contains(entry.landmark.id) {
            ensureLabelView(for: entry.landmark, at: entry.point)
        }

        // Show/update cluster badges.
        for cluster in clusters {
            showClusterBadge(cluster)
        }

        // Remove badges for clusters that no longer exist (members moved apart).
        let activeBadgeIDs = Set(clusters.map { $0.id })
        for id in Array(clusterBadgeViews.keys) where !activeBadgeIDs.contains(id) {
            clusterBadgeViews[id]?.removeFromSuperview()
            clusterBadgeViews.removeValue(forKey: id)
        }

        // LAR-40: Sample luma beneath each visible (non-clustered) label and apply
        // a WCAG-compliant color scheme. Falls back to .dark if buffer is inaccessible.
        for entry in allowedEntries where !clusteredIDs.contains(entry.landmark.id) {
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
        for landmark in sortedFarthestFirst {
            if let label = labelViews[landmark.id], !label.isHidden {
                arView.bringSubviewToFront(label)
            }
        }
        // Bring cluster badges above individual labels.
        for badge in clusterBadgeViews.values where !badge.isHidden {
            arView.bringSubviewToFront(badge)
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
        // LAR-48: Multiply distance-based opacity by edge-fade so labels ghosting in/out of
        // the viewport edges blend smoothly rather than popping on the hard edgeInset boundary.
        let edgeFade = Self.edgeFadeOpacity(at: point, in: arView.bounds.size)

        if let existingLabel = labelViews[landmark.id] {
            existingLabel.isHidden = false
            existingLabel.center = point
            // LAR-8: Update scale whenever position refreshes
            existingLabel.applyDistanceScale(landmark.distance)
            existingLabel.alpha = existingLabel.distanceAlpha * edgeFade
        } else {
            let label = LandmarkLabelView(landmark: landmark, displaySize: labelDisplaySize, distanceUnit: distanceUnit)
            label.center = point
            label.onTap = { [weak self] in
                self?.onSelect?(landmark)
            }
            arView.addSubview(label)
            labelViews[landmark.id] = label
            label.alpha = label.distanceAlpha * edgeFade
        }
    }

    /// Creates the label view for `landmark` if it does not yet exist, positioned at `point`
    /// but hidden. Called for clustered landmarks so the view is ready for fan expansion.
    private func ensureLabelView(for landmark: Landmark, at point: CGPoint) {
        if labelViews[landmark.id] == nil {
            let label = LandmarkLabelView(landmark: landmark, displaySize: labelDisplaySize, distanceUnit: distanceUnit)
            label.center = point
            label.onTap = { [weak self] in
                self?.onSelect?(landmark)
                self?.collapseCluster()
            }
            arView.addSubview(label)
            labelViews[landmark.id] = label
            label.applyDistanceScale(landmark.distance)
        }
        labelViews[landmark.id]?.isHidden = true
    }

    // MARK: - LAR-51: Cluster Detection

    /// Groups entries whose label bounding rects intersect using union-find.
    /// - `labelSize`: the rendered label dimensions used to build each entry's bounding rect.
    ///   Defaults to 20 × 20 so that existing unit tests (which pass explicit point deltas)
    ///   exercise the same threshold behaviour as before without needing changes.
    /// Entries must be pre-sorted by significance (highest first) so that `landmarkIDs`
    /// in each returned ClusterGroup preserves that ordering.
    static func detectClusters(from entries: [(id: String, point: CGPoint)],
                                labelSize: CGSize = CGSize(width: 20, height: 20)) -> [ClusterGroup] {
        let n = entries.count
        guard n >= 2 else { return [] }

        var parent = Array(0..<n)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }

        // Build bounding rects centred on each entry's screen point.
        let hw = labelSize.width / 2
        let hh = labelSize.height / 2
        let rects = entries.map { e in
            CGRect(x: e.point.x - hw, y: e.point.y - hh, width: labelSize.width, height: labelSize.height)
        }

        for i in 0..<n {
            for j in (i + 1)..<n {
                if rects[i].intersects(rects[j]) {
                    let pi = find(i), pj = find(j)
                    if pi != pj { parent[pi] = pj }
                }
            }
        }

        var groups = [Int: [Int]]()
        for i in 0..<n { groups[find(i), default: []].append(i) }

        return groups.compactMap { (_, indices) -> ClusterGroup? in
            guard indices.count >= 2 else { return nil }
            let sorted = indices.sorted()   // lower index = higher significance
            let ids = sorted.map { entries[$0].id }
            let xs = indices.map { entries[$0].point.x }
            let ys = indices.map { entries[$0].point.y }
            let count = CGFloat(indices.count)
            let centre = CGPoint(x: xs.reduce(0, +) / count, y: ys.reduce(0, +) / count)
            return ClusterGroup(
                id: ids.sorted().joined(separator: "|"),
                landmarkIDs: ids,
                screenCentre: centre
            )
        }
    }

    // MARK: - LAR-51: Cluster Badge

    private func showClusterBadge(_ cluster: ClusterGroup) {
        if let existing = clusterBadgeViews[cluster.id] {
            existing.isHidden = false
            existing.center = cluster.screenCentre
            existing.update(count: cluster.landmarkIDs.count)
        } else {
            let badge = ClusterBadgeView(count: cluster.landmarkIDs.count)
            badge.center = cluster.screenCentre
            badge.onTap = { [weak self] in self?.expandCluster(cluster) }
            arView.addSubview(badge)
            clusterBadgeViews[cluster.id] = badge
        }
    }

    // MARK: - LAR-51: Fan Expansion / Collapse

    private func expandCluster(_ cluster: ClusterGroup) {
        guard case .none = clusterState else { return }

        let displayIDs = Array(cluster.landmarkIDs.prefix(ARLandmarkViewController.maxFanLabels))
        let overflowCount = cluster.landmarkIDs.count - displayIDs.count
        let fanItemCount = displayIDs.count + (overflowCount > 0 ? 1 : 0)
        let positions = ARLandmarkViewController.fanPositions(
            count: fanItemCount, centre: cluster.screenCentre, in: arView.bounds.size)

        if scrimView.superview == nil {
            scrimView.frame = arView.bounds
            arView.insertSubview(scrimView, at: 0)
        }
        scrimView.frame = arView.bounds

        clusterState = .expanded(clusterID: cluster.id, centrePoint: cluster.screenCentre)

        for id in displayIDs {
            guard let label = labelViews[id],
                  let landmark = landmarks.first(where: { $0.id == id }) else { continue }
            label.center = cluster.screenCentre
            label.isHidden = false
            label.alpha = 0
            label.onTap = { [weak self] in
                self?.onSelect?(landmark)
                self?.collapseCluster()
            }
            arView.bringSubviewToFront(label)
        }

        if overflowCount > 0, positions.indices.contains(displayIDs.count) {
            let badge = makeOverflowBadge(count: overflowCount)
            badge.center = cluster.screenCentre
            badge.alpha = 0
            arView.addSubview(badge)
            overflowBadgeView = badge
            arView.bringSubviewToFront(badge)
        }

        clusterBadgeViews[cluster.id]?.isHidden = true

        UIView.animate(withDuration: ARLandmarkViewController.fanAnimationDuration,
                       delay: 0, options: .curveEaseInOut) {
            self.scrimView.alpha = 1
            for (i, id) in displayIDs.enumerated() {
                guard let label = self.labelViews[id] else { continue }
                label.center = positions[i]
                // LAR-48: Fanned labels bypass edge fade — fan layout keeps them on-screen.
                label.alpha = label.distanceAlpha
            }
            if let overflow = self.overflowBadgeView, overflowCount > 0 {
                overflow.center = positions[displayIDs.count]
                overflow.alpha = 1
            }
        }
    }

    private func collapseCluster(animated: Bool = true) {
        guard case .expanded = clusterState else { return }
        clusterState = .none

        let duration = animated ? ARLandmarkViewController.fanAnimationDuration : 0
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseInOut) {
            self.scrimView.alpha = 0
        } completion: { _ in
            self.overflowBadgeView?.removeFromSuperview()
            self.overflowBadgeView = nil
        }

        if !animated {
            scrimView.alpha = 0
            overflowBadgeView?.removeFromSuperview()
            overflowBadgeView = nil
        }

        refreshLabels()
    }

    @objc private func scrimTapped() { collapseCluster() }

    // MARK: - LAR-51: Fan Position Calculation

    /// Returns screen positions for `count` items in a radial fan centred at `centre`.
    /// 2–3 items: semicircle above the tap point. 4+ items: full circle from the top.
    /// Positions are clamped inward if they would extend off-screen.
    static func fanPositions(count: Int, centre: CGPoint, in viewSize: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let r = fanRadius

        let angles: [CGFloat]
        if count <= 3 {
            if count == 1 {
                angles = [-.pi / 2]
            } else {
                let step: CGFloat = .pi / CGFloat(count - 1)
                angles = (0..<count).map { i in -.pi + CGFloat(i) * step }
            }
        } else {
            let step: CGFloat = 2 * .pi / CGFloat(count)
            angles = (0..<count).map { i in -.pi / 2 + CGFloat(i) * step }
        }

        var positions = angles.map { a in CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a)) }

        let adjusted = adjustedCentre(centre, fanPositions: positions, in: viewSize)
        if adjusted != centre {
            let dx = adjusted.x - centre.x
            let dy = adjusted.y - centre.y
            positions = positions.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }
        return positions
    }

    static func adjustedCentre(_ centre: CGPoint,
                                fanPositions positions: [CGPoint],
                                in viewSize: CGSize) -> CGPoint {
        let halfW: CGFloat = 90
        let halfH: CGFloat = 35
        let margin: CGFloat = 8

        guard let minX = positions.map({ $0.x - halfW }).min(),
              let maxX = positions.map({ $0.x + halfW }).max(),
              let minY = positions.map({ $0.y - halfH }).min(),
              let maxY = positions.map({ $0.y + halfH }).max() else { return centre }

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if minX < margin { dx = margin - minX }
        else if maxX > viewSize.width - margin { dx = viewSize.width - margin - maxX }
        if minY < margin { dy = margin - minY }
        else if maxY > viewSize.height - margin { dy = viewSize.height - margin - maxY }

        return CGPoint(x: centre.x + dx, y: centre.y + dy)
    }

    // MARK: - LAR-51: Overflow Badge

    private func makeOverflowBadge(count: Int) -> UIView {
        let text = String(format: NSLocalizedString("ar.cluster.overflow", comment: ""), count)
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.textAlignment = .center
        label.layer.cornerRadius = 13
        label.layer.masksToBounds = true
        label.sizeToFit()
        label.frame = CGRect(x: 0, y: 0, width: label.frame.width + 20, height: 26)
        label.isUserInteractionEnabled = false
        return label
    }

    // MARK: - LAR-51: Helpers

    private func clearClusterBadges() {
        clusterBadgeViews.values.forEach { $0.removeFromSuperview() }
        clusterBadgeViews.removeAll()
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
    // LAR-48: Stores the pure distance-based opacity so showLabel can multiply it by edge fade.
    private(set) var distanceAlpha: CGFloat = 1.0
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
        // LAR-48: Store as distanceAlpha so showLabel can multiply by edge-fade opacity.
        let opacity: CGFloat
        switch distanceMeters {
        case ..<300:      opacity = 1.00
        case 300..<800:   opacity = 0.90
        case 800..<2000:  opacity = 0.75
        case 2000..<5000: opacity = 0.55
        default:          opacity = 0.40
        }
        distanceAlpha = opacity
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

// MARK: - ClusterGroup
// LAR-51: Represents a set of landmark labels whose screen-space centres are close enough
// to be replaced by a single cluster badge. `landmarkIDs` is ordered by significance
// (highest first) so that fan expansion and overflow truncation prioritise important landmarks.

struct ClusterGroup {
    /// Stable identifier: landmark IDs sorted lexicographically and joined by "|".
    let id: String
    /// Landmark IDs in the cluster, highest significance first.
    let landmarkIDs: [String]
    /// Centroid of all member screen positions (badge placement point).
    let screenCentre: CGPoint
}

// MARK: - ClusterState
// LAR-51: Tracks whether a cluster fan is currently open.

enum ClusterState {
    case none
    case expanded(clusterID: String, centrePoint: CGPoint)
}

// MARK: - ClusterBadgeView
// LAR-51: The visual badge that replaces a group of overlapping landmark labels.
// Shows a stack icon (SF Symbol) and the member count, styled as a dark pill.
// Tapping the badge triggers fan expansion via `onTap`.

class ClusterBadgeView: UIView {

    var onTap: (() -> Void)?

    private let iconView = UIImageView()
    private let countLabel = UILabel()

    // Layout constants — fixed pill geometry.
    private static let iconSize: CGFloat = 20
    private static let spacing: CGFloat  = 6
    private static let hPad: CGFloat     = 12
    private static let badgeHeight: CGFloat = 36

    init(count: Int) {
        super.init(frame: .zero)
        setup(count: count)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Updates the displayed count and re-layouts the pill width to fit.
    func update(count: Int) {
        countLabel.text = "\(count)"
        countLabel.sizeToFit()
        let savedCenter = center   // layoutBadge changes frame.size which shifts center
        layoutBadge()
        center = savedCenter
    }

    private func setup(count: Int) {
        backgroundColor = UIColor.black.withAlphaComponent(0.72)
        layer.cornerRadius = 18
        layer.masksToBounds = true

        let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.image = UIImage(systemName: "square.stack.3d.up.fill", withConfiguration: config)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit

        countLabel.text = "\(count)"
        countLabel.font = .systemFont(ofSize: 16, weight: .bold)
        countLabel.textColor = .white
        countLabel.sizeToFit()

        // Pure frame-based layout — no Auto Layout, no UIStackView, no constraints.
        // Mixing TAMIC=true (the default for a frame-managed view) with explicit
        // constraints on self corrupts the hit area; frame math avoids that entirely.
        addSubview(iconView)
        addSubview(countLabel)
        layoutBadge()

        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    /// Computes and applies frame sizes for the badge and its child views.
    private func layoutBadge() {
        let iconSz   = Self.iconSize
        let sp       = Self.spacing
        let hPad     = Self.hPad
        let h        = Self.badgeHeight
        let contentW = iconSz + sp + countLabel.frame.width
        let w        = max(contentW + 2 * hPad, 64)

        // Only update size, not origin — center is managed by the caller via .center.
        frame.size = CGSize(width: w, height: h)

        let startX = (w - contentW) / 2
        iconView.frame    = CGRect(x: startX,
                                   y: (h - iconSz) / 2,
                                   width: iconSz, height: iconSz)
        countLabel.frame  = CGRect(x: startX + iconSz + sp,
                                   y: (h - countLabel.frame.height) / 2,
                                   width: countLabel.frame.width,
                                   height: countLabel.frame.height)
    }

    @objc private func tapped() { onTap?() }
}

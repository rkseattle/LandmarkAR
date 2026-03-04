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
    @Binding var selectedLandmark: Landmark?

    func makeUIViewController(context: Context) -> ARLandmarkViewController {
        ARLandmarkViewController()
    }

    func updateUIViewController(_ vc: ARLandmarkViewController, context: Context) {
        vc.update(landmarks: landmarks, userLocation: userLocation, heading: heading) { landmark in
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
        arView.session.run(config)
        arView.session.delegate = self
    }

    // MARK: - Update from SwiftUI

    func update(landmarks: [Landmark],
                userLocation: CLLocation?,
                heading: CLHeading?,
                onSelect: @escaping (Landmark) -> Void) {
        self.landmarks = landmarks
        self.userLocation = userLocation
        self.heading = heading
        self.onSelect = onSelect

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

        let cameraTransform = arFrame.camera.transform
        let projectionMatrix = arFrame.camera.projectionMatrix(
            for: .landscapeRight,
            viewportSize: arView.bounds.size,
            zNear: 0.1,
            zFar: 1000
        )

        for landmark in landmarks {
            guard let worldPosition = worldPosition(for: landmark, relativeTo: userLocation) else { continue }

            guard let screenPoint = project(worldPosition,
                                            camera: cameraTransform,
                                            projection: projectionMatrix,
                                            viewSize: arView.bounds.size) else {
                labelViews[landmark.id]?.isHidden = true
                continue
            }

            showLabel(for: landmark, at: screenPoint)
        }
    }

    private func worldPosition(for landmark: Landmark, relativeTo userLocation: CLLocation) -> SIMD3<Float>? {
        let bearing = landmark.bearing
        let bearingRad = Float(bearing.toRadians())
        let displayDistance: Float = 80

        let x = displayDistance * sin(bearingRad)
        let z = -displayDistance * cos(bearingRad)
        let y: Float = 0

        return SIMD3<Float>(x, y, z)
    }

    private func project(_ worldPoint: SIMD3<Float>,
                         camera: float4x4,
                         projection: float4x4,
                         viewSize: CGSize) -> CGPoint? {
        let worldPoint4 = SIMD4<Float>(worldPoint.x, worldPoint.y, worldPoint.z, 1)
        let viewSpace = camera.inverse * worldPoint4

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
            let label = LandmarkLabelView(landmark: landmark)
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

class LandmarkLabelView: UIView {

    var onTap: (() -> Void)?
    private let landmark: Landmark
    private let nameLabel = UILabel()
    private let distanceLabel = UILabel()

    init(landmark: Landmark) {
        self.landmark = landmark
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        // LAR-7: No background or border — transparent view, text only
        backgroundColor = .clear

        // Name label
        nameLabel.text = landmark.title
        nameLabel.textColor = .white
        nameLabel.font = UIFont.boldSystemFont(ofSize: 15)
        nameLabel.numberOfLines = 2
        nameLabel.textAlignment = .center
        nameLabel.applyShadow()

        // LAR-9: Distance label — formatted and shown below name
        distanceLabel.text = formattedDistance(landmark.distance)
        distanceLabel.textColor = UIColor.white.withAlphaComponent(0.9)
        distanceLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        distanceLabel.textAlignment = .center
        distanceLabel.applyShadow()

        let stack = UIStackView(arrangedSubviews: [nameLabel, distanceLabel])
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

    // LAR-8: Scale the label so closer landmarks appear larger
    func applyDistanceScale(_ distanceMeters: CLLocationDistance) {
        let scale: CGFloat
        switch distanceMeters {
        case ..<300:        scale = 1.4
        case 300..<800:     scale = 1.2
        case 800..<2000:    scale = 1.0
        case 2000..<5000:   scale = 0.85
        default:            scale = 0.70
        }
        transform = CGAffineTransform(scaleX: scale, y: scale)
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

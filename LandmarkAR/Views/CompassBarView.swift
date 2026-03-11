import SwiftUI
import CoreLocation

// MARK: - CompassBarView (LAR-50)
// A fixed horizontal compass strip pinned to the top of the AR overlay.
// Shows the current heading with tick marks, cardinal/intercardinal labels, and
// off-screen landmark chevrons. Rendered with SwiftUI Canvas for smooth animation.

struct CompassBarView: View {

    let heading: CLHeading?
    let landmarks: [Landmark]
    let userLocation: CLLocation?

    /// Approximate camera field-of-view half-angle for iPhone portrait mode.
    static let fovHalfAngle: Double = 30.0

    /// Total degrees of arc visible across the full width of the bar.
    static let degreesVisible: Double = 90.0

    var body: some View {
        if let heading, heading.headingAccuracy >= 0 {
            CompassStripView(
                heading: heading.trueHeading,
                landmarks: landmarks,
                userLocation: userLocation
            )
        } else {
            CalibratingView()
        }
    }
}

// MARK: - CalibratingView

private struct CalibratingView: View {
    @Environment(\.localeBundle) private var bundle

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.north.line")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            Text("compass.calibrating", bundle: bundle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }
}

// MARK: - CompassStripView

private struct CompassStripView: View {
    let heading: Double
    let landmarks: [Landmark]
    let userLocation: CLLocation?

    private static let degreesVisible = CompassBarView.degreesVisible
    private static let fovHalfAngle   = CompassBarView.fovHalfAngle

    private static let compassLabels: [(Double, String)] = [
        (0,   "N"),
        (45,  "NE"),
        (90,  "E"),
        (135, "SE"),
        (180, "S"),
        (225, "SW"),
        (270, "W"),
        (315, "NW"),
    ]

    var body: some View {
        ZStack {
            Canvas { context, size in
                let width        = size.width
                let centerX      = width / 2
                let ptsPerDegree = width / CompassBarView.degreesVisible

                drawTicks(context: &context, size: size, centerX: centerX, ptsPerDegree: ptsPerDegree)
                drawCompassLabels(context: &context, size: size, centerX: centerX, ptsPerDegree: ptsPerDegree)
                drawChevrons(context: &context, size: size, centerX: centerX, ptsPerDegree: ptsPerDegree)
                drawCenterMarker(context: &context, centerX: centerX)
            }

            // Heading readout centered at the bottom of the bar
            VStack {
                Spacer()
                Text("\(Int(heading.rounded()))°")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.bottom, 3)
            }
        }
        .frame(height: 44)
        .background(.ultraThinMaterial)
    }

    // MARK: - Canvas drawing

    private func drawTicks(
        context: inout GraphicsContext,
        size: CGSize,
        centerX: Double,
        ptsPerDegree: Double
    ) {
        let width = size.width
        let halfVisible = Self.degreesVisible / 2 + 10

        // Start at the nearest 5° boundary to avoid floating-point drift
        var deg = floor((heading - halfVisible) / 5.0) * 5.0
        let endDeg = heading + halfVisible

        while deg <= endDeg {
            let x = CompassBarLogic.xPosition(forDegree: deg, heading: heading, centerX: centerX, ptsPerDegree: ptsPerDegree)
            guard x >= -2, x <= width + 2 else { deg += 5; continue }

            let isMajor = Int(deg.rounded()) % 10 == 0
            let tickHeight: Double = isMajor ? 10 : 6
            let lineWidth: Double  = isMajor ? 1.5 : 1.0

            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: tickHeight))
            context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: lineWidth)

            deg += 5
        }
    }

    private func drawCompassLabels(
        context: inout GraphicsContext,
        size: CGSize,
        centerX: Double,
        ptsPerDegree: Double
    ) {
        let width = size.width

        for (degrees, label) in Self.compassLabels {
            let x = CompassBarLogic.xPosition(forDegree: degrees, heading: heading, centerX: centerX, ptsPerDegree: ptsPerDegree)
            guard x >= 0, x <= width else { continue }

            let isCardinal = label.count == 1
            let font: Font = isCardinal
                ? .system(size: 12, weight: .bold)
                : .system(size: 9, weight: .regular)

            let resolved = context.resolve(
                Text(label).font(font).foregroundColor(.white)
            )
            context.draw(resolved, at: CGPoint(x: x, y: 22), anchor: .center)
        }
    }

    private func drawChevrons(
        context: inout GraphicsContext,
        size: CGSize,
        centerX: Double,
        ptsPerDegree: Double
    ) {
        guard let userLocation else { return }
        let width = size.width
        let edgePadding: Double = 8

        for landmark in landmarks {
            let bearing   = userLocation.coordinate.bearing(to: landmark.coordinate)
            let angleDiff = CompassBarLogic.normalizedDiff(bearing - heading)

            // Only render for landmarks outside the camera field of view
            guard CompassBarLogic.isOffScreen(angleDiff: angleDiff, fovHalfAngle: Self.fovHalfAngle) else { continue }

            let rawX = centerX + angleDiff * ptsPerDegree
            let x    = max(edgePadding, min(width - edgePadding, rawX))

            let chevSize = CompassBarLogic.chevronSize(for: landmark.significanceScore)
            let chevTop  = size.height - chevSize - 3

            var path = Path()
            path.move(to: CGPoint(x: x, y: chevTop))
            path.addLine(to: CGPoint(x: x - chevSize / 2, y: chevTop + chevSize))
            path.addLine(to: CGPoint(x: x + chevSize / 2, y: chevTop + chevSize))
            path.closeSubpath()
            context.fill(path, with: .color(.white.opacity(0.75)))
        }
    }

    private func drawCenterMarker(context: inout GraphicsContext, centerX: Double) {
        // Solid white inverted triangle at the top-center of the bar, pointing down
        let size: Double = 7
        var path = Path()
        path.move(to: CGPoint(x: centerX - size / 2, y: 0))
        path.addLine(to: CGPoint(x: centerX + size / 2, y: 0))
        path.addLine(to: CGPoint(x: centerX, y: size))
        path.closeSubpath()
        context.fill(path, with: .color(.white))
    }
}

// MARK: - CompassBarLogic
// Pure functions extracted for unit testing (LAR-50).

enum CompassBarLogic {

    /// Normalizes an angle difference to the range [-180, 180].
    static func normalizedDiff(_ diff: Double) -> Double {
        var d = diff.truncatingRemainder(dividingBy: 360)
        if d > 180  { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// Returns true when a landmark at `angleDiff` degrees from the current heading
    /// lies outside the camera field of view (|angleDiff| > fovHalfAngle).
    static func isOffScreen(angleDiff: Double, fovHalfAngle: Double = CompassBarView.fovHalfAngle) -> Bool {
        abs(angleDiff) > fovHalfAngle
    }

    /// Maps a significance score to a chevron size in points.
    /// Score range: ~400 (regular) … 8000+ (iconic). Output: [5, 10] pts.
    static func chevronSize(for score: Double, min minSize: Double = 5.0, max maxSize: Double = 10.0) -> Double {
        let normalized = Swift.min(sqrt(score / 10_000.0), 1.0)
        return minSize + normalized * (maxSize - minSize)
    }

    /// Returns the x position on the bar for a compass degree relative to the current heading.
    static func xPosition(forDegree degree: Double, heading: Double, centerX: Double, ptsPerDegree: Double) -> Double {
        let diff = normalizedDiff(degree - heading)
        return centerX + diff * ptsPerDegree
    }
}

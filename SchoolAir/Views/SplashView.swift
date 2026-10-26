import SwiftUI

/// The app icon, drawn live: the ring sweeps in, the cap settles, the name fades up,
/// then the whole thing gives way to the Now screen. Honors Reduce Motion.
struct SplashView: View {
    /// Keep the splash on screen (launch argument `-splash hold`, for screenshots).
    var holds = false
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var ringProgress: CGFloat = 0
    @State private var capVisible = false
    @State private var markerVisible = false
    @State private var titleVisible = false

    /// 270° of the circle, open at the bottom, like the icon.
    private let sweep: CGFloat = 0.75
    /// Where the marker sits along the ring.
    private let markerFraction: CGFloat = 0.33
    private let ringSize: CGFloat = 224
    private let lineWidth: CGFloat = 22

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 40) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: ringProgress * sweep)
                        .stroke(ringGradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(135))
                        .frame(width: ringSize, height: ringSize)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 8, y: 4)

                    marker
                        .opacity(markerVisible ? 1 : 0)

                    SchoolAirCap()
                        .fill(capGradient)
                        .frame(width: 116, height: 80)
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.18), radius: 14, y: 8)
                        .scaleEffect(capVisible ? 1 : 0.6)
                        .opacity(capVisible ? 1 : 0)
                        .offset(y: -4)
                }
                .frame(width: ringSize + lineWidth, height: ringSize + lineWidth)

                Text("School Air")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .opacity(titleVisible ? 1 : 0)
                    .offset(y: titleVisible ? 0 : 12)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("School Air")
        }
        .task { await play() }
    }

    private var ringGradient: AngularGradient {
        // The circle is rotated 135° after this gradient is painted, so the sweep starts at 0° here.
        AngularGradient(
            colors: [.green, .yellow, .orange, .red, .purple],
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(270)
        )
    }

    /// Same blues as the icon: a touch brighter in dark mode so the cap still pops.
    private var capGradient: LinearGradient {
        let colors = colorScheme == .dark
            ? [Color(red: 0.38, green: 0.71, blue: 1.0), Color(red: 0.06, green: 0.42, blue: 0.96)]
            : [Color(red: 0.25, green: 0.61, blue: 1.0), Color(red: 0.0, green: 0.35, blue: 0.86)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var marker: some View {
        let angle = Angle.degrees(135 + 270 * Double(markerFraction)).radians
        let radius = ringSize / 2
        return Circle()
            .fill(Color(red: 0.0, green: 0.38, blue: 0.9))
            .frame(width: 10, height: 10)
            .padding(5)
            .background(Color(.systemBackground), in: Circle())
            .offset(x: radius * cos(angle), y: radius * sin(angle))
    }

    private func play() async {
        if reduceMotion {
            ringProgress = 1
            capVisible = true
            markerVisible = true
            titleVisible = true
            try? await Task.sleep(for: .seconds(1.0))
        } else {
            withAnimation(.easeOut(duration: 0.9)) { ringProgress = 1 }
            try? await Task.sleep(for: .seconds(0.35))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) { capVisible = true }
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeOut(duration: 0.3)) { markerVisible = true }
            withAnimation(.easeOut(duration: 0.4)) { titleVisible = true }
            try? await Task.sleep(for: .seconds(1.0))
        }
        guard !Task.isCancelled else { return }
        if !holds {
            onFinished()
        }
    }
}

#Preview {
    SplashView(holds: true) {}
}

/// Matches the shipping icon: shallow blue mortarboard, crown, and tassel on the right.
private struct SchoolAirCap: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
        p.move(to: point(0.78, 0.44))
        p.addCurve(to: point(0.22, 0.44), control1: point(0.82, 1.00), control2: point(0.18, 1.00))
        p.closeSubpath()
        p.move(to: point(0.48, 0.03))
        p.addQuadCurve(to: point(0.52, 0.03), control: point(0.50, 0.01))
        p.addLine(to: point(0.97, 0.33))
        p.addQuadCurve(to: point(0.97, 0.45), control: point(1.03, 0.39))
        p.addLine(to: point(0.52, 0.73))
        p.addQuadCurve(to: point(0.48, 0.73), control: point(0.50, 0.75))
        p.addLine(to: point(0.03, 0.45))
        p.addQuadCurve(to: point(0.03, 0.33), control: point(-0.03, 0.39))
        p.closeSubpath()
        p.move(to: point(0.91, 0.40))
        p.addLine(to: point(0.95, 0.40))
        p.addLine(to: point(0.97, 0.88))
        p.addLine(to: point(0.93, 0.88))
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: rect.minX + rect.width * 0.89, y: rect.minY + rect.height * 0.83,
                               width: rect.width * 0.12, height: rect.height * 0.17))
        return p
    }
}

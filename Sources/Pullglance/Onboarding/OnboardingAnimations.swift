import SwiftUI

/// Steps through `phases` in order, forever, holding each for `hold` and animating into the next with
/// `animation`. With Reduce Motion on it shows the last phase and never moves. (`PhaseAnimator` was tried
/// first: it stretched the column it sat in and hid text mid-transition.)
struct PhaseLoop<Phase: Hashable, Content: View>: View {
    let phases: [Phase]
    let hold: (Phase) -> Duration
    let animation: (Phase) -> Animation
    @ViewBuilder let content: (Phase) -> Content

    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(reduceMotion ? phases[phases.count - 1] : phases[index])
            .task(id: reduceMotion) {
                guard !reduceMotion else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: hold(phases[index]))
                    if Task.isCancelled { return }
                    let next = (index + 1) % phases.count
                    withAnimation(animation(phases[next])) { index = next }
                }
            }
    }
}

/// The drawn menu bar count rolling 2 → 5 with an orange ring at the end, and the tab picker switching.
struct BadgeAndTabsAnimation: View {
    private enum Phase: CaseIterable { case two, three, four, five, review }

    var body: some View {
        PhaseLoop(phases: Phase.allCases, hold: { phase in
            switch phase {
            case .five: .milliseconds(1200)
            case .review: .milliseconds(1500)
            default: .milliseconds(600)
            }
        }, animation: { _ in .easeInOut(duration: 0.3) }) { phase in
            frame(for: phase)
        }
    }
    private func frame(for phase: Phase) -> some View {
        let count: Int = { switch phase { case .two: 2; case .three: 3; case .four: 4; case .five, .review: 5 } }()
        return ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.background).strokeBorder(.quaternary)
            VStack(alignment: .trailing, spacing: 14) {
                HStack(spacing: 10) {
                    Text(verbatim: "Wed 21:30").foregroundStyle(.white.opacity(0.7))
                    Image(systemName: "arrow.triangle.pull").foregroundStyle(.white)
                    Text(verbatim: "\(count)").foregroundStyle(.white).monospacedDigit()
                        .contentTransition(.numericText(countsDown: false))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).frame(height: 24)
                .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.orange, lineWidth: 2).padding(-3).opacity(phase == .five ? 1 : 0))
                tabs(selected: phase == .review ? 1 : 0)
            }
            .padding(14)
        }
    }

    private func tabs(selected: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { index in
                HStack(spacing: 6) {
                    Text(index == 0 ? "My PRs" : "To review", bundle: .app).fontWeight(.semibold)
                    Text(verbatim: index == 0 ? "2" : "21").foregroundStyle(.secondary)
                }
                .font(.system(size: 11)).frame(maxWidth: .infinity).frame(height: 20)
                .background(index == selected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
                .shadow(color: .black.opacity(index == selected ? 0.12 : 0), radius: 1, y: 1)
            }
        }
        .padding(3).frame(width: 240)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// A fictional row sliding open to its tiles, closing, then taking the keyboard focus ring.
struct RowActionsAnimation: View {
    private enum Phase: CaseIterable { case rest, open, closed, focused }

    var body: some View {
        PhaseLoop(phases: Phase.allCases, hold: { phase in
            switch phase {
            case .rest: .milliseconds(600)
            case .open: .milliseconds(1200)
            case .closed: .milliseconds(500)
            case .focused: .milliseconds(1200)
            }
        }, animation: { phase in
            switch phase {
            case .open, .closed: .snappy(duration: 0.35)
            case .focused, .rest: .easeOut(duration: 0.2)
            }
        }) { phase in
            frame(for: phase)
        }
    }

    private func frame(for phase: Phase) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.background).strokeBorder(.quaternary)
            VStack(alignment: .leading, spacing: 10) {
                ZStack(alignment: .trailing) {
                    HStack(spacing: 0) {
                        tile("pin", Text("Pin", bundle: .app), .blue)
                        tile("moon.zzz", Text("Snooze", bundle: .app), .orange)
                        tile("text.bubble", Text("Comment", bundle: .app), .gray)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Retry uploads on 5xx").font(.system(size: 12))
                        Text(verbatim: "acme/web #412 · alice · 2 h").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 44)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .offset(x: phase == .open ? -162 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 2).opacity(phase == .focused ? 1 : 0))
                HStack(spacing: 8) {
                    keyCap("↓", pressed: phase == .focused)
                    Text("moves the focus", bundle: .app)
                    keyCap("P", pressed: false); keyCap("S", pressed: false); keyCap("O", pressed: false)
                    Text("act on it", bundle: .app)
                    Spacer()
                    Text(verbatim: "⌘/").foregroundStyle(.secondary)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(14)
        }
    }

    private func tile(_ symbol: String, _ label: Text, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 13))
            label.font(.system(size: 9))
        }
        .foregroundStyle(.white).frame(width: 54, height: 44).background(color)
    }

    private func keyCap(_ key: String, pressed: Bool) -> some View {
        Text(verbatim: key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .frame(width: 22, height: 20)
            .background(.background, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
            .offset(y: pressed ? 1.5 : 0)
    }
}

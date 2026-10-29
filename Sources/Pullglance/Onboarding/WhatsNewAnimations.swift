import SwiftUI

// The what's new drawings: `PhaseLoop`s in the welcome's style (a card, a fictional row, key caps),
// 120pt tall, playing only while their screen is active. Fictional content stays verbatim; the few labels
// the app itself shows use the app's own keys.

/// The card every drawing sits in.
private struct DrawingCard<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.background).strokeBorder(.quaternary)
            content().padding(14)
        }
    }
}

/// A drawn popover row: dot, title, metadata line and pills, the way `PRRow` lays them out.
private struct DrawnRow<Dot: View, Pills: View>: View {
    let title: String
    let meta: String
    @ViewBuilder let dot: () -> Dot
    @ViewBuilder let pills: () -> Pills
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            dot().frame(width: 16, height: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.system(size: 12)).lineLimit(1)
                HStack(spacing: 4) {
                    Text(verbatim: meta).font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if let trailing { trailing }
                }
                HStack(spacing: 4) { pills() }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
    }
}

private struct DrawnPill: View {
    let text: Text
    var tint: Color = .gray
    var body: some View {
        text.font(.system(size: 9.5))
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .foregroundStyle(tint.mix(with: .primary, by: 0.45))
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
    }
}

private struct DrawnDot: View {
    let color: Color
    var symbol: String? = "checkmark"
    var body: some View {
        ZStack {
            Circle().fill(color).frame(width: 14, height: 14)
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)).foregroundStyle(.white) }
        }
    }
}

struct KeyCap: View {
    let key: String
    var pressed = false
    var width: CGFloat = 22
    var body: some View {
        Text(verbatim: key)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .frame(width: width, height: 20)
            .background(.background, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(pressed ? Color.accentColor : Color(nsColor: .quaternaryLabelColor), lineWidth: pressed ? 1.5 : 1))
            .offset(y: pressed ? 1.5 : 0)
    }
}

/// A watched row gets its bell, then the notification card slides in when the checks pass.
struct WatchAnimation: View {
    private enum Phase: CaseIterable { case rest, watched, notified }

    var body: some View {
        PhaseLoop(phases: Phase.allCases, hold: { phase in
            switch phase { case .rest: .milliseconds(700); case .watched: .milliseconds(1100); case .notified: .milliseconds(2200) }
        }, animation: { phase in
            switch phase { case .notified: .spring(duration: 0.5, bounce: 0.2); default: .easeOut(duration: 0.25) }
        }) { phase in
            DrawingCard {
                ZStack(alignment: .bottomTrailing) {
                    VStack {
                        DrawnRow(title: "Split the billing worker from the API", meta: "web #388 · 5 days ago",
                                 dot: { DrawnDot(color: .green) },
                                 pills: { DrawnPill(text: Text("Approved", bundle: .app), tint: .green) },
                                 trailing: AnyView(Image(systemName: "bell.fill").font(.system(size: 9)).foregroundStyle(.orange).opacity(phase == .rest ? 0 : 1)))
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Color(red: 0.95, green: 0.61, blue: 0.47), Color(red: 0.85, green: 0.43, blue: 0.31)], startPoint: .top, endPoint: .bottom)).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Checks passed", bundle: .app).font(.system(size: 11, weight: .semibold))
                            Text(verbatim: "#388 Split the billing worker from the API").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .padding(8).frame(width: 230, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                    .offset(y: phase == .notified ? 0 : 90)
                    .opacity(phase == .notified ? 1 : 0)
                }
            }
        }
    }
}

/// The Desk's file pill stepping through files on ⌘J while the viewed count grows.
struct DeskKeysAnimation: View {
    private static let files = ["src/api/upload.ts", "src/api/retry.ts", "src/ui/Settings.tsx", "tests/upload.test.ts"]

    var body: some View {
        PhaseLoop(phases: Array(Self.files.indices), hold: { _ in .milliseconds(1300) }, animation: { _ in .easeInOut(duration: 0.25) }) { index in
            DrawingCard {
                VStack(spacing: 10) {
                    HStack {
                        Text("Files", bundle: .app).font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text(verbatim: "\(3 + index) of 12 viewed").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit().contentTransition(.numericText(countsDown: false))
                    }
                    .padding(.horizontal, 10).frame(height: 24)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.quaternary))
                    HStack(spacing: 8) {
                        KeyCap(key: "⌘J", pressed: index % 2 == 1, width: 30)
                        KeyCap(key: "⌘K", width: 30)
                        KeyCap(key: "⌘E", width: 30)
                        Spacer()
                        Text(verbatim: "⌘/").foregroundStyle(.secondary).font(.system(size: 11))
                    }
                    HStack(spacing: 10) {
                        Text(verbatim: "⌘K ‹").foregroundStyle(.white.opacity(0.6))
                        Text(verbatim: Self.files[index]).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.white).frame(minWidth: 150)
                            .id(index).transition(.opacity)
                        Text(verbatim: "› ⌘J").foregroundStyle(.white.opacity(0.6))
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 12).frame(height: 24)
                    .background(Color(white: 0.14), in: Capsule())
                }
            }
        }
    }
}

/// The dot turning from the green of the checks to the purple of a merge GitHub will do.
struct HandoffAnimation: View {
    private enum Phase: CaseIterable { case yours, queued }

    var body: some View {
        PhaseLoop(phases: Phase.allCases, hold: { phase in
            switch phase { case .yours: .milliseconds(1300); case .queued: .milliseconds(2200) }
        }, animation: { _ in .easeInOut(duration: 0.35) }) { phase in
            DrawingCard {
                VStack(spacing: 12) {
                    DrawnRow(title: "Bump the uploader to the new SDK", meta: "web #377 · 2 days ago",
                             dot: { DrawnDot(color: phase == .queued ? Color(red: 0.51, green: 0.31, blue: 0.87) : .green, symbol: phase == .queued ? "line.3.horizontal" : "checkmark") },
                             pills: {
                                 DrawnPill(text: Text("Approved", bundle: .app), tint: .green)
                                 if phase == .queued { DrawnPill(text: Text(verbatim: String(format: String(localized: "In queue · %lld", bundle: .app), 2)), tint: .purple).transition(.opacity) }
                             })
                    HStack(spacing: 16) {
                        Label { Text("yours to merge", bundle: .app).foregroundStyle(.secondary) } icon: { Circle().fill(.green).frame(width: 9, height: 9) }
                        Label { Text("GitHub merges it", bundle: .app).foregroundStyle(.secondary) } icon: { Circle().fill(Color(red: 0.51, green: 0.31, blue: 0.87)).frame(width: 9, height: 9) }
                        Spacer()
                    }
                    .font(.system(size: 10.5))
                }
            }
        }
    }
}

/// Three rows of one stack: their pills, then the filter on, with the rail between the dots and the chip.
struct StacksAnimation: View {
    private enum Phase: CaseIterable { case pills, filtered }

    var body: some View {
        PhaseLoop(phases: Phase.allCases, hold: { phase in
            switch phase { case .pills: .milliseconds(1600); case .filtered: .milliseconds(2400) }
        }, animation: { _ in .easeInOut(duration: 0.35) }) { phase in
            DrawingCard {
                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            HStack(spacing: 8) {
                                ZStack {
                                    Rectangle().fill(Color.secondary.opacity(0.45)).frame(width: 2)
                                        .padding(.top, index == 0 ? 10 : -4).padding(.bottom, index == 2 ? 10 : -4)
                                        .opacity(phase == .filtered ? 1 : 0)
                                    DrawnDot(color: [Color.green, .red, .gray][index], symbol: index == 1 ? "xmark" : index == 2 ? nil : "checkmark")
                                }
                                .frame(width: 16)
                                Text(verbatim: ["Auth middleware", "Get-user endpoints", "Account page"][index]).font(.system(size: 11.5)).lineLimit(1)
                                DrawnPill(text: Text(verbatim: "⧉ \(index + 1) of 3"))
                                Spacer()
                            }
                            .frame(height: 24)
                        }
                    }
                    Text(verbatim: String(format: String(localized: "Stack #%lld", bundle: .app), 7))
                        .font(.system(size: 10)).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule()).foregroundStyle(Color.accentColor)
                        .offset(x: 200, y: 4)
                        .opacity(phase == .filtered ? 1 : 0)
                }
            }
        }
    }
}

/// The focus ring walking down the rows on J, with the keys that drive the list.
struct KeyboardAnimation: View {
    var body: some View {
        PhaseLoop(phases: [0, 1, 2], hold: { _ in .milliseconds(900) }, animation: { _ in .easeOut(duration: 0.2) }) { focused in
            DrawingCard {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { index in
                            HStack(spacing: 8) {
                                DrawnDot(color: [Color.green, .yellow, .green][index], symbol: index == 1 ? nil : "checkmark")
                                Text(verbatim: ["Retry uploads on 5xx", "Migrate checkout to the new API", "Rate limit the webhook fan-out"][index]).font(.system(size: 11.5)).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8).frame(height: 20)
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).opacity(index == focused ? 1 : 0))
                        }
                    }
                    HStack(spacing: 6) {
                        KeyCap(key: "J", pressed: true); KeyCap(key: "K"); KeyCap(key: "H"); KeyCap(key: "L")
                        Text(verbatim: "·").foregroundStyle(.tertiary)
                        KeyCap(key: "F"); KeyCap(key: "␣", width: 30)
                        Spacer()
                        Text(verbatim: "⌘/").foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                }
            }
        }
    }
}

/// A teammate's pull request assigned to you: the author on the row, the Assigned chip above.
struct AssignedAnimation: View {
    private enum Phase: CaseIterable { case row, chip }

    var body: some View {
        PhaseLoop(phases: Phase.allCases, hold: { phase in
            switch phase { case .row: .milliseconds(900); case .chip: .milliseconds(2200) }
        }, animation: { _ in .easeOut(duration: 0.3) }) { phase in
            DrawingCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach([Text("All", bundle: .app), Text("Action", bundle: .app), Text("Ready", bundle: .app)].indices, id: \.self) { index in
                            [Text("All", bundle: .app), Text("Action", bundle: .app), Text("Ready", bundle: .app)][index]
                                .font(.system(size: 10.5)).padding(.horizontal, 8).padding(.vertical, 2)
                                .background(.quaternary, in: Capsule())
                        }
                        Text("Assigned", bundle: .app).font(.system(size: 10.5)).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Color.primary, in: Capsule()).foregroundStyle(Color(nsColor: .windowBackgroundColor))
                            .opacity(phase == .chip ? 1 : 0)
                    }
                    DrawnRow(title: "Fix flaky retry in the uploader", meta: "web #412 · alice · 2 hr ago",
                             dot: { DrawnDot(color: .green) },
                             pills: { DrawnPill(text: Text("Approved", bundle: .app), tint: .green) },
                             trailing: AnyView(Circle().fill(Color(red: 0.95, green: 0.61, blue: 0.47)).frame(width: 14, height: 14).overlay(Text(verbatim: "a").font(.system(size: 8, weight: .bold)).foregroundStyle(.white))))
                }
            }
        }
    }
}

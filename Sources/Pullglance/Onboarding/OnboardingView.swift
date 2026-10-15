import AppKit
import SwiftUI

/// The welcome window's content: the flea, a title, a text, the step's content, and a footer with Back,
/// the progress dots and the primary button. `step` is owned by the window controller so ← → and Esc
/// can drive it from AppKit.
struct OnboardingView: View {
    @Bindable var store: PRStore
    let checker: RequirementChecker
    @Binding var step: Int
    let finish: () -> Void
    let quit: () -> Void

    private var current: OnboardingStep { OnboardingStep.all[step] }
    private var isGhStep: Bool { current.content == .requirements }
    private var canContinue: Bool { !isGhStep || checker.allPassed }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                MascotImage(isGhStep && checker.allPassed ? .celebrating : current.pose, size: 84)
                    .padding(.top, 6)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                VStack(alignment: .leading, spacing: 8) {
                    Text(LocalizedStringKey(current.title), bundle: .app).font(.system(size: 21, weight: .bold))
                    Text(LocalizedStringKey(current.text), bundle: .app).font(.system(size: 12.5)).foregroundStyle(.secondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    content.padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(EdgeInsets(top: 44, leading: 30, bottom: 16, trailing: 30))
            .frame(maxHeight: .infinity, alignment: .top)
            .id(step)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            footer
        }
        .frame(width: 560, height: 400)
        .background(.windowBackground)
        .animation(.easeOut(duration: 0.3), value: step)
        .onChange(of: step, initial: true) { _, _ in
            if isGhStep { checker.start() } else { checker.stop() }
        }
    }

    @ViewBuilder private var content: some View {
        switch current.content {
        case .none: EmptyView()
        case .requirements: requirements
        case .badgeAndTabs: BadgeAndTabsAnimation().frame(height: 120)
        case .rowActions: RowActionsAnimation().frame(height: 120)
        case .notifications:
            requirementRow(symbol: "bell.badge", tint: .orange, title: Text("Notify when a snooze ends", bundle: .app),
                           detail: Text("Optional. macOS asks once; you can change it in Settings later.", bundle: .app)) {
                Toggle(isOn: $store.notifiesSnoozeEnd) { EmptyView() }.labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        }
    }

    private var requirements: some View {
        VStack(spacing: 7) {
            stateRow(checker.installed, title: Text("gh is installed", bundle: .app),
                     pending: Text("Looking in /opt/homebrew/bin, /usr/local/bin and PATH…", bundle: .app)) {
                Button { NSWorkspace.shared.open(URL(string: "https://cli.github.com")!) } label: { Text("Install with Homebrew", bundle: .app) }
            }
            stateRow(checker.loggedIn, title: Text("gh is logged in", bundle: .app),
                     pending: Text("Run gh auth login in Terminal. I keep checking.", bundle: .app)) {
                Button {
                    let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
                    NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
                } label: { Text("Open Terminal", bundle: .app) }
            }
        }
    }

    /// A requirement row: a status dot that pulses while checking and pops to a check when it passes.
    private func stateRow(_ state: RequirementState, title: Text, pending: Text, @ViewBuilder fix: () -> some View) -> some View {
        let detail: Text = {
            switch state {
            case .ok(let text): Text(verbatim: text)
            case .failed(let message): Text("Couldn't check: \(message)", bundle: .app)
            case .unknown, .checking, .missing: pending
            }
        }()
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(state.passed ? Color.green : state == .checking ? Color.orange : Color.gray.opacity(0.4)).frame(width: 20, height: 20)
                Image(systemName: state.passed ? "checkmark" : "ellipsis").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .symbolEffect(.pulse, isActive: state == .checking)
            VStack(alignment: .leading, spacing: 1) {
                title.font(.system(size: 12.5, weight: .semibold))
                detail.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if case .missing = state { fix().controlSize(.small) }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary))
        .animation(.easeOut(duration: 0.25), value: state)
    }

    private func requirementRow(symbol: String, tint: Color, title: Text, detail: Text, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(tint).frame(width: 20, height: 20)
                Image(systemName: symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                title.font(.system(size: 12.5, weight: .semibold))
                detail.font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing()
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        .background(.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.quaternary))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step == 0 {
                Color.clear.frame(width: 1)
            } else if isGhStep, checker.installed == .missing {
                Button(action: quit) { Text("Quit", bundle: .app) }.buttonStyle(.plain).foregroundStyle(.red)
            } else {
                Button { step -= 1 } label: { Text("Back", bundle: .app) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingStep.all.indices, id: \.self) { index in
                    Capsule().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            Spacer()
            Button {
                if step == OnboardingStep.all.count - 1 { finish() } else { step += 1 }
            } label: {
                Text(LocalizedStringKey(current.button), bundle: .app).frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!canContinue)
        }
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

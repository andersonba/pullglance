import AppKit
import SwiftUI

/// Which step is showing. Owned by the window controller so ← → and Esc can drive it from AppKit; the
/// view animates every change of `step`.
@MainActor
@Observable
final class OnboardingModel {
    var step: Int

    init(step: Int = 0) { self.step = step }

    func go(to index: Int) {
        guard OnboardingStep.all.indices.contains(index), index != step else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.18)) { step = index }
    }
}

/// The welcome window's content: the flea, a title, a text, the step's content, and a footer with Back,
/// the progress dots and the primary button. Every step stays in the tree; each one is offset and faded
/// by its distance to the current step, so going forward and back are mirror images of each other and
/// nothing is inserted or removed mid-animation. The flea hops on every change.
struct OnboardingView: View {
    @Bindable var store: PRStore
    let checker: RequirementChecker
    @Bindable var model: OnboardingModel
    /// gh just passed: the window counts as completed from here on, whatever way it goes away (⌘Q too).
    var ghPassed: () -> Void = {}
    let finish: () -> Void
    let quit: () -> Void

    @State private var hop = false

    private var step: Int { model.step }
    private var current: OnboardingStep { OnboardingStep.all[step] }
    private var isGhStep: Bool { current.content == .requirements }
    private var canContinue: Bool { !isGhStep || checker.allPassed }
    private var pose: MascotPose { isGhStep && checker.allPassed ? .celebrating : current.pose }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                mascot
                ZStack(alignment: .topLeading) {
                    ForEach(Array(OnboardingStep.all.enumerated()), id: \.element.id) { index, item in
                        column(for: item, active: index == step)
                            .offset(x: CGFloat(index - step) * 56)
                            .opacity(index == step ? 1 : 0)
                            .scaleEffect(index == step ? 1 : 0.96, anchor: .leading)
                            .allowsHitTesting(index == step)
                            .accessibilityHidden(index != step)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .clipped()
            }
            .padding(EdgeInsets(top: 44, leading: 30, bottom: 16, trailing: 30))
            .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .frame(width: 560, height: 400)
        .background(.windowBackground)
        .onChange(of: step, initial: true) { _, _ in
            if isGhStep { checker.start() } else { checker.stop() }
        }
        .onChange(of: checker.allPassed) { _, passed in
            if passed { ghPassed() }
        }
        .onChange(of: step) { _, _ in
            withAnimation(.spring(duration: 0.3, bounce: 0.55)) { hop = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.spring(duration: 0.4, bounce: 0.35)) { hop = false }
            }
        }
    }

    /// The pose crossfades; the whole flea hops up a little and lands on each step change.
    private var mascot: some View {
        ZStack {
            MascotImage(pose, size: 84)
                .id(pose)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: pose)
        .scaleEffect(hop ? 1.08 : 1, anchor: .bottom)
        .offset(y: hop ? -10 : 0)
        .padding(.top, 6)
    }

    private func column(for item: OnboardingStep, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(item.title), bundle: .app).font(.system(size: 21, weight: .bold))
            Text(LocalizedStringKey(item.text), bundle: .app).font(.system(size: 12.5)).foregroundStyle(.secondary).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            content(for: item, active: active).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func content(for item: OnboardingStep, active: Bool) -> some View {
        switch item.content {
        case .none: EmptyView()
        case .requirements: requirements
        case .badgeAndTabs: if active { BadgeAndTabsAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .rowActions: if active { RowActionsAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
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
            switch state {
            case .missing, .failed: fix().controlSize(.small)
            default: EmptyView()
            }
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
                Button { model.go(to: step - 1) } label: { Text("Back", bundle: .app) }.buttonStyle(.plain).foregroundStyle(.secondary)
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
                if step == OnboardingStep.all.count - 1 { finish() } else { model.go(to: step + 1) }
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

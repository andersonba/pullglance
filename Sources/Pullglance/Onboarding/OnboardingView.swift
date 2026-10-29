import AppKit
import KeyboardShortcuts
import SwiftUI

/// Which step is showing. Owned by the window controller so ← → and Esc can drive it from AppKit; the
/// view animates every change of `step`.
@MainActor
@Observable
final class OnboardingModel {
    /// The list this window shows: the welcome's steps, or a what's new selection.
    let steps: [OnboardingStep]
    var step: Int

    init(steps: [OnboardingStep], step: Int = 0) {
        self.steps = steps
        self.step = step
    }

    func go(to index: Int) {
        guard steps.indices.contains(index), index != step else { return }
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
    /// The welcome, or the what's new tour: same shell, a version label per screen, Next and Done.
    var style: Style = .welcome
    enum Style { case welcome, whatsNew }
    /// gh just passed: the window counts as completed from here on, whatever way it goes away (⌘Q too).
    var ghPassed: () -> Void = {}
    let finish: () -> Void
    let quit: () -> Void

    @State private var hop = false

    private var step: Int { model.step }
    private var steps: [OnboardingStep] { model.steps }
    private var current: OnboardingStep { steps[step] }
    private var isLast: Bool { step == steps.count - 1 }
    /// The list is newest release first: the first step's version is the current release.
    private var newestVersion: String? { steps.first?.version }
    private var isGhStep: Bool { current.content == .requirements }
    private var canContinue: Bool { !isGhStep || checker.allPassed }
    private var pose: MascotPose { isGhStep && checker.allPassed ? .celebrating : current.pose }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 20) {
                mascot
                ZStack(alignment: .topLeading) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { index, item in
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
            if style == .whatsNew, let version = item.version {
                // The release the screen belongs to; an older one (a catch-up screen) in grey.
                Text(verbatim: String(format: String(localized: "New in %@", bundle: .app), version))
                    .font(.system(size: 10.5, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                    .foregroundStyle(version == newestVersion ? Color.accentColor : Color.secondary)
                    .padding(.bottom, -2)
            }
            Text(LocalizedStringKey(item.title), bundle: .app).font(.system(size: 21, weight: .bold))
            Text(LocalizedStringKey(item.text), bundle: .app).font(.system(size: 12.5)).foregroundStyle(.secondary).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            content(for: item, active: active).padding(.top, 4)
            if case .openURL(let url) = item.tryIt {
                Button { NSWorkspace.shared.open(url) } label: { Text("Release notes", bundle: .app) }.controlSize(.small).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func content(for item: OnboardingStep, active: Bool) -> some View {
        switch item.content {
        case .none: EmptyView()
        case .requirements: requirements
        case .badgeAndTabs: if active { BadgeAndTabsAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .rowActions: if active { RowActionsAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .hotkey:
            requirementRow(symbol: "keyboard", tint: .blue, title: Text("Open the popover", bundle: .app),
                           detail: Text("From any app. Click to change; ⌫ removes it.", bundle: .app)) {
                KeyboardShortcuts.Recorder(for: .togglePopover) { EmptyView() }.controlSize(.small)
            }
        case .notifications:
            requirementRow(symbol: "bell.badge", tint: .orange, title: Text("Notify when a snooze ends", bundle: .app),
                           detail: Text("Optional. macOS asks once; you can change it in Settings later.", bundle: .app)) {
                Toggle(isOn: $store.notifiesSnoozeEnd) { EmptyView() }.labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
        case .watch: if active { WatchAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .deskKeys: if active { DeskKeysAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .handoff: if active { HandoffAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .stacks: if active { StacksAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .keyboard: if active { KeyboardAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .assigned: if active { AssignedAnimation().frame(height: 120) } else { Color.clear.frame(height: 120) }
        case .more(let bullets):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text(verbatim: "•").foregroundStyle(.tertiary)
                        Text(LocalizedStringKey(bullet), bundle: .app).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
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
                ForEach(steps.indices, id: \.self) { index in
                    // A thin bar where the release changes: the catch-up screens read as their own group.
                    if style == .whatsNew, index > 0, steps[index].version != steps[index - 1].version {
                        Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: 1, height: 10).padding(.horizontal, 2)
                    }
                    Capsule().fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: index == step ? 18 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: step)
            Spacer()
            Button {
                if isLast { finish() } else { model.go(to: step + 1) }
            } label: {
                primaryLabel.frame(minWidth: 72)
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

    /// The welcome's steps name their button; the tour's say Next, and Done on the last screen.
    private var primaryLabel: Text {
        switch style {
        case .welcome: Text(LocalizedStringKey(current.button), bundle: .app)
        case .whatsNew: isLast ? Text("Done", bundle: .app) : Text("Next", bundle: .app)
        }
    }
}

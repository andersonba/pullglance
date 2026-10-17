import SwiftUI

struct ReviewSettingsView: View {
    @Bindable private var store = ReviewSettingsStore.shared
    @State private var choosingTests = false

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker(selection: $store.settings.landing) {
                    Text("Files", bundle: .app).tag(PullRequestLanding.files)
                    Text("Conversation", bundle: .app).tag(PullRequestLanding.conversation)
                    Text("By list", bundle: .app).tag(PullRequestLanding.byList)
                } label: {
                    Text("Opening a pull request", bundle: .app)
                }
                .pickerStyle(.segmented)
                Text(landingCaption, bundle: .app).font(.caption2).foregroundStyle(.tertiary)
                Picker(selection: $store.settings.filePill) {
                    Text("Top", bundle: .app).tag(FilePillPosition.top)
                    Text("Bottom", bundle: .app).tag(FilePillPosition.bottom)
                } label: {
                    Text("File controls", bundle: .app)
                }
                .pickerStyle(.segmented)
                Text("Floating over the page on Files and compare pages: previous and next file, viewed and next.", bundle: .app)
                    .font(.caption2).foregroundStyle(.tertiary)
            } header: {
                Text("Review Desk", bundle: .app)
            }
            SwiftUI.Section {
                LabeledContent {
                    HStack(spacing: 10) {
                        Text(testsSummary).foregroundStyle(.secondary)
                        Button { choosingTests = true } label: { Text("Choose…", bundle: .app) }.controlSize(.small)
                    }
                } label: {
                    Text("Files counted as tests", bundle: .app)
                }
                Text("What the Tests button in the bar marks as viewed in one go: presets by stack, plus your own globs.", bundle: .app)
                    .font(.caption2).foregroundStyle(.tertiary)
            } header: {
                Text("Tests", bundle: .app)
            }
            SwiftUI.Section {
                Toggle(isOn: $store.settings.autoMark) { Text("Mark automatically when opening a pull request", bundle: .app) }
                Toggle(isOn: $store.settings.loadBeforeMark) { Text("Load the whole file list before marking", bundle: .app) }
                Toggle(isOn: $store.settings.verify) { Text("Verify on the server after marking", bundle: .app) }
                Toggle(isOn: $store.settings.rememberCompare) { Text("Remember viewed files on compare pages", bundle: .app) }
            } header: {
                Text("Behavior", bundle: .app)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
        .sheet(isPresented: $choosingTests) { TestPresetsSheet(store: store) }
    }

    private var landingCaption: LocalizedStringKey {
        switch store.settings.landing {
        case .files: "The diff, at the first file still to review. Same for a click, ↩, and the browser when the Desk is off."
        case .conversation: "The pull request page: comments, checks, merge. Same for a click, ↩, and the browser when the Desk is off."
        case .byList: "My PRs open on the conversation; To review opens on the first file still to review. Same for a click, ↩, and the browser when the Desk is off."
        }
    }

    private var testsSummary: String {
        let presets = ReviewPresets.all.filter { store.settings.presets[$0.id] ?? $0.enabled }.count
        let globs = store.settings.customGlobs.count
        return String(localized: "\(presets) presets on · \(globs) custom globs", bundle: .app)
    }
}

/// The presets by stack and the custom globs, out of the tab's way: most people set them once.
struct TestPresetsSheet: View {
    @Bindable var store: ReviewSettingsStore
    @Environment(\.dismiss) private var dismiss

    private var groups: [(name: String, presets: [ReviewPreset])] {
        var order: [String] = []
        var byGroup: [String: [ReviewPreset]] = [:]
        for p in ReviewPresets.all {
            if byGroup[p.group] == nil { order.append(p.group) }
            byGroup[p.group, default: []].append(p)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Files counted as tests", bundle: .app).font(.headline)
            Form {
                SwiftUI.Section {
                    ForEach(groups, id: \.name) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: group.name).font(.caption).foregroundStyle(.secondary)
                            ForEach(group.presets) { preset in
                                Toggle(isOn: Binding(
                                    get: { store.settings.presets[preset.id] ?? preset.enabled },
                                    set: { store.settings.presets[preset.id] = $0 }
                                )) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: preset.label)
                                        Text(verbatim: preset.description).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                    }
                }
                SwiftUI.Section {
                    TextEditor(text: $store.settings.customGlobsText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 72)
                } header: {
                    Text("Custom globs, one per line. Lines starting with # are ignored.", bundle: .app)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("Done", bundle: .app) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460, height: 520)
    }
}

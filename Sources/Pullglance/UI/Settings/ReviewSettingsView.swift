import SwiftUI

struct ReviewSettingsView: View {
    @Bindable private var store = ReviewSettingsStore.shared

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
            } header: {
                Text("Files counted as tests", bundle: .app)
            }
            SwiftUI.Section {
                TextEditor(text: $store.settings.customGlobsText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 80)
                Text("One glob per line. Lines starting with # are ignored.", bundle: .app).font(.caption2).foregroundStyle(.tertiary)
            } header: {
                Text("Custom globs", bundle: .app)
            }
            SwiftUI.Section {
                Toggle(isOn: $store.settings.autoMark) { Text("Mark automatically when opening a pull request", bundle: .app) }
                Toggle(isOn: $store.settings.loadBeforeMark) { Text("Load the whole file list before marking", bundle: .app) }
                Toggle(isOn: $store.settings.verify) { Text("Verify on the server after marking", bundle: .app) }
                Toggle(isOn: $store.settings.rememberCompare) { Text("Remember viewed files on compare pages", bundle: .app) }
                Button { ReviewStorage(defaults: .standard).clearPersistent() } label: { Text("Clear compare memory", bundle: .app) }
                    .controlSize(.small)
            } header: {
                Text("Behavior", bundle: .app)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 4)
    }
}

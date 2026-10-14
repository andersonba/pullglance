import SwiftUI

struct SectionHeader: View {
    let title: String
    /// nil hides the count (used for "Via team" before it has been fetched).
    let count: Int?
    var expanded: Binding<Bool>? = nil
    var detail: String? = nil
    /// A small action shown only while the pointer is over the header (e.g. "Sort by update").
    var hoverAction: HoverAction? = nil
    /// One quiet menu at the right edge: the current order as its title (Priority, Recent, Manual) with the
    /// ways to change it inside, reordering included. Replaces the hover action on sections that have it.
    var sortMenu: SortMenu? = nil

    struct SortMenu {
        let sort: ListSort
        /// Rows ordered by hand: the title says so and the menu offers the way back.
        let isManual: Bool
        let setSort: (ListSort) -> Void
        let reorder: () -> Void
        let clearManual: () -> Void
    }

    struct HoverAction {
        let title: String
        /// Shown all the time instead of only under the pointer (reorder mode).
        var alwaysVisible = false
        let perform: () -> Void
    }

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            if let expanded {
                Image(systemName: expanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            Text(verbatim: count.map { "\(title) · \($0)" } ?? title)
                .textCase(.uppercase)
            if let detail {
                Spacer()
                Text(verbatim: detail).fontWeight(.regular)
            }
            if let sortMenu {
                if detail == nil { Spacer() }
                Menu {
                    Picker(selection: Binding(get: { sortMenu.isManual ? nil : sortMenu.sort }, set: { if let s = $0 { sortMenu.setSort(s) } })) {
                        Text("Priority", bundle: .app).tag(ListSort?.some(.priority))
                        Text("Recent", bundle: .app).tag(ListSort?.some(.recent))
                    } label: { EmptyView() }
                    .pickerStyle(.inline)
                    Divider()
                    if sortMenu.isManual {
                        Button(action: sortMenu.clearManual) { Text(sortMenu.sort == .priority ? "Back to Priority" : "Back to Recent", bundle: .app) }
                    }
                    Button(action: sortMenu.reorder) { Text("Reorder rows…", bundle: .app) }
                } label: {
                    HStack(spacing: 3) {
                        Text(sortMenu.isManual ? "Manual" : sortMenu.sort == .priority ? "Priority" : "Recent", bundle: .app)
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .textCase(nil)
                    .foregroundStyle(.secondary)
                }
                // Button style with a plain button: the label keeps its own quiet styling (the borderless style
                // paints it in the control color).
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if let hoverAction {
                if detail == nil, sortMenu == nil { Spacer() }
                // Quiet on purpose: a secondary label, underlined only under the pointer.
                Button(action: hoverAction.perform) {
                    Text(verbatim: hoverAction.title)
                        .font(.system(size: 10.5, weight: .medium))
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hovering || hoverAction.alwaysVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.12), value: hovering)
                .accessibilityHidden(!(hovering || hoverAction.alwaysVisible))
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Color.primary.opacity(0.6))
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { expanded?.wrappedValue.toggle() }
    }
}

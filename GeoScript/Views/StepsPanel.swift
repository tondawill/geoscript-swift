import GeoEngine
import SwiftUI

/// The construction protocol. Like an expression list: every step is an input, an empty row waits at
/// the bottom, and a symbol keypad shows while typing.
struct StepsPanel: View {
    let store: DrawingStore
    @FocusState private var focus: String?
    @Environment(\.colorScheme) private var colorScheme

    private static let symbols = ["∈", "∩", "∧", "⊥", "∥", "∠", "△", "°", "↦", "↔", "|", ";", "="]

    var body: some View {
        let rows = store.orderedRows
        let exerciseCount = rows.filter { $0.step?.exercise == true }.count
        let active = rows.first(where: \.active)
        let suggestions = store.currentSuggestions

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.t("protocol.title")).font(.title3.bold())
                Button(store.t("exercise.lockAll"), systemImage: "lock") { store.lockAll() }
                    .disabled(!store.canLockAll)
                    .help(store.t("exercise.lockAllHelp"))
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if exerciseCount > 0, index == 0 {
                            sectionHeader("🔒 \(store.t("exercise.title"))")
                        }
                        if exerciseCount > 0, index == exerciseCount {
                            sectionHeader(store.t("protocol.construction"))
                        }
                        rowView(row, number: index - exerciseCount + 1)
                        // Inside the scrolling list: anything that grows below it would push the keypad off screen.
                        if row.active, let error = row.error {
                            Text(store.t(error.error.rawValue, ["name": error.name ?? ""]))
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.leading, 40)
                                .padding(.vertical, 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if row.active, let suggestions {
                            suggestionsView(suggestions)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(maxHeight: .infinity)
            if active != nil {
                Divider()
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 8)], spacing: 8) {
                    ForEach(Self.symbols, id: \.self) { symbol in
                        Button(symbol) {
                            store.insertSymbol(symbol)
                            focus = store.session?.key
                        }
                        .buttonStyle(.bordered)
                        .focusable(false)
                    }
                }
                .padding(14)
            }
        }
        .onChange(of: focus) { old, new in
            if let new { store.focusRow(new) } else if let old { store.blurRow(old) }
        }
        .onChange(of: store.requestedRow) { _, row in
            guard let row else { return }
            focus = row
            store.requestedRow = nil
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func rowView(_ row: StepRow, number: Int) -> some View {
        let isExercise = row.step?.exercise == true
        let selected = row.step != nil && row.step?.objectId == store.selection
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Group {
                if isExercise {
                    Image(systemName: "lock.fill").font(.caption)
                } else if row.step != nil || !row.text.isEmpty {
                    Text("\(number).").monospacedDigit()
                } else {
                    Text("")
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 26, alignment: .trailing)

            if let color = row.step.flatMap({ store.construction.styleOf($0.objectId).color }) {
                Circle().fill(geoColor(color, isDark: colorScheme == .dark)).frame(width: 9, height: 9)
            }

            if isExercise {
                Text(row.text)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(store.t("exercise.locked"))
            } else {
                TextField(row.step == nil ? store.t("typing.placeholder") : "", text: Binding(
                    get: { row.text },
                    set: { store.changeRow($0) }
                ))
                .textFieldStyle(.plain)
                .focused($focus, equals: row.id)
                .autocorrectionDisabled()
            }
            if row.error != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(selected || row.active ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .onHover { inside in
            store.hoveredSteps = inside ? (row.step.map { $0.highlight ?? [$0.objectId] } ?? []) : []
        }
    }

    private func suggestionsView(_ suggestions: Suggestions) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(suggestions.items.enumerated()), id: \.element) { index, name in
                Button(name) {
                    store.acceptSuggestion(name)
                    focus = store.session?.key
                }
                .buttonStyle(.bordered)
                .tint(index == store.suggestionPick ? .accentColor : nil)
                .focusable(false)
            }
        }
        .padding(.leading, 40)
        .padding(.vertical, 4)
    }
}

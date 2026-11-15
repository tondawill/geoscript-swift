import AppKit
import GeoEngine
import SwiftUI

/// The function rows, in the right panel like the construction steps: one function per row, typeset
/// when not being edited, an empty row waiting at the bottom, a keypad while typing.
struct GraphPanel: View {
    let store: DrawingStore
    @FocusState private var focus: String?
    @State private var selections: [String: TextSelection?] = [:]

    private var graph: GraphStore { store.graph }

    /// Keypad: label, text inserted, and where the caret goes in it (default: at the end).
    private static let keys: [(label: String, text: String, caret: Int?)] = [
        ("x²", "^2", nil), ("xⁿ", "^", nil), ("√", "√()", 2), ("π", "π", nil), ("|x|", "||", 1), ("(", "(", nil), (")", ")", nil),
        ("sin", "sin()", 4), ("cos", "cos()", 4), ("tan", "tan()", 4), ("ln", "ln()", 3),
        // A restriction at the end of a row: y = x^2 {0 ≤ x ≤ 3}.
        ("{ }", "{}", 1), ("≤", " ≤ ", nil), ("≥", " ≥ ", nil),
    ]

    var body: some View {
        let graph = graph
        let rows = graph.rows
        let shown = rows + [GraphRow(id: graph.newId, text: "", color: "")]
        VStack(alignment: .leading, spacing: 0) {
            Text(store.t("graph.title"))
                .lineLimit(1)
                .font(.title3.bold())
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                            Group {
                                if row.between != nil {
                                    CrossingRow(store: store, row: row, number: index + 1)
                                } else {
                                    VStack(alignment: .leading, spacing: 2) {
                                        if row.id == graph.newId, let kind = graph.placingKind { ghostRow(kind) }
                                        typedRow(row, index: index, shown: shown)
                                        // Inside the list, so a long message scrolls with it instead of resizing the window.
                                        if focus == row.id, let error = graph.compiledRow(row.id)?.error {
                                            Text(store.t(error.key, ["name": error.name ?? ""]))
                                                .font(.callout)
                                                .foregroundStyle(.red)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.leading, 66)
                                                .padding(.trailing, 6)
                                                .padding(.bottom, 4)
                                        }
                                    }
                                }
                            }
                            .id(row.id)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
                .onChange(of: graph.selected) { _, id in
                    // Only a graph picked on the canvas: a row being typed into is in view already.
                    if let id, id != focus { proxy.scrollTo(id) }
                }
            }
            if graph.focused != nil {
                Divider()
                keypad
            }
        }
        .onChange(of: focus) { _, id in
            if id != nil { graph.tool = .move }
            graph.focused = id
            if let id, id != graph.newId { graph.selected = id }
        }
        .onChange(of: graph.focused) { _, id in
            if focus != id { focus = id }
        }
    }

    private func typedRow(_ row: GraphRow, index: Int, shown: [GraphRow]) -> some View {
        let graph = graph
        let isNew = row.id == graph.newId
        let compiled = graph.compiledRow(row.id)
        let isFocused = focus == row.id
        let isSelected = graph.selected == row.id && !isFocused
        let pretty = !isFocused && compiled?.parsed != nil && compiled?.error == nil
        return HStack(alignment: .center, spacing: 8) {
            Text(isNew ? "" : "\(index + 1).")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 22, alignment: .trailing)
            if isNew {
                Color.clear.frame(width: 22, height: 22)
            } else {
                SwatchButton(store: store, row: row, region: { if case .region = compiled?.parsed?.kind { return true } else { return false } }())
            }
            ZStack(alignment: .leading) {
                TextField("", text: Binding(get: { row.text }, set: { graph.type($0, in: row.id) }),
                          selection: selectionBinding(row.id),
                          prompt: isNew ? Text(store.t("graph.placeholder")) : nil)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focus, equals: row.id)
                    .opacity(pretty ? 0.01 : 1)
                    .onSubmit { focusRow(index + 1, in: shown, step: 1) }
                    .onKeyPress(.downArrow) {
                        focusRow(index + 1, in: shown, step: 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        focusRow(index - 1, in: shown, step: -1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        focus = nil
                        return .handled
                    }
                    .onKeyPress(.delete) {
                        // Backspace in an empty row removes it.
                        guard row.text.isEmpty, !isNew else { return .ignored }
                        graph.remove(row.id)
                        focusRow(index - 1, in: shown, step: -1)
                        return .handled
                    }
                if pretty, let parsed = compiled?.parsed {
                    MathView(pieces: MathBuilder(comma: store.usesComma).pieces(parsed))
                        .opacity(row.hidden ? 0.45 : 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
            if let error = compiled?.error, !isFocused {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(store.t(error.key, ["name": error.name ?? ""]))
            }
            if !isNew {
                Button { graph.toggleHidden(row.id) } label: {
                    Image(systemName: row.hidden ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(store.t(row.hidden ? "graph.show" : "graph.hide"))
                Button { graph.remove(row.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                    .help(store.t("action.delete"))
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.accentColor.opacity(0.14) : isFocused ? Color.secondary.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }

    /// A function being placed: its live formula (or its template) as a faint row above the empty one.
    private func ghostRow(_ kind: FunctionKind) -> some View {
        let graph = graph
        let preview = graph.placingPreview
        let parsed = preview?.ghost == true ? preview?.text.flatMap { try? parseRow($0).get() } : nil
        return HStack(spacing: 8) {
            Color.clear.frame(width: 22)
            Circle().fill(geoColor(graph.nextColor, isDark: false).opacity(0.6)).frame(width: 14, height: 14).frame(width: 22)
            Group {
                if let parsed {
                    MathView(pieces: MathBuilder(comma: store.usesComma).pieces(parsed))
                } else {
                    Text(functionTemplate(kind, sideways: graph.sideways, czech: store.language == .cs)).font(.system(size: 14)).italic()
                }
            }
            .opacity(0.55)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
    }

    private func selectionBinding(_ id: String) -> Binding<TextSelection?> {
        Binding(get: { selections[id] ?? nil }, set: { selections[id] = $0 })
    }

    /// Focuses the row at `index`, or the nearest typed row (not a row of crossings) further on.
    private func focusRow(_ index: Int, in shown: [GraphRow], step: Int) {
        var k = max(0, min(shown.count - 1, index))
        while k >= 0 && k < shown.count {
            if shown[k].between == nil {
                focus = shown[k].id
                return
            }
            k += step
        }
    }

    private var keypad: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Self.keys, id: \.label) { key in
                Button { insert(key) } label: {
                    Text(key.label).frame(maxWidth: .infinity, minHeight: 22)
                }
                .buttonStyle(.bordered)
                .focusable(false)
            }
        }
        .padding(10)
    }

    /// Types a key at the caret; √ and |x| wrap the selection.
    private func insert(_ key: (label: String, text: String, caret: Int?)) {
        guard let id = focus else { return }
        let text = graph.row(id)?.text ?? ""
        var from = text.count, to = text.count
        if let sel = selections[id] ?? nil, case .selection(let range) = sel.indices {
            from = text.distance(from: text.startIndex, to: min(range.lowerBound, text.endIndex))
            to = text.distance(from: text.startIndex, to: min(range.upperBound, text.endIndex))
        }
        let chars = Array(text)
        let selected = String(chars[from..<to])
        var inner = key.text
        if let caret = key.caret, !selected.isEmpty {
            inner = String(key.text.prefix(caret)) + selected + String(key.text.dropFirst(caret))
        }
        let next = String(chars[..<from]) + inner + String(chars[to...])
        let caret = from + (key.caret != nil && selected.isEmpty ? key.caret! : inner.count)
        graph.type(next, in: id)
        // A new row at the bottom keeps the focus: it already has that id.
        selections[id] = TextSelection(insertionPoint: next.index(next.startIndex, offsetBy: caret))
    }
}

/// A row made by the Intersect tool: the two graphs, and where they cross in the view.
private struct CrossingRow: View {
    let store: DrawingStore
    let row: GraphRow
    let number: Int
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let graph = store.graph
        let between = row.between ?? []
        let names = ["a": String(graph.number(between.first ?? "")), "b": String(graph.number(between.last ?? ""))]
        let points = graph.viewport.map { graph.picture($0, graph.canvasSize).kept[row.id] ?? [] } ?? []
        let isSelected = graph.selected == row.id
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 22, alignment: .trailing)
            SwatchButton(store: store, row: row, region: false)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    ForEach(between, id: \.self) { id in
                        Circle().fill(geoColor(graph.row(id)?.color, isDark: colorScheme == .dark)).frame(width: 9, height: 9)
                    }
                    Text(store.t("graph.cross.rows", names)).foregroundStyle(.secondary)
                }
                if points.isEmpty {
                    Text(store.t("graph.cross.none")).foregroundStyle(.tertiary)
                } else {
                    ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                        Text(pointText(p, comma: store.usesComma)).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { graph.selected = row.id }
            Button { graph.remove(row.id) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help(store.t("action.delete"))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .opacity(row.hidden ? 0.5 : 1)
        .background(isSelected ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .help(store.t("graph.cross.row", names))
    }
}

/// A row's round swatch: a click opens the palette, any colour, the line's thickness and dashes,
/// how solid a shaded row's fill is, and Show / Hide.
private struct SwatchButton: View {
    let store: DrawingStore
    let row: GraphRow
    let region: Bool
    @State private var open = false
    @State private var hex = ""
    @Environment(\.colorScheme) private var colorScheme

    private var graph: GraphStore { store.graph }

    var body: some View {
        let color = geoColor(row.color, isDark: colorScheme == .dark)
        Button { open.toggle() } label: {
            ZStack {
                Circle().fill(row.hidden ? Color.clear : color)
                Circle().stroke(color, lineWidth: 2)
                if row.between != nil {
                    Text("∩").font(.system(size: 12, weight: .bold)).foregroundStyle(row.hidden ? color : .white)
                } else if region {
                    // A shaded row: the area under a wave filled in.
                    Image(systemName: "water.waves").font(.system(size: 9, weight: .bold)).foregroundStyle(row.hidden ? color : .white)
                }
            }
            .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .help(store.t("style.color"))
        .popover(isPresented: $open, arrowEdge: .leading) { menu }
    }

    private var menu: some View {
        let isDark = colorScheme == .dark
        let custom = row.color.hasPrefix("#") ? row.color : nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(colorPalette, id: \.self) { name in
                    Button {
                        graph.restyle(row.id) { $0.color = name }
                        open = false
                    } label: {
                        Circle()
                            .fill(geoColor(name, isDark: isDark))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: row.color == name ? 2.5 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(store.t("color.\(name)"))
                }
                ColorPicker(store.t("color.custom"), selection: customColor, supportsOpacity: false)
                    .labelsHidden()
                    .help(store.t("color.custom"))
            }
            HStack {
                Text(store.t("color.code"))
                TextField("#rrggbb", text: $hex)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .onChange(of: hex) { _, value in
                        let v = value.trimmingCharacters(in: .whitespaces)
                        let code = (v.hasPrefix("#") ? v : "#" + v).lowercased()
                        if code.wholeMatch(of: #/#[0-9a-f]{6}/#) != nil, code != row.color { graph.restyle(row.id) { $0.color = code } }
                    }
            }
            if row.between == nil {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(store.t("graph.style.width"))
                        Spacer()
                        Text("\(formatDimension(row.width ?? graphDefaultWidth, comma: store.usesComma)) px").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { row.width ?? graphDefaultWidth },
                                          set: { v in graph.restyle(row.id, live: true) { $0.width = v } }),
                           in: 0...graphMaxWidth, step: 0.5) { editing in if !editing { graph.endStyleEdit() } }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.t("graph.style.line"))
                    Picker(store.t("graph.style.line"), selection: Binding(get: { row.dash?.rawValue ?? "solid" },
                                                                         set: { v in graph.restyle(row.id) { $0.dash = Dash(rawValue: v) } })) {
                        Text(store.t("graph.style.solid")).tag("solid")
                        Text(store.t("graph.style.dashed")).tag("dashed")
                        Text(store.t("graph.style.dotted")).tag("dotted")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                if region {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(store.t("graph.style.fill"))
                            Spacer()
                            Text("\(Int(((row.fill ?? graphDefaultFill) * 100).rounded())) %").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { (row.fill ?? graphDefaultFill) * 100 },
                                              set: { v in graph.restyle(row.id, live: true) { $0.fill = v / 100 } }),
                               in: 0...100, step: 5) { editing in if !editing { graph.endStyleEdit() } }
                    }
                }
            }
            Toggle(store.t("graph.hide"), isOn: Binding(get: { row.hidden }, set: { _ in graph.toggleHidden(row.id) }))
        }
        .padding(14)
        .frame(width: 290)
        .onAppear { hex = custom ?? "" }
        .onDisappear { graph.endStyleEdit() }
    }

    private var customColor: Binding<Color> {
        Binding(get: { geoColor(row.color.hasPrefix("#") ? row.color : "#2e8b57", isDark: false) },
                set: { color in
                    guard let code = hexCode(color) else { return }
                    graph.restyle(row.id, live: true) { $0.color = code }
                })
    }
}

/// "#rrggbb" of a colour.
func hexCode(_ color: Color) -> String? {
    guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    return String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
}

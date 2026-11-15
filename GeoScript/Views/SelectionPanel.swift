import GeoEngine
import SwiftUI

/// What can be done with the selected object.
struct SelectionPanel: View {
    let store: DrawingStore
    let object: GeoObject
    @Environment(\.colorScheme) private var colorScheme

    private var construction: Construction { store.construction }

    private var title: String {
        let name = construction.displayName(object)
        switch object {
        case .segment: return store.t("info.segment", ["name": name])
        case .line: return store.t("info.line", ["name": name])
        case .ray: return store.t("info.ray", ["name": name])
        case .circle: return store.t("info.circle", ["name": name])
        default: return store.t("info.point", ["name": name])
        }
    }

    private var relation: Relation? { construction.relationOf(object) }

    private var dimensionValue: Double? {
        let resolved = construction.resolve()
        switch object {
        case .segment: return construction.segmentLength(object, resolved)
        case .circle: return construction.circleRadius(object, resolved)
        default: return nil
        }
    }

    private var dimensionLabel: String {
        switch object {
        case .segment(let s): "|\(construction.object(s.a)?.name ?? "?")\(construction.object(s.b)?.name ?? "?")|"
        default: "r"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.bold())
            if let value = dimensionValue {
                DimensionRow(store: store, label: dimensionLabel, unit: "cm", value: value, locked: construction.isLocked(object),
                             disabledReason: construction.dimensionError(object).map(store.message(for:)),
                             submit: { parsed in store.applyDimension(object.id, parsed) },
                             unlock: { store.unlockDimension(object.id) })
                    .id(object.id)
            }
            if let relation { relationRow(relation) }
            colourRow
            HStack {
                Text(store.t("style.opacity"))
                Slider(value: opacityBinding, in: ObjectStyle.minOpacity...1, step: 0.05) { editing in
                    if editing { store.beginStyleEdit() } else { store.endStyleEdit() }
                }
                Text("\(Int((construction.styleOf(object.id).opacity * 100).rounded())) %")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if !object.isPoint {
                Toggle(store.t("style.dashed"), isOn: Binding(
                    get: { construction.styleOf(object.id).dashed },
                    set: { value in store.updateStyle { $0.dashed = value } }
                ))
            }
            Toggle(store.t("exercise.toggle"), isOn: Binding(
                get: { construction.isExercise(object.id) },
                set: { _ in store.toggleExercise() }
            ))
            .help(store.t("exercise.toggleHelp"))
            HStack {
                Button(store.t("action.rename")) { store.beginRename() }
                Spacer()
                Button(store.t("action.delete"), role: .destructive) { store.deleteSelection() }
            }
        }
    }

    private var opacityBinding: Binding<Double> {
        Binding(get: { construction.styleOf(object.id).opacity },
                set: { value in store.updateStyle { $0.opacity = value } })
    }

    @ViewBuilder
    private func relationRow(_ rel: Relation) -> some View {
        let name = construction.displayName(object)
        let ref = construction.object(rel.p).map(construction.displayName) ?? "?"
        switch rel.kind {
        case .angle:
            VStack(alignment: .leading, spacing: 4) {
                Text("\(name) ∠ \(ref)").foregroundStyle(.secondary)
                DimensionRow(store: store, label: "α", unit: "°", value: rel.angle * 180 / .pi, locked: true, disabledReason: nil,
                             submit: { store.applyAngle(object.id, $0) },
                             unlock: { store.removeRelation(object.id) })
                    .id(object.id + "angle")
            }
        case .perpendicular, .parallel:
            HStack {
                Text(store.t(rel.kind == .perpendicular ? "relation.perpendicular" : "relation.parallel", ["name": name, "ref": ref]))
                Spacer()
                Button(store.t("action.removeRelation")) { store.removeRelation(object.id) }
            }
        }
    }

    private var colourRow: some View {
        let current = construction.styleOf(object.id).color
        let isDark = colorScheme == .dark
        return VStack(alignment: .leading, spacing: 8) {
            Text(store.t("style.color"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 30), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach([nil] + colorPalette.map(Optional.some), id: \.self) { (name: String?) in
                    Button {
                        store.updateStyle { $0.color = name }
                    } label: {
                        Circle()
                            .fill(geoColor(name, isDark: isDark))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: current == name ? 2.5 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                    .help(name.map { store.t("color.\($0)") } ?? store.t("color.default"))
                }
                ColorPicker(store.t("color.custom"), selection: customColor, supportsOpacity: false).labelsHidden()
            }
        }
    }

    private var customColor: Binding<Color> {
        Binding(get: { geoColor(construction.styleOf(object.id).color ?? "#2e8b57", isDark: false) },
                set: { color in
                    guard let hex = hexString(color) else { return }
                    store.updateStyle { $0.color = hex }
                })
    }

    private func hexString(_ color: Color) -> String? {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}

/// |AB| = [6,00] cm with a lock.
private struct DimensionRow: View {
    let store: DrawingStore
    let label: String
    let unit: String
    let value: Double
    let locked: Bool
    let disabledReason: String?
    let submit: (Double) -> String?
    let unlock: () -> Void

    @State private var text = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private var shown: String { formatNumber(value, comma: store.usesComma) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                Spacer()
                TextField(label, text: $text)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 84)
                    .focused($focused)
                    .disabled(disabledReason != nil)
                    .onSubmit(apply)
                Text(unit).foregroundStyle(.secondary)
                if locked {
                    Button(store.t("dimension.locked"), systemImage: "lock.fill", action: unlock)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help(store.t("dimension.locked"))
                }
            }
            if let message = error ?? disabledReason {
                Text(message).font(.caption).foregroundStyle(error == nil ? Color.secondary : Color.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { text = shown }
        .onChange(of: shown) { _, new in if !focused { text = new } }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { apply() }
        }
    }

    private func apply() {
        guard text != shown else { return }
        guard let parsed = parseNumber(text) else {
            error = store.t("error.number")
            return
        }
        error = submit(parsed)
        if error == nil { text = shown }
    }
}

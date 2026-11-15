import SwiftUI

/// Everything that floats above the canvas: the live dimension and the name / dimension box.
struct FloatingInputLayer: View {
    let store: DrawingStore
    let live: LiveDimension?

    var body: some View {
        ZStack {
            if let live, let hover = store.hover {
                LiveDimensionBox(dimension: live)
                    .position(x: hover.x + 70, y: hover.y + 30)
                    .allowsHitTesting(false)
            }
            if let prompt = store.prompt, let anchor = store.promptAnchor {
                PromptBox(store: store)
                    .id(prompt)
                    .position(x: anchor.x + 125, y: anchor.y - 52)
            }
        }
    }
}

/// |AB| = 6.00 cm. It never takes focus: the typed text is collected by the store.
private struct LiveDimensionBox: View {
    let dimension: LiveDimension

    var body: some View {
        HStack(spacing: 4) {
            Text("\(dimension.label) =")
            Text(dimension.value)
                .bold(dimension.typing)
                .foregroundStyle(dimension.invalid ? Color.red : Color.primary)
                .monospacedDigit()
            Text(dimension.unit).foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct PromptBox: View {
    @Bindable var store: DrawingStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(store.promptLabel).font(.callout)
                TextField(store.promptLabel, text: $store.promptText)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .onSubmit { store.submitPrompt() }
                    .onExitCommand { store.closePrompt() }
                if let suffix = store.promptSuffix {
                    Text(suffix).font(.callout).foregroundStyle(.secondary)
                }
            }
            Text(store.promptError ?? store.t("name.help"))
                .font(.caption)
                .foregroundStyle(store.promptError == nil ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 230, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .shadow(radius: 3, y: 1)
        .onAppear { focused = true }
    }
}

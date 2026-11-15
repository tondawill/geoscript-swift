import Foundation
import GeoEngine

/// One row of the steps panel: a step, or the row being typed in.
struct StepRow: Identifiable {
    let id: String
    let text: String
    let step: ProtocolStep?
    let active: Bool
    let error: TypingFailure?
}

/// A row being typed in. Every keystroke is applied afresh to `base`, and the whole edit is one undo step.
struct StepSession {
    enum Target {
        case edit(ProtocolStep)
        case new(after: Id?)
    }

    var key: String
    var base: Construction
    var baseSteps: [ProtocolStep]
    var target: Target
    var text: String
    var error: TypingFailure?
    var dirty = false
}

extension DrawingStore {
    static let endRow = "new"

    private func isNewId(_ id: Id, _ base: Construction) -> Bool {
        (Int(id.dropFirst()) ?? 0) >= base.nextId
    }

    private func start(_ key: String, _ target: StepSession.Target, _ text: String) {
        session = StepSession(key: key, base: construction, baseSteps: protocolSteps, target: target, text: text)
    }

    func focusRow(_ key: String) {
        guard key != session?.key else { return }
        suggestionsOff = true
        suggestionPick = -1
        if key == Self.endRow {
            selection = nil
            start(key, .new(after: nil), "")
            return
        }
        guard let step = protocolSteps.first(where: { $0.objectId == key }), !step.exercise else { return }
        start(key, .edit(step), step.text)
        selection = step.objectId
    }

    func blurRow(_ key: String) {
        if session?.key == key { session = nil }
    }

    /// A change in the active row, after autocorrect.
    func changeRow(_ rawText: String) {
        guard session != nil else { return }
        let fixed = autocorrect(rawText, caret: (rawText as NSString).length)
        suggestionPick = -1
        suggestionsOff = false
        applyRow(fixed.text)
    }

    private func applyRow(_ text: String) {
        guard var s = session else { return }
        // Until the row changes something, it works on the drawing as it is now.
        let base = s.dirty ? s.base : construction
        let result: Result<TypingResult, TypingFailure>
        switch s.target {
        case .edit(let step):
            result = text == step.text ? .success(TypingResult(construction: base, select: step.objectId)) : base.editStep(step, text, typingContext)
        case .new(let after):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = .success(TypingResult(construction: base, select: nil))
            } else {
                var index: Int?
                if let after, let afterStep = s.baseSteps.first(where: { $0.objectId == after }) {
                    let positions = afterStep.objects.compactMap { id in base.objects.firstIndex { $0.id == id } }
                    index = (positions.max() ?? -1) + 1
                }
                result = base.insertStep(text, typingContext, index: index)
            }
        }
        s.text = text
        s.base = base
        switch result {
        case .success(let value):
            if s.dirty {
                replaceConstruction(value.construction)
            } else if value.construction != construction {
                commit {
                    $0 = value.construction
                    return true
                }
                s.dirty = true
            }
            s.error = nil
        case .failure(let failure):
            // Half-typed text: show the drawing as it was before this row.
            if s.dirty { replaceConstruction(base) }
            s.error = failure
        }
        session = s
    }

    /// Esc: back to how it was before the row was focused.
    func cancelRow() {
        if session?.dirty == true { undo() }
        session = nil
        requestedRow = nil
    }

    /// Enter: a new empty row below the one just typed.
    func enterRow() {
        guard let s = session, s.error == nil else { return }
        let steps = protocolSteps
        let made = steps.last { $0.objects.contains { isNewId($0, s.base) } }
        var after: Id?
        if let made {
            after = made.objectId
        } else {
            switch s.target {
            case .edit(let step): after = steps.first { $0.objectId == step.objectId }?.objectId
            case .new(let target): after = target
            }
        }
        // Below the last step is simply the empty row at the end.
        if after == steps.last?.objectId { after = nil }
        selection = nil
        let key = after.map { "new:\($0)" } ?? Self.endRow
        start(key, .new(after: after), "")
        requestedRow = key
    }

    var stepRows: [StepRow] {
        let steps = protocolSteps
        func row(_ s: ProtocolStep) -> StepRow { StepRow(id: s.objectId, text: s.text, step: s, active: false, error: nil) }
        let empty = StepRow(id: Self.endRow, text: "", step: nil, active: false, error: nil)
        guard let s = session else { return steps.map(row) + [empty] }

        var own = Set<Id>()
        var editing: ProtocolStep?
        var anchor: Id?
        switch s.target {
        case .edit(let step):
            own = Set(step.objects)
            editing = step
            anchor = step.objectId
        case .new(let after):
            anchor = after
        }
        // Steps made or replaced by the row are shown by the row itself.
        let visible = steps.filter { step in !step.objects.contains { own.contains($0) || isNewId($0, s.base) } }
        func baseIndex(_ id: Id?) -> Int {
            guard let id else { return .max }
            return s.baseSteps.firstIndex { $0.objectId == id } ?? -1
        }
        let at = baseIndex(anchor)
        var rows = visible.map(row)
        let pos = visible.firstIndex { step in
            let i = baseIndex(step.objectId)
            return i < 0 || i > at
        } ?? visible.count
        rows.insert(StepRow(id: s.key, text: s.text, step: editing, active: true, error: s.error), at: pos)
        if s.key != Self.endRow { rows.append(empty) }
        return rows
    }

    var stepNames: [String] {
        construction.objects.compactMap { o in
            guard let name = o.name, !name.isEmpty, !o.isHidden else { return nil }
            return name
        }
    }

    var currentSuggestions: Suggestions? {
        guard let s = session, !suggestionsOff else { return nil }
        return suggest(s.text, caret: (s.text as NSString).length, names: stepNames)
    }

    func acceptSuggestion(_ name: String) {
        guard let s = session, let suggestions = currentSuggestions else { return }
        let text = (s.text as NSString).replacingCharacters(in: NSRange(location: suggestions.from, length: suggestions.to - suggestions.from), with: name)
        suggestionPick = -1
        suggestionsOff = true
        applyRow(text)
    }

    func insertSymbol(_ symbol: String) {
        guard let s = session else { return }
        var spaced = symbol
        if "∈∩∧⊥∥=".contains(symbol) {
            spaced = (s.text.hasSuffix(" ") || s.text.isEmpty ? "" : " ") + symbol + " "
        } else if symbol == ";" {
            spaced = "; "
        }
        changeRow(s.text + spaced)
    }

    /// Keys while a row is being typed in: suggestions, moving between rows, Esc.
    func stepKeyPressed(code: UInt16) -> Bool {
        let list = currentSuggestions?.items ?? []
        switch code {
        case Key.down, Key.up:
            let step = code == Key.down ? 1 : -1
            if !list.isEmpty {
                suggestionPick = suggestionPick < 0 ? (step > 0 ? 0 : list.count - 1) : (suggestionPick + step + list.count) % list.count
                return true
            }
            let rows = orderedRows
            guard let i = rows.firstIndex(where: \.active), rows.indices.contains(i + step) else { return true }
            requestedRow = rows[i + step].id
            return true
        case Key.tab:
            guard !list.isEmpty else { return false }
            acceptSuggestion(list[max(0, suggestionPick)])
            return true
        case Key.enter, Key.keypadEnter:
            if suggestionPick >= 0, suggestionPick < list.count {
                acceptSuggestion(list[suggestionPick])
            } else {
                enterRow()
            }
            return true
        case Key.escape:
            if !list.isEmpty {
                suggestionsOff = true
            } else {
                cancelRow()
            }
            return true
        default:
            return false
        }
    }

    /// The exercise is listed first.
    var orderedRows: [StepRow] {
        let rows = stepRows
        return rows.filter { $0.step?.exercise == true } + rows.filter { $0.step?.exercise != true }
    }
}

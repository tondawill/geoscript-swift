import CoreGraphics
import Foundation
import GeoEngine
import Observation

enum Language: String, CaseIterable, Identifiable {
    case cs, en
    var id: String { rawValue }
    var label: String { rawValue.uppercased() }
}

/// One drawing: its construction and history, and how the pointer and keyboard act on it.
@MainActor @Observable
final class DrawingStore {
    static let snapPixels = 10.0
    static let dragThreshold = 3.0
    static let doubleClickSeconds = 0.4
    private static let languageKey = "geoscript.language"

    enum Key {
        static let tab: UInt16 = 48
        static let escape: UInt16 = 53
        static let backspace: UInt16 = 51
        static let forwardDelete: UInt16 = 117
        static let enter: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let up: UInt16 = 126
        static let down: UInt16 = 125
    }

    enum Drag {
        case point(Id)
        case circle(Id)
        case segment(Id, last: Vec)
        case pan(last: CGPoint)
        case click
        case ignored
    }

    var construction = Construction()
    var sketch: [SketchStroke] = []
    /// Graphs mode: the function rows, with their own undo history.
    let graph = GraphStore()
    var mode: AppMode = .geometry {
        didSet { if mode != oldValue { cancel() } }
    }
    var viewport: Viewport?
    var canvasSize: CGSize = .zero
    var tool: Tool = .move {
        didSet { cancel() }
    }
    var hover: CGPoint?
    var showGrid = false
    var clean = false
    var cleanPoints = false
    var showSketch = false
    var selection: Id?
    /// Objects of the step under the pointer in the steps panel.
    var hoveredSteps: [Id] = []
    var language: Language = .cs {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
            graph.usesComma = language == .cs
        }
    }
    /// Shown instead of the tool hint after something could not be done.
    var message: String?
    /// Goes up whenever the file contents change.
    private(set) var revision = 0

    var prompt: Prompt?
    var promptText = "" {
        didSet { promptError = nil }
    }
    var promptError: String?

    var lineStart: Snap?
    var circleCenter: Id?
    var relFirst: Id?
    var relSecond: Id?
    /// Angle tool: the angle (of the four at the crossing) frozen when typing starts.
    var angleLock: AngleSector?
    var typed: String?
    private(set) var history = History<Construction>()

    var session: StepSession?
    /// Row of the steps panel that should take the focus.
    var requestedRow: String?
    var suggestionPick = -1
    var suggestionsOff = false

    @ObservationIgnored var drag: Drag?
    /// The drawing when the current drag began, so a whole drag is one undo step.
    @ObservationIgnored var dragStart: Construction?
    @ObservationIgnored var pressLocation: CGPoint = .zero
    @ObservationIgnored var dragMoved = false
    @ObservationIgnored var lastClick: (time: Date, location: CGPoint)?
    @ObservationIgnored private var styleEditStart: Construction?
    @ObservationIgnored private var messageTask: Task<Void, Never>?

    init() {
        graph.onChange = { [weak self] in self?.changed() }
        if let saved = UserDefaults.standard.string(forKey: Self.languageKey), let value = Language(rawValue: saved) {
            language = value
        }
        graph.usesComma = language == .cs
    }

    // MARK: Text

    func t(_ key: String, _ values: [String: String] = [:]) -> String {
        var text = (language == .cs ? Messages.cs[key] : nil) ?? Messages.en[key] ?? key
        for (name, value) in values { text = text.replacingOccurrences(of: "{\(name)}", with: value) }
        return text
    }

    var usesComma: Bool { language == .cs }

    func dim(_ n: Double) -> String { formatDimension(n, comma: usesComma) }

    func flash(_ key: String, _ values: [String: String] = [:]) {
        message = t(key, values)
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self?.message = nil }
        }
    }

    var format: ProtocolFormat {
        let comma = usesComma
        return ProtocolFormat(dim: { formatDimension($0, comma: comma) }, deg: { formatDimension($0, comma: comma) })
    }

    var protocolSteps: [ProtocolStep] { construction.buildProtocol(format) }

    // MARK: Coordinates

    var tolerance: Double {
        Self.snapPixels / (viewport?.scale ?? Viewport.pxPerCm)
    }

    func world(_ p: CGPoint) -> Vec? {
        viewport?.toWorld(Vec(x: p.x, y: p.y))
    }

    func screen(_ p: Vec) -> CGPoint? {
        viewport.map { v in
            let s = v.toScreen(p)
            return CGPoint(x: s.x, y: s.y)
        }
    }

    func snap(at p: CGPoint) -> Snap? {
        world(p).map { construction.findSnap(construction.resolve(), at: $0, tolerance: tolerance) }
    }

    func sizeChanged(_ size: CGSize) {
        canvasSize = size
        if viewport == nil, size.width > 0 {
            viewport = Viewport(width: size.width, height: size.height)
        }
    }

    func pan(dx: Double, dy: Double) {
        viewport?.pan(dx: dx, dy: dy)
    }

    func zoom(at p: CGPoint, factor: Double) {
        viewport?.zoom(at: Vec(x: p.x, y: p.y), factor: factor)
    }

    /// Where typed steps put new points: around the centre of the visible area.
    var typingContext: TypingContext {
        TypingContext(center: world(CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)) ?? Vec(x: 0, y: 0))
    }

    // MARK: History

    func cancel() {
        lineStart = nil
        circleCenter = nil
        relFirst = nil
        relSecond = nil
        angleLock = nil
        typed = nil
        message = nil
        prompt = nil
    }

    /// Undo and redo of the mode in view: the drawing and the graphs each have their own history.
    var canUndo: Bool { mode == .graph ? graph.history.canUndo : history.canUndo }
    var canRedo: Bool { mode == .graph ? graph.history.canRedo : history.canRedo }

    func undo() {
        if mode == .graph { return graph.undo() }
        cancel()
        session = nil
        if let previous = history.undo(from: construction) {
            construction = previous
            changed()
        }
        dropStaleSelection()
    }

    func redo() {
        if mode == .graph { return graph.redo() }
        cancel()
        session = nil
        if let next = history.redo(from: construction) {
            construction = next
            changed()
        }
        dropStaleSelection()
    }

    private func dropStaleSelection() {
        if let selection, construction.object(selection) == nil { self.selection = nil }
    }

    func changed() {
        revision += 1
    }

    /// Records an undo step for a change already made (the end of a drag).
    func recordUndo(from before: Construction) {
        history.record(before)
        changed()
    }

    /// Replaces the drawing without an undo step (live typing in the steps panel).
    func replaceConstruction(_ next: Construction) {
        construction = next
        changed()
    }

    /// Applies a change as one undo step. A change that alters the exercise is refused unless `thaw`.
    @discardableResult
    func commit(thaw: Bool = false, _ change: (inout Construction) -> Bool) -> Bool {
        var next = construction
        guard change(&next) else { return false }
        if !thaw, construction.touchesExercise(after: next) {
            flash("exercise.locked")
            return false
        }
        if next != construction {
            history.record(construction)
            construction = next
            changed()
        }
        return true
    }

    /// The exercise can't be changed: says so instead (true when `id` is part of it).
    func refuseExercise(_ id: Id?) -> Bool {
        guard let id, construction.isExercise(id) else { return false }
        flash("exercise.locked")
        return true
    }

    /// Clears the drawing in one undoable step.
    func deleteAll() {
        cancel()
        session = nil
        selection = nil
        commit(thaw: true) { c in
            c.objects = []
            c.exercise = []
            return true
        }
    }

    func deleteSelection() {
        guard let selection, !refuseExercise(selection) else { return }
        self.selection = nil
        commit {
            $0.removeKeepingPoints([selection])
            return true
        }
    }

    // MARK: Style

    func beginStyleEdit() {
        if styleEditStart == nil { styleEditStart = construction }
    }

    func endStyleEdit() {
        if let start = styleEditStart, start != construction { recordUndo(from: start) }
        styleEditStart = nil
    }

    /// Changes the selected object's style. During a slider drag the undo step is made at its end.
    func updateStyle(_ change: (inout ObjectStyle) -> Void) {
        guard let selection, !refuseExercise(selection) else { return }
        var style = construction.styleOf(selection)
        change(&style)
        if styleEditStart != nil {
            construction.setStyle(selection, style)
        } else {
            commit {
                $0.setStyle(selection, style)
                return true
            }
        }
    }

    // MARK: Exercise

    /// Turns the selected object's step (all its objects) into the exercise, or back.
    func toggleExercise() {
        guard let selection else { return }
        let ids = protocolSteps.first { $0.objects.contains(selection) }?.objects ?? [selection]
        let on = !construction.isExercise(selection)
        commit(thaw: !on) {
            $0.setExercise(ids, on: on)
            return true
        }
    }

    func lockAll() {
        cancel()
        let ids = construction.objects.map(\.id)
        commit {
            $0.setExercise(ids, on: true)
            return true
        }
    }

    var canLockAll: Bool {
        construction.objects.contains { !construction.isExercise($0.id) }
    }

    // MARK: Sketch

    func addSketchStroke(_ stroke: SketchStroke) {
        sketch.append(stroke)
        changed()
    }

    func clearSketch() {
        sketch = []
        changed()
    }

    // MARK: Keyboard

    /// Returns true when the key was used.
    func keyPressed(code: UInt16, characters: String, editingText: Bool) -> Bool {
        if prompt != nil { return false } // the box handles its own keys
        if session != nil { return stepKeyPressed(code: code) }
        if editingText { return false }

        if progress.live != nil {
            switch code {
            case Key.backspace:
                if let t = typed { typed = t.count > 1 ? String(t.dropLast()) : nil }
                if typed == nil { angleLock = nil }
            case Key.enter, Key.keypadEnter:
                commitTyped()
            case Key.escape:
                if typed != nil { typed = nil; angleLock = nil } else { cancel() }
            default:
                guard characters.count == 1, let c = characters.first, c.isASCII, c.isNumber || c == "." || c == "," else { return false }
                if typed == nil, tool == .angle { angleLock = hoveredAngle }
                typed = (typed ?? "") + characters
            }
            return true
        }

        switch code {
        case Key.escape:
            cancel()
            return false
        case Key.backspace, Key.forwardDelete:
            guard selection != nil else { return false }
            deleteSelection()
            return true
        default:
            if characters.lowercased() == "h" {
                clean.toggle()
                return true
            }
            return false
        }
    }

    // MARK: Files

    func fileText() -> String {
        exportFile(FileContents(construction: construction, sketch: sketch, graphs: graph.rows), steps: protocolSteps,
                   stepsTitle: t("protocol.title"), exerciseTitle: t("exercise.title"), graphsTitle: t("graph.title"))
    }

    func load(_ contents: FileContents) {
        construction = contents.construction
        sketch = contents.sketch
        graph.load(contents.graphs)
        // A file with only functions opens in Graphs mode.
        if contents.construction.objects.isEmpty && !contents.graphs.isEmpty { mode = .graph }
    }
}

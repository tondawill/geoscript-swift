import Foundation

/// .geoscript files: plain text with the construction protocol (readable by anyone) and, below it, the
/// exact drawing as JSON. Opening a file uses the JSON; a file with only protocol steps is typed in step by step.

public let fileExtension = "geoscript"
private let magic = "GeoScript 1"
private let dataMark = "--- data ---"
public let colorPalette = ["red", "blue", "green", "orange", "purple", "pink", "gray"]

/// One stroke of the freehand sketch: points of the sketch area, flattened as x, y, x, y …
/// An eraser stroke wipes what was drawn before it. The sketch is not geometry.
public struct SketchStroke: Equatable, Sendable {
    public var tool: String
    /// "ink" or a palette name; ignored for the eraser.
    public var color: String
    public var pts: [Double]

    public init(tool: String, color: String, pts: [Double]) {
        self.tool = tool
        self.color = color
        self.pts = pts
    }
}

public func isColor(_ value: Any?) -> Bool {
    guard let s = value as? String else { return false }
    return colorPalette.contains(s) || s.wholeMatch(of: /#[0-9a-fA-F]{6}/) != nil
}

/// Everything a file holds: the drawing of Geometry mode and the function rows of Graphs mode.
public struct FileContents: Equatable, Sendable {
    public var construction: Construction
    public var sketch: [SketchStroke]
    public var graphs: [GraphRow]

    public init(construction: Construction, sketch: [SketchStroke] = [], graphs: [GraphRow] = []) {
        self.construction = construction
        self.sketch = sketch
        self.graphs = graphs
    }
}

public enum FileError: Error, Equatable, Sendable {
    case invalid
    case badStep(line: Int)
}

private func json(_ o: GeoObject) -> [String: Any] {
    func point(_ kind: String, _ id: Id, _ name: String, _ hidden: Bool) -> [String: Any] {
        var d: [String: Any] = ["kind": kind, "id": id, "name": name]
        if hidden { d["hidden"] = true }
        return d
    }
    switch o {
    case .freePoint(let p):
        var d = point("freePoint", p.id, p.name, p.hidden)
        if p.ownStep { d["ownStep"] = true }
        d["x"] = p.x
        d["y"] = p.y
        return d
    case .distancePoint(let p):
        var d = point("distancePoint", p.id, p.name, p.hidden)
        d["parent"] = p.parent
        d["distance"] = p.distance
        d["angle"] = p.angle
        if let toward = p.toward { d["toward"] = toward }
        return d
    case .intersectionPoint(let p):
        var d = point("intersectionPoint", p.id, p.name, p.hidden)
        d["a"] = p.a
        d["b"] = p.b
        d["index"] = p.index
        return d
    case .pointOn(let p):
        var d = point("pointOn", p.id, p.name, p.hidden)
        d["on"] = p.on
        d["t"] = p.t
        return d
    case .directionPoint(let p):
        var d = point("directionPoint", p.id, p.name, p.hidden)
        d["parent"] = p.parent
        d["ref"] = p.ref
        d["offset"] = p.offset
        d["distance"] = p.distance
        d["lengthLocked"] = p.lengthLocked
        if let c = p.onCurve { d["onCurve"] = ["id": c.id, "index": c.index] as [String: Any] }
        return d
    case .segment(let s):
        return ["kind": "segment", "id": s.id, "name": s.name ?? NSNull(), "a": s.a, "b": s.b]
    case .line(let l):
        return ["kind": "line", "id": l.id, "name": l.name, "a": l.a, "b": l.b]
    case .ray(let l):
        return ["kind": "ray", "id": l.id, "name": l.name, "a": l.a, "b": l.b]
    case .circle(let k):
        var d: [String: Any] = ["kind": "circle", "id": k.id, "name": k.name, "center": k.center,
                                "through": k.through ?? NSNull(), "radius": k.radius, "locked": k.locked]
        if let span = k.span { d["span"] = span }
        return d
    }
}

private func number(_ v: Any?) -> Double? {
    guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
    let d = n.doubleValue
    return d.isFinite ? d : nil
}

private func boolean(_ v: Any?) -> Bool? {
    guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
    return n.boolValue
}

/// Parses one object; nil when a field is missing or of the wrong type.
private func object(from d: [String: Any]) -> GeoObject? {
    guard let id = d["id"] as? String else { return nil }
    if d["hidden"] != nil, boolean(d["hidden"]) == nil { return nil }
    let hidden = boolean(d["hidden"]) ?? false
    let name = d["name"] as? String
    switch d["kind"] as? String {
    case "freePoint":
        guard let name, let x = number(d["x"]), let y = number(d["y"]) else { return nil }
        return .freePoint(FreePoint(id: id, name: name, hidden: hidden, ownStep: boolean(d["ownStep"]) ?? false, x: x, y: y))
    case "distancePoint":
        guard let name, let parent = d["parent"] as? String, let distance = number(d["distance"]), let angle = number(d["angle"]) else { return nil }
        return .distancePoint(DistancePoint(id: id, name: name, hidden: hidden, parent: parent, distance: distance, angle: angle,
                                            toward: d["toward"] as? String))
    case "intersectionPoint":
        guard let name, let a = d["a"] as? String, let b = d["b"] as? String, let index = number(d["index"]) else { return nil }
        return .intersectionPoint(IntersectionPoint(id: id, name: name, hidden: hidden, a: a, b: b, index: Int(index)))
    case "pointOn":
        guard let name, let on = d["on"] as? String, let t = number(d["t"]) else { return nil }
        return .pointOn(PointOnObject(id: id, name: name, hidden: hidden, on: on, t: t))
    case "directionPoint":
        guard let name, let parent = d["parent"] as? String, let ref = d["ref"] as? String, let offset = number(d["offset"]),
              let distance = number(d["distance"]), let lengthLocked = boolean(d["lengthLocked"]) else { return nil }
        var onCurve: OnCurve?
        if let raw = d["onCurve"], !(raw is NSNull) {
            guard let c = raw as? [String: Any], let cid = c["id"] as? String, let index = number(c["index"]) else { return nil }
            onCurve = OnCurve(id: cid, index: Int(index))
        }
        return .directionPoint(DirectionPoint(id: id, name: name, hidden: hidden, parent: parent, ref: ref, offset: offset,
                                              distance: distance, lengthLocked: lengthLocked, onCurve: onCurve))
    case "segment":
        guard d["name"] is NSNull || name != nil, let a = d["a"] as? String, let b = d["b"] as? String else { return nil }
        return .segment(Segment(id: id, name: name, a: a, b: b))
    case "line":
        guard let name, let a = d["a"] as? String, let b = d["b"] as? String else { return nil }
        return .line(StraightLine(id: id, name: name, a: a, b: b))
    case "ray":
        guard let name, let a = d["a"] as? String, let b = d["b"] as? String else { return nil }
        return .ray(StraightLine(id: id, name: name, a: a, b: b))
    case "circle":
        guard let name, let center = d["center"] as? String, d["through"] is NSNull || d["through"] is String,
              let radius = number(d["radius"]), let locked = boolean(d["locked"]) else { return nil }
        var span: [Id]?
        if let raw = d["span"] {
            guard let list = raw as? [String], list.count == 2 else { return nil }
            span = list
        }
        return .circle(Circle(id: id, name: name, center: center, through: d["through"] as? String, span: span, radius: radius, locked: locked))
    default:
        return nil
    }
}

/// Checks that parsed JSON is a sound construction (known kinds, fields, references, no cycles).
private func validate(_ data: [String: Any]) -> Construction? {
    guard let raw = data["objects"] as? [[String: Any]], let nextValue = number(data["nextId"]) else { return nil }
    let nextId = Int(nextValue)
    var ids = Set<Id>()
    var list: [GeoObject] = []
    for d in raw {
        guard let o = object(from: d), !ids.contains(o.id), o.id.wholeMatch(of: /o[0-9]+/) != nil,
              (Int(o.id.dropFirst()) ?? .max) < nextId else { return nil }
        ids.insert(o.id)
        list.append(o)
    }
    if list.contains(where: { parentsOf($0).contains { !ids.contains($0) } }) { return nil }
    guard let ordered = toposort(list) else { return nil }
    var c = Construction()
    c.objects = ordered
    c.nextId = nextId
    for (id, value) in data["styles"] as? [String: [String: Any]] ?? [:] {
        guard ids.contains(id), let opacity = number(value["opacity"]), let dashed = boolean(value["dashed"]) else { continue }
        c.styles[id] = ObjectStyle(opacity: opacity, dashed: dashed, color: isColor(value["color"]) ? value["color"] as? String : nil)
    }
    // The exercise is re-closed under "built on", so a hand-edited file can't break the rule.
    let given = (data["exercise"] as? [Any] ?? []).compactMap { $0 as? String }.filter(ids.contains)
    if !given.isEmpty { c.setExercise(given, on: true) }
    return c
}

/// The sketch strokes that are sound; a damaged sketch never stops the drawing from opening.
private func validSketch(_ value: Any?) -> [SketchStroke] {
    (value as? [[String: Any]] ?? []).compactMap { st in
        guard let tool = st["tool"] as? String, tool == "pen" || tool == "eraser", let color = st["color"] as? String,
              color == "ink" || isColor(color), let raw = st["pts"] as? [Any], raw.count % 2 == 0 else { return nil }
        let pts = raw.compactMap(number)
        return pts.count == raw.count ? SketchStroke(tool: tool, color: color, pts: pts) : nil
    }
}

/// Writes a .geoscript file. `steps` is the protocol, `titles` its headings.
public func exportFile(_ contents: FileContents, steps: [ProtocolStep], stepsTitle: String, exerciseTitle: String, graphsTitle: String = "Graphs") -> String {
    let given = steps.filter(\.exercise)
    let own = steps.filter { !$0.exercise }
    let graphRows = soundCrossings(contents.graphs.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.between != nil })
    // A row of kept crossings is written "∩ 1, 2": the numbers of its two rows in the list.
    func graphLine(_ g: GraphRow) -> String {
        if let between = g.between {
            let numbers = between.map { id in String((graphRows.firstIndex { $0.id == id } ?? -1) + 1) }
            return "∩ \(numbers.joined(separator: ", "))"
        }
        return g.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var lines = [magic, ""]
    if !given.isEmpty { lines += ["\(exerciseTitle):"] + given.map { "- \($0.text)" } + [""] }
    if !steps.isEmpty || graphRows.isEmpty {
        lines += ["\(stepsTitle):"] + own.enumerated().map { "\($0 + 1). \($1.text)" } + [""]
    }
    if !graphRows.isEmpty { lines += ["\(graphsTitle):"] + graphRows.map { "- \(graphLine($0))" } + [""] }
    lines.append(dataMark)

    let c = contents.construction
    var styles: [String: Any] = [:]
    for (id, s) in c.styles {
        var d: [String: Any] = ["opacity": s.opacity, "dashed": s.dashed]
        if let color = s.color { d["color"] = color }
        styles[id] = d
    }
    let sketch: [[String: Any]] = contents.sketch.map {
        ["tool": $0.tool, "color": $0.color, "pts": $0.pts.map { ($0 * 10).rounded() / 10 }]
    }
    let data: [String: Any] = ["objects": c.objects.map(json), "nextId": c.nextId, "styles": styles,
                               "exercise": c.exercise ?? [], "sketch": sketch, "graphs": graphRows.map(\.json)]
    let body = (try? JSONSerialization.data(withJSONObject: data, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    return lines.joined(separator: "\n") + "\n" + body + "\n"
}

public func importFile(_ text: String, _ ctx: TypingContext) -> Result<FileContents, FileError> {
    if let at = text.range(of: dataMark) {
        guard let raw = String(text[at.upperBound...]).data(using: .utf8),
              let data = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let c = validate(data) else { return .failure(.invalid) }
        return .success(FileContents(construction: c, sketch: validSketch(data["sketch"]), graphs: validGraphs(data["graphs"])))
    }
    // Only protocol steps: "1. AB; |AB| = 6 cm" (numbers optional). Other lines are skipped.
    var c = Construction()
    var steps = 0
    var inExercise = false
    var inGraphs = false
    var given: [Id] = []
    var graphRows: [GraphRow] = []
    let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    for (i, rawLine) in lines.enumerated() {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasSuffix(":") {
            let heading = line.lowercased()
            inExercise = heading == "zadání:" || heading == "exercise:"
            inGraphs = heading == "grafy:" || heading == "graphs:"
        }
        if line.isEmpty || line == magic || line.hasSuffix(":") { continue }
        let body = line.replacing(/^([0-9]+[.)]|-)\s*/, with: "")
        if inGraphs {
            let n = graphRows.count
            var row = GraphRow(id: "g\(n + 1)", text: String(body), color: graphColors[n % graphColors.count])
            if let m = body.wholeMatch(of: /∩\s*([0-9]+)\s*,\s*([0-9]+)/) {
                row.text = ""
                row.between = ["g\(m.1)", "g\(m.2)"]
            }
            graphRows.append(row)
            continue
        }
        let before = Set(c.objects.map(\.id))
        guard case .success(let r) = c.applyStep(String(body), ctx) else { return .failure(.badStep(line: i + 1)) }
        c = r.construction
        if inExercise { given += c.objects.map(\.id).filter { !before.contains($0) } }
        steps += 1
    }
    if !given.isEmpty { c.setExercise(given, on: true) }
    if steps == 0, graphRows.isEmpty { return .failure(.invalid) }
    return .success(FileContents(construction: c, graphs: soundCrossings(graphRows)))
}

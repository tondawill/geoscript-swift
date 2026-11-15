import CoreGraphics
import Foundation
import GeoEngine

enum Prompt: Hashable {
    /// `fresh`: the point was just placed, so naming it is part of the same undo step.
    case name(Id, fresh: Bool)
    case dimension(Id)
    case angle(Id)

    var id: Id {
        switch self {
        case .name(let id, _), .dimension(let id), .angle(let id): id
        }
    }
}

extension DrawingStore {
    var promptLabel: String {
        switch prompt {
        case .dimension: "="
        case .angle: "α ="
        default: t("name.label")
        }
    }

    var promptSuffix: String? {
        switch prompt {
        case .dimension: "cm"
        case .angle: "°"
        default: nil
        }
    }

    /// Screen position the box is placed next to.
    var promptAnchor: CGPoint? {
        guard let prompt, let object = construction.object(prompt.id) else { return nil }
        let positions = construction.resolve()
        if let p = positions[object.id] { return screen(p) }
        switch curveGeom(object, positions) {
        case let .straight(a, b, _): return screen(Vec(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2))
        case let .circle(center, radius): return screen(polar(center, radius, .pi / 4))
        case nil: return nil
        }
    }

    private func openPrompt(_ next: Prompt, text: String) {
        prompt = next
        promptText = text
        promptError = nil
    }

    func openNamePrompt(_ o: GeoObject, fresh: Bool = false) {
        openPrompt(.name(o.id, fresh: fresh), text: o.name ?? "")
    }

    func openDimensionPrompt(_ o: GeoObject) {
        let positions = construction.resolve()
        guard let value = construction.segmentLength(o, positions) ?? construction.circleRadius(o, positions) else { return }
        openPrompt(.dimension(o.id), text: dim(value))
    }

    func openAnglePrompt(_ o: GeoObject) {
        guard let rel = construction.relationOf(o) else { return }
        openPrompt(.angle(o.id), text: dim(rel.angle * 180 / .pi))
    }

    private func nameError(_ raw: String, for object: GeoObject) -> String? {
        let name = normalizeName(raw)
        if object.isPoint {
            guard isValidPointName(name) else { return t("error.pointName") }
        } else if case .segment = object, name.isEmpty {
            return nil
        } else if !isValidLowerName(name) {
            return t("error.lowerName")
        }
        return construction.isNameTaken(name, except: object.id) ? t("error.nameTaken", ["name": name]) : nil
    }

    func message(for error: DimensionError) -> String {
        switch error {
        case .cannotEditSegment: t("error.cannotEditSegment")
        case .cannotEditCircle: t("error.cannotEditCircle")
        case .exerciseLocked: t("exercise.locked")
        }
    }

    /// Sets a length or radius. Returns an error message, or nil when it was applied.
    func applyDimension(_ id: Id, _ value: Double) -> String? {
        guard let object = construction.object(id) else { return nil }
        var failure: DimensionError?
        commit { c in
            if case .circle = object { failure = c.setCircleRadius(id, value) } else { failure = c.setSegmentLength(id, value) }
            return failure == nil
        }
        return failure.map(message(for:))
    }

    /// Changes a relation's angle. Returns an error message, or nil when it was applied.
    func applyAngle(_ id: Id, _ degrees: Double) -> String? {
        guard degrees > 0, degrees < 180 else { return t("error.angle") }
        guard let next = construction.settingRelationAngle(id, degrees * .pi / 180) else { return nil }
        if construction.touchesExercise(after: next) { return t("exercise.locked") }
        commit {
            $0 = next
            return true
        }
        return nil
    }

    func unlockDimension(_ id: Id) {
        guard let object = construction.object(id) else { return }
        commit { c in
            if case .circle = object { c.unlockCircle(id) } else { c.unlockSegment(id) }
            return true
        }
    }

    func removeRelation(_ id: Id) {
        let resolved = construction.resolve()
        commit {
            $0 = $0.removingRelation(id, resolved)
            return true
        }
    }

    func beginRename() {
        guard let selection, !refuseExercise(selection), let o = construction.object(selection) else { return }
        openNamePrompt(o)
    }

    /// Enter in the box: applies the value, or shows why it can't be used.
    func submitPrompt() {
        promptError = applyPrompt()
        if promptError == nil { prompt = nil }
    }

    func closePrompt() {
        prompt = nil
    }

    /// Clicking elsewhere: a valid entry is kept, an invalid one is dropped.
    func closePromptKeepingValid() {
        guard prompt != nil else { return }
        _ = applyPrompt()
        prompt = nil
    }

    /// Returns an error message, or nil when the entry was applied.
    private func applyPrompt() -> String? {
        switch prompt {
        case let .name(id, fresh):
            guard let object = construction.object(id) else { return nil }
            if let error = nameError(promptText, for: object) { return error }
            let name = normalizeName(promptText)
            let newName = name.isEmpty ? nil : name
            if fresh {
                construction.renameObject(id, newName)
                changed()
            } else {
                commit {
                    $0.renameObject(id, newName)
                    return true
                }
            }
            return nil
        case .dimension(let id):
            guard let value = parseNumber(promptText) else { return t("error.number") }
            return applyDimension(id, value)
        case .angle(let id):
            guard let value = parseNumber(promptText) else { return t("error.angle") }
            return applyAngle(id, value)
        case nil:
            return nil
        }
    }
}

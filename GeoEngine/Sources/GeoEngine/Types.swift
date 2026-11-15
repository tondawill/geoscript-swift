/// Geometry engine data model. World units are centimetres, y axis points up.

public typealias Id = String

public struct Vec: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// A point placed freely on the plane: a root node of the DAG.
public struct FreePoint: Equatable, Sendable {
    public var id: Id
    public var name: String
    /// Helper point of a line: never drawn, snapped to, named or dragged.
    public var hidden = false
    /// Placed on its own: it keeps its own protocol step instead of being folded into a later segment.
    public var ownStep = false
    public var x: Double
    public var y: Double
}

/// A point at a fixed distance from a parent. Dragging it changes only the angle.
/// With `toward` set, it lies on the ray from the parent through that point ("C ∈ ↦AB ∧ |AC| = 5 cm"):
/// `angle` is then ignored and the point cannot be dragged.
public struct DistancePoint: Equatable, Sendable {
    public var id: Id
    public var name: String
    public var hidden = false
    public var parent: Id
    public var distance: Double
    public var angle: Double
    public var toward: Id? = nil
}

/// Intersection of two curves. `index` picks one of the (up to two) solutions.
/// When the objects stop crossing, the point is undefined.
public struct IntersectionPoint: Equatable, Sendable {
    public var id: Id
    public var name: String
    public var hidden = false
    public var a: Id
    public var b: Id
    public var index: Int
}

/// A point lying on one object. `t` is the parameter along a straight object or the angle on a circle.
public struct PointOnObject: Equatable, Sendable {
    public var id: Id
    public var name: String
    public var hidden = false
    public var on: Id
    public var t: Double
}

public struct OnCurve: Equatable, Sendable {
    public var id: Id
    public var index: Int
    public init(id: Id, index: Int) { self.id = id; self.index = index }
}

/// A point whose direction from `parent` is tied to a line: parent + distance · (direction of `ref`
/// rotated by `offset`). With `onCurve` set, it is where that ray meets the curve instead.
public struct DirectionPoint: Equatable, Sendable {
    public var id: Id
    public var name: String
    public var hidden = false
    public var parent: Id
    public var ref: Id
    public var offset: Double
    public var distance: Double
    public var lengthLocked: Bool
    public var onCurve: OnCurve?
}

/// Segment AB. `name` is an optional custom lowercase name; otherwise it is shown as its endpoints.
public struct Segment: Equatable, Sendable {
    public var id: Id
    public var name: String?
    public var a: Id
    public var b: Id
}

/// Line ↔AB or ray ↦AB.
public struct StraightLine: Equatable, Sendable {
    public var id: Id
    public var name: String
    public var a: Id
    public var b: Id
}

/// Circle k(S, r): through a point, with a radius equal to a distance of two points (`span`), or numeric.
public struct Circle: Equatable, Sendable {
    public var id: Id
    public var name: String
    public var center: Id
    public var through: Id?
    public var span: [Id]?
    public var radius: Double
    public var locked: Bool
}

public enum GeoObject: Equatable, Sendable {
    case freePoint(FreePoint)
    case distancePoint(DistancePoint)
    case intersectionPoint(IntersectionPoint)
    case pointOn(PointOnObject)
    case directionPoint(DirectionPoint)
    case segment(Segment)
    case line(StraightLine)
    case ray(StraightLine)
    case circle(Circle)

    public var id: Id {
        switch self {
        case .freePoint(let o): o.id
        case .distancePoint(let o): o.id
        case .intersectionPoint(let o): o.id
        case .pointOn(let o): o.id
        case .directionPoint(let o): o.id
        case .segment(let o): o.id
        case .line(let o), .ray(let o): o.id
        case .circle(let o): o.id
        }
    }

    public var name: String? {
        get {
            switch self {
            case .freePoint(let o): o.name
            case .distancePoint(let o): o.name
            case .intersectionPoint(let o): o.name
            case .pointOn(let o): o.name
            case .directionPoint(let o): o.name
            case .segment(let o): o.name
            case .line(let o), .ray(let o): o.name
            case .circle(let o): o.name
            }
        }
        set {
            let text = newValue ?? ""
            switch self {
            case .freePoint(var o): o.name = text; self = .freePoint(o)
            case .distancePoint(var o): o.name = text; self = .distancePoint(o)
            case .intersectionPoint(var o): o.name = text; self = .intersectionPoint(o)
            case .pointOn(var o): o.name = text; self = .pointOn(o)
            case .directionPoint(var o): o.name = text; self = .directionPoint(o)
            case .segment(var o): o.name = newValue; self = .segment(o)
            case .line(var o): o.name = text; self = .line(o)
            case .ray(var o): o.name = text; self = .ray(o)
            case .circle(var o): o.name = text; self = .circle(o)
            }
        }
    }

    public var isPoint: Bool {
        switch self {
        case .freePoint, .distancePoint, .intersectionPoint, .pointOn, .directionPoint: true
        default: false
        }
    }

    public var isHidden: Bool {
        get {
            switch self {
            case .freePoint(let o): o.hidden
            case .distancePoint(let o): o.hidden
            case .intersectionPoint(let o): o.hidden
            case .pointOn(let o): o.hidden
            case .directionPoint(let o): o.hidden
            default: false
            }
        }
        set {
            switch self {
            case .freePoint(var o): o.hidden = newValue; self = .freePoint(o)
            case .distancePoint(var o): o.hidden = newValue; self = .distancePoint(o)
            case .intersectionPoint(var o): o.hidden = newValue; self = .intersectionPoint(o)
            case .pointOn(var o): o.hidden = newValue; self = .pointOn(o)
            case .directionPoint(var o): o.hidden = newValue; self = .directionPoint(o)
            default: break
            }
        }
    }

    /// Straight objects: segment, line, ray.
    public var isLinear: Bool {
        switch self {
        case .segment, .line, .ray: true
        default: false
        }
    }

    /// Objects that points can be placed on or intersected with.
    public var isCurve: Bool {
        if case .circle = self { return true }
        return isLinear
    }
}

/// How an object is drawn.
public struct ObjectStyle: Equatable, Sendable {
    /// 0.5 … 1: objects can be faded to half, never hidden.
    public var opacity: Double
    /// Dashed instead of solid (ignored for points).
    public var dashed: Bool
    /// A palette name or "#rrggbb"; nil means the default ink.
    public var color: String?

    public init(opacity: Double = 1, dashed: Bool = false, color: String? = nil) {
        self.opacity = opacity
        self.dashed = dashed
        self.color = color
    }

    public static let minOpacity = 0.5
}

/// World positions of all points, computed by `Construction.resolve()`.
public typealias Resolved = [Id: Vec]

/// The construction is a DAG stored in insertion order. Every object only references objects added
/// before it, so the array order is a valid topological order.
public struct Construction: Equatable, Sendable {
    public var objects: [GeoObject] = []
    public var nextId = 1
    /// Per-object appearance; objects without an entry use the default style.
    public var styles: [Id: ObjectStyle] = [:]
    /// The exercise ("zadání"): objects given by the task, always closed under "built on".
    public var exercise: [Id]?

    public init() {}
}

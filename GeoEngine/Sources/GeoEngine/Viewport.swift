/// screen = (x · scale + tx, −y · scale + ty): world y points up, screen y points down.
public struct Viewport: Equatable, Sendable {
    /// 1 cm on screen at 100 % zoom (96 px per inch / 2.54).
    public static let pxPerCm = 96 / 2.54
    public static let minScale = pxPerCm / 20
    public static let maxScale = pxPerCm * 20

    public var scale: Double
    public var tx: Double
    public var ty: Double

    public init(width: Double, height: Double) {
        scale = Self.pxPerCm
        tx = width / 2
        ty = height / 2
    }

    public init(scale: Double, tx: Double, ty: Double) {
        self.scale = scale
        self.tx = tx
        self.ty = ty
    }

    public func toScreen(_ p: Vec) -> Vec {
        Vec(x: p.x * scale + tx, y: -p.y * scale + ty)
    }

    public func toWorld(_ s: Vec) -> Vec {
        Vec(x: (s.x - tx) / scale, y: -(s.y - ty) / scale)
    }

    /// Zooms by `factor`, keeping the world point under the screen point `at` fixed.
    public mutating func zoom(at: Vec, factor: Double) {
        zoom(at: at, factor: factor, range: Self.minScale...Self.maxScale)
    }

    /// Zooms within `range` (pixels per unit), keeping the world point under `at` fixed.
    public mutating func zoom(at: Vec, factor: Double, range: ClosedRange<Double>) {
        let next = min(range.upperBound, max(range.lowerBound, scale * factor))
        let f = next / scale
        scale = next
        tx = at.x - (at.x - tx) * f
        ty = at.y - (at.y - ty) * f
    }

    public mutating func pan(dx: Double, dy: Double) {
        tx += dx
        ty += dy
    }
}

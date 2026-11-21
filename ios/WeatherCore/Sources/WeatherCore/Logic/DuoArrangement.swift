import Foundation

/// Where the hinge sits, in the status page's own coordinates.
public struct DuoDivision: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

/// How the status page uses the two displays.
///
/// Cover and a fully open inner display stay one scrolling column. A column
/// is also the answer when this SDK cannot see the hinge. A book fold (the
/// hinge runs down the display) puts the status on one side and the charts
/// on the other. A tent fold (the hinge runs across) puts the status above
/// the hinge and the charts below it.
public enum DuoArrangement: Equatable, Sendable {
    case column
    case book(leading: Double, gap: Double, trailing: Double)
    case tent(top: Double, gap: Double, bottom: Double)

    /// `division` is the active hinge. Nil means flat, closed, or unknown.
    public static func arrangement(
        containerWidth: Double,
        containerHeight: Double,
        division: DuoDivision?
    ) -> DuoArrangement {
        guard let division, containerWidth > 1, containerHeight > 1 else { return .column }
        let verticalFold = division.height >= division.width
        if verticalFold {
            guard division.height > containerHeight * 0.5 else { return .column }
            let leading = max(0, division.x)
            let trailing = max(0, containerWidth - division.maxX)
            guard leading >= 120, trailing >= 120 else { return .column }
            return .book(leading: leading, gap: division.width, trailing: trailing)
        }
        guard division.width > containerWidth * 0.5 else { return .column }
        let top = max(0, division.y)
        let bottom = max(0, containerHeight - division.maxY)
        guard top >= 120, bottom >= 120 else { return .column }
        return .tent(top: top, gap: division.height, bottom: bottom)
    }
}

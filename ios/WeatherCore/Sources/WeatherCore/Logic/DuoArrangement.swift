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
/// No division rect means the cover, or any phone that has no hinge, so the
/// page stays one column. A division that runs down the inner display is a
/// book: status on one side, charts on the other. A division that runs across
/// it is a tent: status above, charts below. When the hinge is actually
/// separating the glass, the gap is the division's own frame. When the inner
/// display is flat, the two sides still meet at the hinge and the gap is zero.
public enum DuoArrangement: Equatable, Sendable {
    case column
    case book(leading: Double, gap: Double, trailing: Double)
    case tent(top: Double, gap: Double, bottom: Double)

    /// `division` is the hinge the system reported for this view. Nil means
    /// the cover or a display with no fold. `hingeSeparates` is the region's
    /// active flag: true while the device is partly folded, false while the
    /// inner display is flat.
    public static func arrangement(
        containerWidth: Double,
        containerHeight: Double,
        division: DuoDivision?,
        hingeSeparates: Bool = true
    ) -> DuoArrangement {
        guard let division, containerWidth > 1, containerHeight > 1 else { return .column }
        let verticalFold = division.height >= division.width
        if verticalFold {
            let overlap = overlap(
                start: division.y, length: division.height, container: containerHeight)
            guard overlap > containerHeight * 0.5 else { return .column }
            if hingeSeparates {
                let leading = max(0, division.x)
                let trailing = max(0, containerWidth - division.maxX)
                guard leading >= 120, trailing >= 120 else { return .column }
                return .book(leading: leading, gap: max(0, division.width), trailing: trailing)
            }
            let mid = division.x + division.width / 2
            let leading = min(max(mid, 0), containerWidth)
            let trailing = containerWidth - leading
            guard leading >= 120, trailing >= 120 else { return .column }
            return .book(leading: leading, gap: 0, trailing: trailing)
        }
        let overlap = overlap(
            start: division.x, length: division.width, container: containerWidth)
        guard overlap > containerWidth * 0.5 else { return .column }
        if hingeSeparates {
            let top = max(0, division.y)
            let bottom = max(0, containerHeight - division.maxY)
            guard top >= 120, bottom >= 120 else { return .column }
            return .tent(top: top, gap: max(0, division.height), bottom: bottom)
        }
        let mid = division.y + division.height / 2
        let top = min(max(mid, 0), containerHeight)
        let bottom = containerHeight - top
        guard top >= 120, bottom >= 120 else { return .column }
        return .tent(top: top, gap: 0, bottom: bottom)
    }

    private static func overlap(start: Double, length: Double, container: Double) -> Double {
        let end = start + length
        return min(end, container) - max(start, 0)
    }
}

/// Space an active camera or status occlusion takes inside the page.
public struct DuoPadding: Equatable, Sendable {
    public var top: Double
    public var leading: Double
    public var bottom: Double
    public var trailing: Double

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    public static let zero = DuoPadding(top: 0, leading: 0, bottom: 0, trailing: 0)
}

public enum DuoOcclusionLayout {
    /// Each frame already includes the system's margins. An occlusion that
    /// misses the view adds nothing. One that overlaps is cleared on the
    /// edge nearest its centre, out to the far side of the overlap.
    public static func padding(
        frames: [DuoDivision],
        containerWidth: Double,
        containerHeight: Double
    ) -> DuoPadding {
        guard containerWidth > 1, containerHeight > 1 else { return .zero }
        var top = 0.0
        var leading = 0.0
        var bottom = 0.0
        var trailing = 0.0
        for frame in frames {
            let minX = max(frame.x, 0)
            let minY = max(frame.y, 0)
            let maxX = min(frame.maxX, containerWidth)
            let maxY = min(frame.maxY, containerHeight)
            guard maxX - minX > 1, maxY - minY > 1 else { continue }
            let centerX = (minX + maxX) / 2
            let centerY = (minY + maxY) / 2
            let toLeading = centerX
            let toTrailing = containerWidth - centerX
            let toTop = centerY
            let toBottom = containerHeight - centerY
            let nearest = min(toLeading, toTrailing, toTop, toBottom)
            if nearest == toLeading {
                leading = max(leading, maxX)
            } else if nearest == toTrailing {
                trailing = max(trailing, containerWidth - minX)
            } else if nearest == toTop {
                top = max(top, maxY)
            } else {
                bottom = max(bottom, containerHeight - minY)
            }
        }
        return DuoPadding(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }
}

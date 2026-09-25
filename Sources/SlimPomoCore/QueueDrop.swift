import CoreGraphics
import Foundation

/// Where the dashed gap sits while a queue row is dragged.
/// The gap moves when the pointer passes the midpoint of the neighbouring row.
public enum QueueDrop {
    public static func gapIndex(
        pointerY: CGFloat,
        rowHeight: CGFloat,
        gap: Int,
        lower: Int,
        upper: Int
    ) -> Int {
        guard upper >= lower else { return lower }
        let height = rowHeight > 1 ? rowHeight : 1
        var gap = min(max(gap, lower), upper)
        while gap > lower {
            let aboveMidpoint = (CGFloat(gap) - 0.5) * height
            if pointerY < aboveMidpoint {
                gap -= 1
            } else {
                break
            }
        }
        while gap < upper {
            let belowMidpoint = (CGFloat(gap) + 1.5) * height
            if pointerY > belowMidpoint {
                gap += 1
            } else {
                break
            }
        }
        return gap
    }

    /// Releasing above the list still drops into the top legal slot the outline is showing.
    /// Releasing below the list, or off to the side, does not.
    public static func releaseLandsInQueue(
        pointerX: CGFloat,
        pointerY: CGFloat,
        listWidth: CGFloat,
        listHeight: CGFloat
    ) -> Bool {
        let horizontal = pointerX >= -32 && pointerX <= listWidth + 32
        return horizontal && pointerY <= listHeight + 12
    }
}

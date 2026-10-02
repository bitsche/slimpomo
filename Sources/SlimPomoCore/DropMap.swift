import CoreGraphics
import Foundation

/// One vertical stretch of the list and the place a held task lands when the pointer is in it.
public struct DropBand: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The upper half of a row: before it.
        case before
        /// The lower half of a row: after it.
        case after
        /// The dashed gap the held task sits in.
        case held
        /// A day's drop zone while the day is empty.
        case zone
        /// The LATER header or a day label: the start of the group below.
        case label
        /// An empty region with nothing drawn, or the space after the last row.
        case tail
    }

    public var slot: DragSlot
    public var kind: Kind
    /// Infinite for the first band above the list and the last band below it.
    public var minY: CGFloat
    public var maxY: CGFloat

    public init(slot: DragSlot, kind: Kind, minY: CGFloat, maxY: CGFloat) {
        self.slot = slot
        self.kind = kind
        self.minY = minY
        self.maxY = maxY
    }

    public func contains(_ y: CGFloat) -> Bool {
        y >= minY && y < maxY
    }
}

/// Where the held task is, plus the band the pointer was in when the task moved there.
public struct DropTarget: Equatable, Sendable {
    public var slot: DragSlot
    /// The stretch the pointer was in before the list shifted under it. See `DropMap.resolve`.
    public var carried: ClosedRange<CGFloat>?

    public init(slot: DragSlot, carried: ClosedRange<CGFloat>? = nil) {
        self.slot = slot
        self.carried = carried
    }
}

/// Maps the pointer's y to a drop position. The bands tile the whole list from top to bottom, so every y has
/// exactly one target, and they are computed from the layout as it is drawn right now.
public enum DropMap {
    /// How far the pointer must move into another band before the held task goes there.
    public static let hysteresis: CGFloat = 4

    /// Half of the gap that follows each row. A row's band reaches this far into the gap on both sides.
    static var halfGap: CGFloat { (DragMetrics.stride - DragMetrics.rowHeight) / 2 }

    /// The bands for the list with the held task at `held`.
    public static func bands(regions: [DragRegionSpec], held: DragSlot) -> [DropBand] {
        let blocks = DragGeometry.blocks(regions, held: held.region)
        let tops = DragGeometry.tops(blocks)
        let stride = DragMetrics.stride
        let heading = DragMetrics.headingHeight + DragMetrics.headingBottom
        let half = halfGap
        let firstDay = blocks.indices.first { blocks[$0].id != .queue && blocks[$0].rows > 0 }

        func clamp(_ index: Int, in region: Int) -> Int {
            let slots = regions[region].slots
            return min(max(index, slots.lowerBound), slots.upperBound)
        }

        /// Where the band of the region ends and the next one starts.
        func end(of region: Int) -> CGFloat {
            guard let next = blocks.indices.first(where: { $0 > region && blocks[$0].rows > 0 }) else {
                return .infinity
            }
            if next == firstDay {
                return tops[next] - heading - DragMetrics.laterTopPadding - DragMetrics.laterHeaderHeight
            }
            return tops[next] - heading - DragMetrics.headingTopGap / 2
        }

        var result: [DropBand] = []
        var cursor: CGFloat = -.infinity

        func append(_ slot: DragSlot, _ kind: DropBand.Kind, to bottom: CGFloat) {
            guard bottom > cursor else { return }
            if let last = result.last, last.slot == slot, last.kind != .held, kind != .held {
                result[result.count - 1].maxY = bottom
            } else {
                result.append(DropBand(slot: slot, kind: kind, minY: cursor, maxY: bottom))
            }
            cursor = bottom
        }

        for (index, region) in regions.enumerated() {
            let block = blocks[index]
            let regionEnd = end(of: index)
            if block.rows == 0 {
                if region.id == .queue {
                    append(DragSlot(region: .queue, index: clamp(0, in: index)), .tail, to: regionEnd)
                }
                continue
            }
            let top = tops[index]
            if region.id != .queue {
                append(DragSlot(region: region.id, index: clamp(0, in: index)), .label, to: top - half)
            }
            let holdsGap = region.id == held.region
            let gapRow = min(max(held.index, 0), block.rows - 1)
            for row in 0..<block.rows {
                let rowTop = top + CGFloat(row) * stride
                let last = row == block.rows - 1
                let bottom = last ? regionEnd : rowTop + stride - half
                if holdsGap, row == gapRow {
                    append(DragSlot(region: region.id, index: clamp(held.index, in: index)), .held, to: bottom)
                } else if !holdsGap, region.items == 0 {
                    append(DragSlot(region: region.id, index: clamp(0, in: index)), .zone, to: bottom)
                } else {
                    let others = holdsGap && row > gapRow ? row - 1 : row
                    append(DragSlot(region: region.id, index: clamp(others, in: index)), .before, to: rowTop + DragMetrics.rowHeight / 2)
                    append(DragSlot(region: region.id, index: clamp(others + 1, in: index)), .after, to: bottom)
                }
            }
        }
        if let last = result.indices.last {
            result[last].maxY = .infinity
        }
        return result
    }

    /// The band under `y`.
    public static func band(at y: CGFloat, in bands: [DropBand]) -> DropBand? {
        bands.first { $0.contains(y) } ?? bands.last
    }

    /// Where the held task goes when the pointer is at `y`.
    ///
    /// The held task only leaves its slot after the pointer is `hysteresis` beyond the stretch that slot covers.
    /// A move between regions shifts the rows below it by one stride, so the pointer can end up outside the band it
    /// just chose. The band it was in when the task moved is carried, and keeps the task there until the pointer
    /// leaves it. Without it the task would jump on to the next region at once.
    public static func resolve(pointerY y: CGFloat, regions: [DragRegionSpec], current: DropTarget) -> DropTarget {
        guard regions.contains(where: { $0.id == current.slot.region }) else { return current }
        let all = bands(regions: regions, held: current.slot)
        guard let hit = band(at: y, in: all) else { return current }
        if hit.slot == current.slot {
            return DropTarget(slot: current.slot, carried: nil)
        }
        let margin = hysteresis
        if let range = extent(of: current.slot, in: all), y >= range.lowerBound - margin, y < range.upperBound + margin {
            return current
        }
        if let carried = current.carried, y >= carried.lowerBound - margin, y < carried.upperBound + margin {
            return current
        }
        return DropTarget(slot: hit.slot, carried: extent(of: hit.slot, in: all))
    }

    private static func extent(of slot: DragSlot, in bands: [DropBand]) -> ClosedRange<CGFloat>? {
        let mine = bands.filter { $0.slot == slot }
        guard let low = mine.map(\.minY).min(), let high = mine.map(\.maxY).max() else { return nil }
        return low...high
    }
}

import CoreGraphics
import Foundation

/// A place a dragged task can land: the queue, or one day of LATER.
public enum DragRegionID: Hashable, Sendable {
    case queue
    case day(String)
}

/// One place in the list: a region and the position among that region's other tasks.
public struct DragSlot: Hashable, Sendable {
    public var region: DragRegionID
    public var index: Int

    public init(region: DragRegionID, index: Int) {
        self.region = region
        self.index = index
    }
}

/// What the resolver needs to know about one region while a task is held.
public struct DragRegionSpec: Equatable, Sendable {
    public var id: DragRegionID
    /// Tasks in the region, not counting the held one.
    public var items: Int
    /// Slots the held task may take, counted among `items`.
    public var slots: ClosedRange<Int>
    /// True when the region draws a drop zone while it is empty (a LATER day while planning).
    public var showsZoneWhenEmpty: Bool
    /// False for a region that is not on screen at all (a collapsed LATER).
    public var visible: Bool

    public init(id: DragRegionID, items: Int, slots: ClosedRange<Int>, showsZoneWhenEmpty: Bool, visible: Bool = true) {
        self.id = id
        self.items = items
        self.slots = slots
        self.showsZoneWhenEmpty = showsZoneWhenEmpty
        self.visible = visible
    }
}

/// Fixed list metrics. The views use the same numbers, so the layout can be computed without measuring
/// anything while rows are sliding.
public enum DragMetrics {
    /// A row (36 pt) plus the 5 pt gap that belongs to it.
    public static let stride: CGFloat = 41
    public static let rowHeight: CGFloat = 36
    /// Space above the first queue row.
    public static let queueTopPadding: CGFloat = 8
    /// Space between the last queue row and the LATER header, after that row's own gap.
    public static let laterGapAfterQueue: CGFloat = 9
    public static let laterGapWithoutQueue: CGFloat = 14
    public static let laterHeaderHeight: CGFloat = 24
    /// Space between the LATER header and the first day heading.
    public static let laterTopPadding: CGFloat = 6
    public static let headingHeight: CGFloat = 14
    public static let headingBottom: CGFloat = 4
    /// Space above every day heading except the first.
    public static let headingTopGap: CGFloat = 10
    /// How far below the last row a release still counts as inside the list.
    public static let releaseSlack: CGFloat = 12
}

public struct DragBlock: Equatable, Sendable {
    public var id: DragRegionID
    /// Space between the previous block's last row and this block's first row.
    public var lead: CGFloat
    /// Rows drawn, including the held task and any drop zone.
    public var rows: Int

    public init(id: DragRegionID, lead: CGFloat, rows: Int) {
        self.id = id
        self.lead = lead
        self.rows = rows
    }
}

/// Positions in the list, in points below the top of the list origin. Everything is computed from the
/// final layout, so it does not depend on where an animation currently is.
public enum DragGeometry {
    public static let stride = DragMetrics.stride
    public static let stickiness: CGFloat = 54

    /// Blocks for the current placement of the held task. `held` is the region it sits in, if any.
    public static func blocks(_ regions: [DragRegionSpec], held: DragRegionID?) -> [DragBlock] {
        var rows: [Int] = []
        for region in regions {
            guard region.visible else {
                rows.append(0)
                continue
            }
            if region.id == held {
                rows.append(region.items + 1)
            } else if region.items == 0, region.showsZoneWhenEmpty {
                rows.append(1)
            } else {
                rows.append(region.items)
            }
        }
        let queueRows = zip(regions, rows).first { $0.0.id == .queue }?.1 ?? 0
        var blocks: [DragBlock] = []
        var firstDay = true
        for (region, count) in zip(regions, rows) {
            switch region.id {
            case .queue:
                blocks.append(DragBlock(id: .queue, lead: count > 0 ? DragMetrics.queueTopPadding : 0, rows: count))
            case .day:
                guard region.visible, count > 0 else {
                    blocks.append(DragBlock(id: region.id, lead: 0, rows: 0))
                    continue
                }
                let heading = DragMetrics.headingHeight + DragMetrics.headingBottom
                if firstDay {
                    let gap = queueRows > 0 ? DragMetrics.laterGapAfterQueue : DragMetrics.laterGapWithoutQueue
                    let lead = gap + DragMetrics.laterHeaderHeight + DragMetrics.laterTopPadding + heading
                    blocks.append(DragBlock(id: region.id, lead: lead, rows: count))
                    firstDay = false
                } else {
                    blocks.append(DragBlock(id: region.id, lead: DragMetrics.headingTopGap + heading, rows: count))
                }
            }
        }
        return blocks
    }

    /// Top of each block's first row.
    public static func tops(_ blocks: [DragBlock]) -> [CGFloat] {
        var y: CGFloat = 0
        var result: [CGFloat] = []
        for block in blocks {
            y += block.lead
            result.append(y)
            y += CGFloat(block.rows) * stride
        }
        return result
    }

    /// Bottom edge of the last drawn row (the row's own gap included).
    public static func bottom(_ blocks: [DragBlock]) -> CGFloat {
        guard let last = blocks.lastIndex(where: { $0.rows > 0 }) else { return 0 }
        let tops = tops(blocks)
        return tops[last] + CGFloat(blocks[last].rows) * stride
    }

    /// The LATER header's vertical range, or nil while no day is drawn.
    public static func laterHeader(_ blocks: [DragBlock]) -> ClosedRange<CGFloat>? {
        let tops = tops(blocks)
        guard let first = blocks.indices.first(where: { blocks[$0].id != .queue && blocks[$0].rows > 0 }) else { return nil }
        let heading = DragMetrics.headingHeight + DragMetrics.headingBottom
        let bottom = tops[first] - heading - DragMetrics.laterTopPadding
        return (bottom - DragMetrics.laterHeaderHeight)...bottom
    }

    /// The block nearest to `y`. A block that holds `y` wins; between blocks the closer edge wins.
    /// `favoring` is the block the gap is already in. It keeps the gap while the pointer is within `stickiness` of it,
    /// which is more than the shift a move causes, so the gap cannot jump back and forth between two regions.
    public static func nearestBlock(at y: CGFloat, in blocks: [DragBlock], favoring: Int? = nil) -> Int? {
        let tops = tops(blocks)
        var best: (index: Int, distance: CGFloat)?
        for index in blocks.indices where blocks[index].rows > 0 {
            let top = tops[index]
            let bottom = top + CGFloat(blocks[index].rows) * stride
            var distance: CGFloat = y < top ? top - y : (y >= bottom ? y - bottom + 0.001 : 0)
            if index == favoring {
                distance -= stickiness
            }
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    /// The drawn row under `y`: its block and row number. Nil in a row's trailing gap, in a lead, or outside.
    public static func row(at y: CGFloat, in blocks: [DragBlock]) -> (region: DragRegionID, row: Int)? {
        let tops = tops(blocks)
        for index in blocks.indices where blocks[index].rows > 0 {
            let top = tops[index]
            let local = y - top
            guard local >= 0, local < CGFloat(blocks[index].rows) * stride else { continue }
            let row = Int(local / stride)
            let inRow = local - CGFloat(row) * stride < DragMetrics.rowHeight
            return inRow ? (blocks[index].id, row) : nil
        }
        return nil
    }

    /// Where the held task goes when the pointer is at `y`. The gap only leaves its region when the pointer is
    /// closer to another region in the layout that results from the move, so the list never flips back and forth.
    public static func resolve(
        pointerY y: CGFloat,
        regions: [DragRegionSpec],
        current: DragSlot
    ) -> DragSlot {
        guard let currentIndex = regions.firstIndex(where: { $0.id == current.region }) else { return current }
        let now = blocks(regions, held: current.region)
        guard var candidate = nearestBlock(at: y, in: now, favoring: currentIndex) else { return current }
        for _ in 0..<3 {
            if candidate == currentIndex {
                let top = tops(now)[currentIndex]
                let allowed = regions[currentIndex].slots
                let index = QueueDrop.gapIndex(
                    pointerY: y - top,
                    rowHeight: stride,
                    gap: current.index,
                    lower: allowed.lowerBound,
                    upper: allowed.upperBound
                )
                return DragSlot(region: current.region, index: index)
            }
            let target = regions[candidate]
            let after = blocks(regions, held: target.id)
            guard let landed = nearestBlock(at: y, in: after, favoring: candidate) else { return current }
            if landed == candidate {
                let top = tops(after)[candidate]
                let v = (y - top) / stride
                let raw = Int((v + 0.5).rounded(.down))
                let index = min(max(raw, target.slots.lowerBound), target.slots.upperBound)
                return DragSlot(region: target.id, index: index)
            }
            candidate = landed
        }
        return current
    }
}

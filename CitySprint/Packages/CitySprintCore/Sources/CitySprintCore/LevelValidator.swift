import Foundation

/// A per-metre occupancy map of lanes that can never be safely ridden
/// (static obstacles plus the full corridor any moving vehicle may sweep).
/// Pedestrians and traffic lights are temporal and can always be waited out
/// with the brake, so they are not part of the map.
public struct BlockMap: Sendable {
    public static let metresPerStep = 1.0
    public static let safetyMargin = 1.5

    public let laneCount: Int
    public private(set) var blocked: [UInt8]
    public private(set) var noLaneChange: [Bool]

    public init(length: Double, laneCount: Int = 3) {
        self.laneCount = laneCount
        let steps = Int((length / BlockMap.metresPerStep).rounded(.up)) + 1
        blocked = [UInt8](repeating: 0, count: steps)
        noLaneChange = [Bool](repeating: false, count: steps)
    }

    public var stepCount: Int { blocked.count }

    private func stepRange(_ y0: Double, _ y1: Double) -> ClosedRange<Int>? {
        let lo = max(0, Int((y0 / BlockMap.metresPerStep).rounded(.down)))
        let hi = min(blocked.count - 1, Int((y1 / BlockMap.metresPerStep).rounded(.up)))
        return lo <= hi ? lo...hi : nil
    }

    /// Lanes whose riding line intersects a footprint centred on `lane` with `width`.
    public static func lanesTouched(lane: Double, width: Double, laneCount: Int = 3,
                                    playerHalfWidth: Double = GameTuning.standard.playerHalfWidth) -> UInt8 {
        var mask: UInt8 = 0
        let reach = width / 2 + playerHalfWidth
        for l in 0..<laneCount where abs(Double(l) - lane) < reach {
            mask |= 1 << UInt8(l)
        }
        return mask
    }

    public mutating func block(mask: UInt8, from y0: Double, to y1: Double) {
        guard mask != 0, let range = stepRange(y0 - BlockMap.safetyMargin, y1 + BlockMap.safetyMargin) else { return }
        for s in range { blocked[s] |= mask }
    }

    public mutating func forbidLaneChange(from y0: Double, to y1: Double) {
        guard let range = stepRange(y0 - BlockMap.safetyMargin, y1 + BlockMap.safetyMargin) else { return }
        for s in range { noLaneChange[s] = true }
    }

    public func isBlocked(lane: Int, from y0: Double, to y1: Double) -> Bool {
        guard let range = stepRange(y0, y1) else { return false }
        let bit = UInt8(1) << UInt8(lane)
        for s in range where blocked[s] & bit != 0 { return true }
        return false
    }

    /// Adds the danger corridor of a lethal entity.
    public mutating func add(_ e: LevelEntity) {
        guard e.kind.isLethal || e.kind == .tramTracks else { return }
        if e.kind == .tramTracks {
            forbidLaneChange(from: e.y, to: e.y + e.length)
            return
        }
        if e.kind == .pedestrian { return }
        let playerLength = GameTuning.standard.playerLength
        var mask = BlockMap.lanesTouched(lane: e.lane, width: e.width, laneCount: laneCount)
        if e.swerve != 0 {
            mask |= BlockMap.lanesTouched(lane: e.lane + e.swerve, width: e.width, laneCount: laneCount)
        }
        if e.kind == .parkedCarDoor {
            // The door swings into the curb lane only.
            mask = 1 << UInt8(laneCount - 1)
        }
        let sweep = e.kind.isMover ? e.travel : 0
        block(mask: mask, from: e.y, to: e.y + e.length + sweep + playerLength)
    }
}

public enum LevelValidator {
    /// Metres needed to complete a lane change at sprint speed, rounded up.
    public static let laneChangeSteps = 3

    /// True when a rider starting in the middle lane can reach the finish
    /// without ever entering a blocked lane segment or changing lanes on rails.
    public static func isPassable(_ map: BlockMap, startLane: Int = 1) -> Bool {
        let n = map.stepCount
        let lanes = map.laneCount
        let all: UInt8 = UInt8((1 << lanes) - 1)
        var reach = [UInt8](repeating: 0, count: n)
        reach[0] = (1 << UInt8(startLane)) & ~map.blocked[0]
        let k = laneChangeSteps
        for s in 0..<(n - 1) {
            let r = reach[s]
            if r == 0 { continue }
            reach[s + 1] |= r & ~map.blocked[s + 1] & all
            guard s + k < n else { continue }
            for l in 0..<lanes where r & (1 << UInt8(l)) != 0 {
                for nl in [l - 1, l + 1] where nl >= 0 && nl < lanes {
                    let pair: UInt8 = (1 << UInt8(l)) | (1 << UInt8(nl))
                    var ok = true
                    for t in s...(s + k) where map.noLaneChange[t] || map.blocked[t] & pair != 0 {
                        ok = false
                        break
                    }
                    if ok { reach[s + k] |= 1 << UInt8(nl) }
                }
            }
        }
        return reach[n - 1] != 0
    }

    public static func map(for level: LevelDefinition, assist: Bool = false) -> BlockMap {
        var map = BlockMap(length: level.length)
        for e in level.entities where !(assist && e.assistSkip) {
            map.add(e)
        }
        return map
    }

    public static func isPassable(_ level: LevelDefinition) -> Bool {
        // Assist mode only removes obstacles, so checking the full set suffices.
        isPassable(map(for: level))
    }
}

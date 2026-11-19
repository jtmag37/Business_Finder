import Foundation

/// Everything that can appear on the road.
public enum EntityKind: UInt8, Codable, Sendable, CaseIterable {
    case car
    case bus
    case parkedCarDoor
    case pothole
    case pedestrian
    case scooter
    case construction
    case tramTracks
    case trafficLight
    case cyclist
    case cobblestones
    case coin
    case water

    /// Touching it ends the run.
    public var isLethal: Bool {
        switch self {
        case .car, .bus, .parkedCarDoor, .pedestrian, .scooter, .construction, .cyclist: return true
        default: return false
        }
    }

    public var isCollectible: Bool { self == .coin || self == .water }

    /// Moves along the road once the player gets close.
    public var isMover: Bool {
        switch self {
        case .car, .bus, .scooter, .cyclist: return true
        default: return false
        }
    }

    /// Spans the whole road for a stretch and changes the riding rules.
    public var isZone: Bool { self == .tramTracks || self == .cobblestones }

    /// Default footprint: (length in metres, width in lanes).
    public var footprint: (length: Double, width: Double) {
        switch self {
        case .car: return (4.4, 0.62)
        case .bus: return (11.5, 0.8)
        case .parkedCarDoor: return (1.1, 0.6)
        case .pothole: return (0.9, 0.38)
        case .pedestrian: return (0.6, 0.28)
        case .scooter: return (1.8, 0.34)
        case .construction: return (16, 0.9)
        case .tramTracks: return (12, 3)
        case .trafficLight: return (0.5, 3)
        case .cyclist: return (1.8, 0.32)
        case .cobblestones: return (50, 3)
        case .coin: return (0.7, 0.3)
        case .water: return (0.8, 0.3)
        }
    }
}

/// Immutable level data. Levels are generated deterministically from a seed
/// (see `LevelGenerator`) and are fully `Codable`, so they can be exported to
/// JSON for tooling or pinned in tests.
public struct LevelEntity: Codable, Equatable, Sendable {
    public var kind: EntityKind
    /// Lateral centre, in lane units. Lanes are 0, 1, 2 (left to right).
    public var lane: Double
    /// Rear edge along the road, in metres.
    public var y: Double
    public var length: Double
    public var width: Double
    /// Movers: cruising speed (m/s). Pedestrians: crossing speed (lanes/s).
    public var speed: Double
    /// Movers: distance travelled before turning off the road.
    public var travel: Double
    /// Movers: lane offset of a single swerve (0 = none).
    public var swerve: Double
    /// Traffic lights: phase offset (s). Pedestrians: direction (+1 / -1).
    public var param: Double
    /// Removed when assist mode is on.
    public var assistSkip: Bool
    /// Cosmetic variation (colour index etc.).
    public var variant: UInt8

    public init(kind: EntityKind, lane: Double, y: Double, length: Double? = nil, width: Double? = nil,
                speed: Double = 0, travel: Double = 0, swerve: Double = 0, param: Double = 0,
                assistSkip: Bool = false, variant: UInt8 = 0) {
        self.kind = kind
        self.lane = lane
        self.y = y
        self.length = length ?? kind.footprint.length
        self.width = width ?? kind.footprint.width
        self.speed = speed
        self.travel = travel
        self.swerve = swerve
        self.param = param
        self.assistSkip = assistSkip
        self.variant = variant
    }
}

public struct LevelID: Hashable, Codable, Sendable, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) { self.rawValue = rawValue }

    public static func city(_ city: CityID, index: Int) -> LevelID {
        let n = index + 1
        return LevelID(rawValue: "\(city.code)-\(n < 10 ? "0" : "")\(n)")
    }

    public static func daily(dayKey: Int) -> LevelID {
        LevelID(rawValue: "daily-\(dayKey)")
    }

    public var description: String { rawValue }
}

public struct LevelDefinition: Codable, Equatable, Sendable {
    public var id: LevelID
    public var city: CityID
    /// 0...9 for city levels, -1 for the daily challenge.
    public var index: Int
    public var seed: UInt64
    public var difficulty: Double
    public var length: Double
    /// Target time (s) for the time star.
    public var parTime: Double
    public var weather: Weather
    /// Sorted by `y`.
    public var entities: [LevelEntity]

    public var isDaily: Bool { index < 0 }

    public var totalCoins: Int { entities.reduce(0) { $0 + ($1.kind == .coin ? 1 : 0) } }

    public func coinsRequiredForStar(assist: Bool) -> Int {
        Int((Double(coinCount(assist: assist)) * ScoreRules.coinStarFraction).rounded(.up))
    }

    public func coinCount(assist: Bool) -> Int {
        entities.reduce(0) { $0 + ($1.kind == .coin && !(assist && $1.assistSkip) ? 1 : 0) }
    }

    public func parTime(assist: Bool) -> Double {
        assist ? (parTime * ScoreRules.assistParMultiplier).rounded() : parTime
    }
}

/// Physics and rules constants. Centralised so they can be tuned and tested.
public struct GameTuning: Sendable {
    public var laneCount = 3
    public var cruiseSpeed = 9.0
    public var sprintSpeed = 12.8
    public var acceleration = 5.0
    public var coastDeceleration = 3.0
    public var brakeDeceleration = 13.0
    public var brakePulse = 0.65
    public var laneChangeSpeed = 6.0          // lanes per second
    public var playerHalfWidth = 0.17         // lanes
    public var playerLength = 1.7             // metres
    public var assistHitboxScale = 0.75

    public var sprintDuration = 1.6
    public var sprintDrainPerSecond = 0.32
    public var staminaRegenPerSecond = 0.07
    public var minimumSprintStamina = 0.12
    public var waterStamina = 0.4

    public var draftMaxGap = 11.0
    public var draftHoldGap = 2.6
    public var draftLateralTolerance = 0.35
    public var draftChargeSeconds = 1.6
    public var draftRegenMultiplier = 3.0
    public var minimumDraftCharge = 0.3
    public var boostSpeed = 5.0
    public var boostDuration = 2.2

    public var cobbleSpeedCap = 6.3
    public var potholeSpeedFactor = 0.45

    public var activationDistance = 30.0
    public var busActivationDistance = 24.0
    public var scanAhead = 90.0
    public var behindMargin = 14.0
    public var doorTriggerDistance = 17.0
    public var doorOpenSeconds = 0.45
    public var pedestrianTriggerDistance = 19.0
    public var swerveDelay = 1.1
    public var swerveSpeed = 1.6               // lanes per second
    public var busAcceleration = 2.4

    public var lightGreen = 5.5
    public var lightYellow = 1.6
    public var lightRed = 3.6
    public var lightHoldDistance = 18.0
    public var redLightPenalty = 3.0

    public var dodgeWindow = 0.6               // seconds to impact
    public var nearMissLateralGap = 0.1        // lanes
    public var comboWindow = 3.0
    public var maxComboMultiplier = 5

    public var lightCycle: Double { lightGreen + lightYellow + lightRed }

    public init() {}

    public static let standard = GameTuning()
}

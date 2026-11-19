import Foundation

/// Outcome of one finished run.
public struct RunResult: Codable, Equatable, Sendable {
    public var levelID: LevelID
    public var city: CityID
    public var isDaily: Bool
    public var finished: Bool
    /// Ride time plus penalties, in seconds.
    public var time: Double
    public var parTime: Double
    public var coins: Int
    public var coinsForStar: Int
    public var nearMisses: Int
    public var maxCombo: Int
    public var comboPoints: Int
    public var potholeHits: Int
    public var redLightsRun: Int
    public var distance: Double
    public var assisted: Bool
    /// Attempts (crashes) before this finish, within the same session.
    public var crashesBeforeFinish: Int
    public var drafts: Int

    public init(levelID: LevelID, city: CityID, isDaily: Bool, finished: Bool, time: Double, parTime: Double,
                coins: Int, coinsForStar: Int, nearMisses: Int, maxCombo: Int, comboPoints: Int,
                potholeHits: Int, redLightsRun: Int, distance: Double, assisted: Bool, crashesBeforeFinish: Int, drafts: Int = 0) {
        self.levelID = levelID
        self.city = city
        self.isDaily = isDaily
        self.finished = finished
        self.time = time
        self.parTime = parTime
        self.coins = coins
        self.coinsForStar = coinsForStar
        self.nearMisses = nearMisses
        self.maxCombo = maxCombo
        self.comboPoints = comboPoints
        self.potholeHits = potholeHits
        self.redLightsRun = redLightsRun
        self.distance = distance
        self.assisted = assisted
        self.crashesBeforeFinish = crashesBeforeFinish
        self.drafts = drafts
    }

    public var isClean: Bool { potholeHits == 0 && redLightsRun == 0 }
    public var stars: Int { StarRating.stars(for: self) }
    public var score: Int { ScoreRules.score(for: self) }
    public var breakdown: ScoreBreakdown { ScoreRules.breakdown(for: self) }
}

public struct ScoreBreakdown: Equatable, Sendable {
    public var coinPoints: Int
    public var comboPoints: Int
    public var timeBonus: Int
    public var cleanBonus: Int
    public var total: Int { coinPoints + comboPoints + timeBonus + cleanBonus }
}

public enum ScoreRules {
    public static let pointsPerCoin = 10
    public static let pointsPerNearMiss = 25
    public static let timeBonusPerSecond = 20.0
    public static let timeBonusWindow = 1.3
    public static let cleanBonus = 250
    public static let coinStarFraction = 0.7
    public static let assistParMultiplier = 1.15

    /// Points for a near miss at the given combo count (1-based), capped.
    public static func nearMissPoints(combo: Int, cap: Int = GameTuning.standard.maxComboMultiplier) -> Int {
        pointsPerNearMiss * min(max(combo, 1), cap)
    }

    public static func breakdown(for result: RunResult) -> ScoreBreakdown {
        guard result.finished else {
            return ScoreBreakdown(coinPoints: 0, comboPoints: 0, timeBonus: 0, cleanBonus: 0)
        }
        let window = result.parTime * timeBonusWindow - result.time
        let timeBonus = window > 0 ? Int((window * timeBonusPerSecond).rounded(.down)) : 0
        return ScoreBreakdown(
            coinPoints: result.coins * pointsPerCoin,
            comboPoints: result.comboPoints,
            timeBonus: timeBonus,
            cleanBonus: result.isClean ? cleanBonus : 0
        )
    }

    public static func score(for result: RunResult) -> Int { breakdown(for: result).total }
}

/// 1 star: reach the finish line.
/// 2nd star: finish within par time (penalties included).
/// 3rd star: collect at least 70% of the coins with a clean ride
///           (no pothole hits, no red lights run).
public enum StarRating {
    public static func stars(for result: RunResult) -> Int {
        guard result.finished else { return 0 }
        var stars = 1
        if result.time <= result.parTime { stars += 1 }
        if result.coins >= result.coinsForStar && result.isClean { stars += 1 }
        return stars
    }
}

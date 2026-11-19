import Foundation

public struct LevelRecord: Codable, Equatable, Sendable {
    public var bestStars: Int
    public var bestTime: Double?
    public var bestScore: Int
    public var completions: Int

    public init(bestStars: Int = 0, bestTime: Double? = nil, bestScore: Int = 0, completions: Int = 0) {
        self.bestStars = bestStars
        self.bestTime = bestTime
        self.bestScore = bestScore
        self.completions = completions
    }

    public var isCompleted: Bool { completions > 0 }

    /// Field-wise best of two records (used for cloud merges).
    public static func best(_ a: LevelRecord, _ b: LevelRecord) -> LevelRecord {
        let time: Double?
        switch (a.bestTime, b.bestTime) {
        case let (x?, y?): time = min(x, y)
        case let (x?, nil): time = x
        case let (nil, y?): time = y
        case (nil, nil): time = nil
        }
        return LevelRecord(bestStars: max(a.bestStars, b.bestStars), bestTime: time,
                           bestScore: max(a.bestScore, b.bestScore), completions: max(a.completions, b.completions))
    }
}

public struct PlayerStats: Codable, Equatable, Sendable {
    public var runs = 0
    public var finishes = 0
    public var crashes = 0
    public var nearMisses = 0
    public var lifetimeCoins = 0
    public var distanceMeters: Double = 0
    public var bestCombo = 0
    public var drafts = 0
    public var dailyCompleted = 0
    public var cleanFinishes = 0

    public init() {}

    public static func max(_ a: PlayerStats, _ b: PlayerStats) -> PlayerStats {
        var s = PlayerStats()
        s.runs = Swift.max(a.runs, b.runs)
        s.finishes = Swift.max(a.finishes, b.finishes)
        s.crashes = Swift.max(a.crashes, b.crashes)
        s.nearMisses = Swift.max(a.nearMisses, b.nearMisses)
        s.lifetimeCoins = Swift.max(a.lifetimeCoins, b.lifetimeCoins)
        s.distanceMeters = Swift.max(a.distanceMeters, b.distanceMeters)
        s.bestCombo = Swift.max(a.bestCombo, b.bestCombo)
        s.drafts = Swift.max(a.drafts, b.drafts)
        s.dailyCompleted = Swift.max(a.dailyCompleted, b.dailyCompleted)
        s.cleanFinishes = Swift.max(a.cleanFinishes, b.cleanFinishes)
        return s
    }
}

public struct Loadout: Codable, Equatable, Sendable {
    public var bike: String
    public var jersey: String
    public var helmet: String

    public init(bike: String = CosmeticCatalog.defaultBike, jersey: String = CosmeticCatalog.defaultJersey,
                helmet: String = CosmeticCatalog.defaultHelmet) {
        self.bike = bike
        self.jersey = jersey
        self.helmet = helmet
    }

    public func id(for slot: CosmeticSlot) -> String {
        switch slot {
        case .bike: return bike
        case .jersey: return jersey
        case .helmet: return helmet
        }
    }

    var sortKey: String { "\(bike)|\(jersey)|\(helmet)" }

    public mutating func set(_ id: String, for slot: CosmeticSlot) {
        switch slot {
        case .bike: bike = id
        case .jersey: jersey = id
        case .helmet: helmet = id
        }
    }
}

/// Everything the player has earned. Stored locally as JSON and optionally
/// mirrored to the user's CloudKit private database.
public struct PlayerProgress: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var levels: [String: LevelRecord]
    /// Daily challenge bests keyed by "yyyymmdd".
    public var daily: [String: LevelRecord]
    public var stats: PlayerStats
    public var loadout: Loadout
    public var loadoutModifiedAt: Date
    public var modifiedAt: Date

    public init(now: Date = Date(timeIntervalSince1970: 0)) {
        version = PlayerProgress.currentVersion
        levels = [:]
        daily = [:]
        stats = PlayerStats()
        loadout = Loadout()
        loadoutModifiedAt = now
        modifiedAt = now
    }

    public func record(for id: LevelID) -> LevelRecord? { levels[id.rawValue] }

    public func stars(for id: LevelID) -> Int { levels[id.rawValue]?.bestStars ?? 0 }

    public var totalStars: Int {
        CityID.allCases.reduce(0) { $0 + stars(in: $1) }
    }

    public func stars(in city: CityID) -> Int {
        (0..<LevelGenerator.levelsPerCity).reduce(0) { $0 + stars(for: .city(city, index: $1)) }
    }

    public func completedLevels(in city: CityID) -> Int {
        (0..<LevelGenerator.levelsPerCity).reduce(0) {
            $0 + ((levels[LevelID.city(city, index: $1).rawValue]?.isCompleted ?? false) ? 1 : 0)
        }
    }

    /// Leaderboard value for a city: sum of best scores over its levels.
    public func cityScore(_ city: CityID) -> Int {
        (0..<LevelGenerator.levelsPerCity).reduce(0) {
            $0 + (levels[LevelID.city(city, index: $1).rawValue]?.bestScore ?? 0)
        }
    }

    public var maxPossibleStars: Int { CityID.allCases.count * LevelGenerator.levelsPerCity * 3 }
}

/// What changed after recording a run, for the results screen.
public struct RecordOutcome: Equatable, Sendable {
    public var stars: Int
    public var score: Int
    public var previousBestStars: Int
    public var isNewBestScore: Bool
    public var isNewBestTime: Bool
    public var newlyUnlockedCities: [CityID]
    public var newlyUnlockedCosmetics: [String]
    public var newlyEarnedAchievements: [String]

    public init(stars: Int, score: Int, previousBestStars: Int, isNewBestScore: Bool, isNewBestTime: Bool,
                newlyUnlockedCities: [CityID], newlyUnlockedCosmetics: [String], newlyEarnedAchievements: [String]) {
        self.stars = stars
        self.score = score
        self.previousBestStars = previousBestStars
        self.isNewBestScore = isNewBestScore
        self.isNewBestTime = isNewBestTime
        self.newlyUnlockedCities = newlyUnlockedCities
        self.newlyUnlockedCosmetics = newlyUnlockedCosmetics
        self.newlyEarnedAchievements = newlyEarnedAchievements
    }
}

extension PlayerProgress {
    /// Applies a finished run. Unfinished runs should use `recordCrash`.
    @discardableResult
    public mutating func record(_ result: RunResult, isSupporter: Bool = false, now: Date = Date()) -> RecordOutcome {
        let citiesBefore = Set(CityID.allCases.filter { ProgressionRules.isCityUnlocked($0, in: self) })
        let cosmeticsBefore = Set(CosmeticCatalog.unlockedIDs(in: self, isSupporter: isSupporter))
        let achievementsBefore = Set(AchievementCatalog.earnedIDs(in: self))

        let stars = result.stars
        let score = result.score
        let key = result.levelID.rawValue
        let isDailyRun = result.isDaily
        let old = (isDailyRun ? daily[dailyKey(result.levelID)] : levels[key]) ?? LevelRecord()

        stats.runs += 1
        stats.distanceMeters += result.distance
        stats.nearMisses += result.nearMisses
        stats.bestCombo = max(stats.bestCombo, result.maxCombo)
        stats.drafts += result.drafts

        var updated = old
        if result.finished {
            stats.finishes += 1
            stats.lifetimeCoins += result.coins
            if result.isClean { stats.cleanFinishes += 1 }
            if isDailyRun && !old.isCompleted { stats.dailyCompleted += 1 }
            updated.completions += 1
            updated.bestStars = max(old.bestStars, stars)
            updated.bestScore = max(old.bestScore, score)
            updated.bestTime = old.bestTime.map { min($0, result.time) } ?? result.time
        }
        if isDailyRun {
            daily[dailyKey(result.levelID)] = updated
        } else {
            levels[key] = updated
        }
        modifiedAt = now

        let citiesAfter = CityID.allCases.filter { ProgressionRules.isCityUnlocked($0, in: self) && !citiesBefore.contains($0) }
        let cosmeticsAfter = CosmeticCatalog.unlockedIDs(in: self, isSupporter: isSupporter).filter { !cosmeticsBefore.contains($0) }
        let achievementsAfter = AchievementCatalog.earnedIDs(in: self).filter { !achievementsBefore.contains($0) }

        return RecordOutcome(
            stars: stars, score: score, previousBestStars: old.bestStars,
            isNewBestScore: result.finished && score > old.bestScore,
            isNewBestTime: result.finished && (old.bestTime.map { result.time < $0 } ?? true),
            newlyUnlockedCities: citiesAfter,
            newlyUnlockedCosmetics: cosmeticsAfter,
            newlyEarnedAchievements: achievementsAfter
        )
    }

    /// Counts a crash (instant restart). Cheap: no unlock evaluation.
    public mutating func recordCrash(distance: Double, nearMisses: Int, drafts: Int = 0, now: Date = Date()) {
        stats.runs += 1
        stats.crashes += 1
        stats.distanceMeters += distance
        stats.nearMisses += nearMisses
        stats.drafts += drafts
        modifiedAt = now
    }

    public mutating func equip(_ item: CosmeticItem, isSupporter: Bool, now: Date = Date()) -> Bool {
        guard CosmeticCatalog.isUnlocked(item, in: self, isSupporter: isSupporter) else { return false }
        loadout.set(item.id, for: item.slot)
        loadoutModifiedAt = now
        modifiedAt = now
        return true
    }

    private func dailyKey(_ id: LevelID) -> String {
        id.rawValue.replacingOccurrences(of: "daily-", with: "")
    }

    public func dailyRecord(dayKey: Int) -> LevelRecord? { daily[String(dayKey)] }
}

public enum ProgressMerge {
    /// Conflict-free merge: every field keeps the best value from either
    /// side, so merging never loses earned progress and is idempotent,
    /// commutative and associative.
    public static func merge(_ a: PlayerProgress, _ b: PlayerProgress) -> PlayerProgress {
        var out = PlayerProgress()
        out.version = max(a.version, b.version)
        out.levels = a.levels.merging(b.levels) { LevelRecord.best($0, $1) }
        out.daily = a.daily.merging(b.daily) { LevelRecord.best($0, $1) }
        out.stats = PlayerStats.max(a.stats, b.stats)
        if a.loadoutModifiedAt > b.loadoutModifiedAt
            || (a.loadoutModifiedAt == b.loadoutModifiedAt && a.loadout.sortKey <= b.loadout.sortKey) {
            out.loadout = a.loadout
            out.loadoutModifiedAt = a.loadoutModifiedAt
        } else {
            out.loadout = b.loadout
            out.loadoutModifiedAt = b.loadoutModifiedAt
        }
        out.modifiedAt = max(a.modifiedAt, b.modifiedAt)
        return out
    }
}

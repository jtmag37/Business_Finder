import Foundation

public enum ProgressionRules {
    public static func starsRequired(for city: CityID) -> Int {
        CityCatalog.definition(for: city).starsToUnlock
    }

    public static func isCityUnlocked(_ city: CityID, in progress: PlayerProgress) -> Bool {
        progress.totalStars >= starsRequired(for: city)
    }

    /// The first level of an unlocked city is open; each further level opens
    /// once the previous one has been finished.
    public static func isLevelUnlocked(city: CityID, index: Int, in progress: PlayerProgress) -> Bool {
        guard isCityUnlocked(city, in: progress), (0..<LevelGenerator.levelsPerCity).contains(index) else {
            return false
        }
        if index == 0 { return true }
        return progress.record(for: .city(city, index: index - 1))?.isCompleted ?? false
    }

    public static func nextLockedCity(in progress: PlayerProgress) -> CityID? {
        CityID.allCases.first { !isCityUnlocked($0, in: progress) }
    }

    public static func starsStillNeeded(for city: CityID, in progress: PlayerProgress) -> Int {
        max(0, starsRequired(for: city) - progress.totalStars)
    }

    /// The level after `id` in the same city, if there is one and it is open.
    public static func nextLevel(after id: LevelID, in progress: PlayerProgress) -> (CityID, Int)? {
        for city in CityID.allCases {
            for index in 0..<LevelGenerator.levelsPerCity where LevelID.city(city, index: index) == id {
                let next = index + 1
                guard next < LevelGenerator.levelsPerCity,
                      isLevelUnlocked(city: city, index: next, in: progress) else { return nil }
                return (city, next)
            }
        }
        return nil
    }
}

// MARK: - Cosmetics

public enum CosmeticSlot: String, Codable, Sendable, CaseIterable {
    case bike
    case jersey
    case helmet
}

public enum UnlockRequirement: Equatable, Sendable {
    case free
    case totalStars(Int)
    case cityCompleted(CityID)
    case nearMisses(Int)
    case lifetimeCoins(Int)
    case dailyChallenges(Int)
    case cleanFinishes(Int)
    case drafts(Int)
    /// Optional one-time "Supporter Pack" purchase. Cosmetic only.
    case supporter

    /// 0...1 progress towards the requirement.
    public func progress(in p: PlayerProgress, isSupporter: Bool) -> Double {
        func ratio(_ value: Int, _ target: Int) -> Double { target <= 0 ? 1 : min(1, Double(value) / Double(target)) }
        switch self {
        case .free: return 1
        case .totalStars(let n): return ratio(p.totalStars, n)
        case .cityCompleted(let c): return ratio(p.completedLevels(in: c), LevelGenerator.levelsPerCity)
        case .nearMisses(let n): return ratio(p.stats.nearMisses, n)
        case .lifetimeCoins(let n): return ratio(p.stats.lifetimeCoins, n)
        case .dailyChallenges(let n): return ratio(p.stats.dailyCompleted, n)
        case .cleanFinishes(let n): return ratio(p.stats.cleanFinishes, n)
        case .drafts(let n): return ratio(p.stats.drafts, n)
        case .supporter: return isSupporter ? 1 : 0
        }
    }

    public func isMet(in p: PlayerProgress, isSupporter: Bool) -> Bool {
        progress(in: p, isSupporter: isSupporter) >= 1
    }
}

public struct CosmeticItem: Identifiable, Equatable, Sendable {
    public var id: String
    public var slot: CosmeticSlot
    public var primary: RGB
    public var secondary: RGB
    public var requirement: UnlockRequirement
}

public enum CosmeticCatalog {
    public static let defaultBike = "bike.classic"
    public static let defaultJersey = "jersey.club"
    public static let defaultHelmet = "helmet.white"

    public static let all: [CosmeticItem] = [
        // Bikes
        CosmeticItem(id: "bike.classic", slot: .bike, primary: RGB(0xE63946), secondary: RGB(0xF1FAEE), requirement: .free),
        CosmeticItem(id: "bike.steel", slot: .bike, primary: RGB(0x6C757D), secondary: RGB(0xADB5BD), requirement: .totalStars(10)),
        CosmeticItem(id: "bike.mint", slot: .bike, primary: RGB(0x52B788), secondary: RGB(0xD8F3DC), requirement: .cityCompleted(.newYork)),
        CosmeticItem(id: "bike.carbon", slot: .bike, primary: RGB(0x212529), secondary: RGB(0xF4A261), requirement: .totalStars(60)),
        CosmeticItem(id: "bike.sunset", slot: .bike, primary: RGB(0xF77F00), secondary: RGB(0xFCBF49), requirement: .lifetimeCoins(1500)),
        CosmeticItem(id: "bike.aurora", slot: .bike, primary: RGB(0x7B2CBF), secondary: RGB(0x80FFDB), requirement: .totalStars(180)),
        CosmeticItem(id: "bike.gold", slot: .bike, primary: RGB(0xD4AF37), secondary: RGB(0xFFF3B0), requirement: .supporter),
        // Jerseys
        CosmeticItem(id: "jersey.club", slot: .jersey, primary: RGB(0x1D3557), secondary: RGB(0xA8DADC), requirement: .free),
        CosmeticItem(id: "jersey.sprinter", slot: .jersey, primary: RGB(0x2A9D8F), secondary: RGB(0xE9C46A), requirement: .nearMisses(50)),
        CosmeticItem(id: "jersey.climber", slot: .jersey, primary: RGB(0xF8F9FA), secondary: RGB(0xE63946), requirement: .cityCompleted(.paris)),
        CosmeticItem(id: "jersey.rain", slot: .jersey, primary: RGB(0x48CAE4), secondary: RGB(0x023E8A), requirement: .cityCompleted(.london)),
        CosmeticItem(id: "jersey.daily", slot: .jersey, primary: RGB(0xFFB703), secondary: RGB(0x023047), requirement: .dailyChallenges(7)),
        CosmeticItem(id: "jersey.clean", slot: .jersey, primary: RGB(0xFFFFFF), secondary: RGB(0x2D6A4F), requirement: .cleanFinishes(25)),
        CosmeticItem(id: "jersey.draft", slot: .jersey, primary: RGB(0x4361EE), secondary: RGB(0x4CC9F0), requirement: .drafts(40)),
        CosmeticItem(id: "jersey.world", slot: .jersey, primary: RGB(0x3A0CA3), secondary: RGB(0xF72585), requirement: .totalStars(240)),
        CosmeticItem(id: "jersey.supporter", slot: .jersey, primary: RGB(0x111111), secondary: RGB(0xD4AF37), requirement: .supporter),
        // Helmets
        CosmeticItem(id: "helmet.white", slot: .helmet, primary: RGB(0xF8F9FA), secondary: RGB(0x343A40), requirement: .free),
        CosmeticItem(id: "helmet.neon", slot: .helmet, primary: RGB(0xCCFF00), secondary: RGB(0x111111), requirement: .cityCompleted(.tokyo)),
        CosmeticItem(id: "helmet.canal", slot: .helmet, primary: RGB(0xFF7A00), secondary: RGB(0xFFFFFF), requirement: .cityCompleted(.amsterdam)),
        CosmeticItem(id: "helmet.tropic", slot: .helmet, primary: RGB(0x06D6A0), secondary: RGB(0xFFD166), requirement: .cityCompleted(.rioDeJaneiro)),
        CosmeticItem(id: "helmet.harbour", slot: .helmet, primary: RGB(0x118AB2), secondary: RGB(0xFFFFFF), requirement: .cityCompleted(.sydney)),
        CosmeticItem(id: "helmet.cape", slot: .helmet, primary: RGB(0x2D6A4F), secondary: RGB(0xFFD60A), requirement: .cityCompleted(.capeTown)),
        CosmeticItem(id: "helmet.supporter", slot: .helmet, primary: RGB(0xD4AF37), secondary: RGB(0x111111), requirement: .supporter),
    ]

    public static func item(id: String) -> CosmeticItem? { all.first { $0.id == id } }

    public static func items(for slot: CosmeticSlot) -> [CosmeticItem] { all.filter { $0.slot == slot } }

    public static func isUnlocked(_ item: CosmeticItem, in progress: PlayerProgress, isSupporter: Bool) -> Bool {
        item.requirement.isMet(in: progress, isSupporter: isSupporter)
    }

    public static func unlockedIDs(in progress: PlayerProgress, isSupporter: Bool) -> [String] {
        all.filter { isUnlocked($0, in: progress, isSupporter: isSupporter) }.map(\.id)
    }

    /// Equipped item for a slot, falling back to the default when the stored
    /// choice is unknown or no longer unlocked (e.g. a refunded purchase).
    public static func resolvedItem(for slot: CosmeticSlot, loadout: Loadout, progress: PlayerProgress,
                                    isSupporter: Bool) -> CosmeticItem {
        if let item = item(id: loadout.id(for: slot)), isUnlocked(item, in: progress, isSupporter: isSupporter) {
            return item
        }
        let fallback: String
        switch slot {
        case .bike: fallback = defaultBike
        case .jersey: fallback = defaultJersey
        case .helmet: fallback = defaultHelmet
        }
        return item(id: fallback)!
    }
}

// MARK: - Achievements

public struct Achievement: Identifiable, Equatable, Sendable {
    /// Must match the achievement ID configured in App Store Connect.
    public var id: String
    public var requirement: UnlockRequirement
}

public enum AchievementCatalog {
    public static let prefix = "citysprint.achievement."

    public static let all: [Achievement] = [
        Achievement(id: prefix + "first_finish", requirement: .totalStars(1)),
        Achievement(id: prefix + "stars_30", requirement: .totalStars(30)),
        Achievement(id: prefix + "stars_120", requirement: .totalStars(120)),
        Achievement(id: prefix + "stars_240", requirement: .totalStars(240)),
        Achievement(id: prefix + "near_miss_100", requirement: .nearMisses(100)),
        Achievement(id: prefix + "coins_5000", requirement: .lifetimeCoins(5000)),
        Achievement(id: prefix + "daily_7", requirement: .dailyChallenges(7)),
        Achievement(id: prefix + "draft_25", requirement: .drafts(25)),
        Achievement(id: prefix + "clean_10", requirement: .cleanFinishes(10)),
    ] + CityID.allCases.map {
        Achievement(id: prefix + "city_" + $0.rawValue.lowercased(), requirement: .cityCompleted($0))
    }

    public static func earnedIDs(in progress: PlayerProgress) -> [String] {
        all.filter { $0.requirement.isMet(in: progress, isSupporter: false) }.map(\.id)
    }

    /// Percent complete for each achievement (Game Center reporting).
    public static func percentages(in progress: PlayerProgress) -> [(id: String, percent: Double)] {
        all.map { (id: $0.id, percent: ($0.requirement.progress(in: progress, isSupporter: false) * 100).rounded()) }
    }
}

public enum LeaderboardIDs {
    public static let prefix = "citysprint.leaderboard."

    /// Sum of best scores over the city's ten levels.
    public static func city(_ city: CityID) -> String { prefix + "city_" + city.rawValue.lowercased() }

    /// Recurring (daily reset) leaderboard for the daily challenge.
    public static let daily = prefix + "daily"

    public static var all: [String] { CityID.allCases.map(city) + [daily] }
}

// MARK: - Daily challenge

public enum DailyChallenge {
    /// yyyymmdd in UTC so every player worldwide shares the same level.
    public static func dayKey(for date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 2000) * 10_000 + (c.month ?? 1) * 100 + (c.day ?? 1)
    }

    public static func level(for date: Date) -> LevelDefinition {
        LevelGenerator.daily(dayKey: dayKey(for: date))
    }

    /// Seconds until the next UTC midnight.
    public static func secondsUntilReset(from date: Date) -> TimeInterval {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return next.timeIntervalSince(date)
    }
}

// MARK: - Purchases

/// Framework-free snapshot of a StoreKit transaction so entitlement rules can
/// be unit-tested. The app builds these from `VerificationResult<Transaction>`.
public struct TransactionSnapshot: Equatable, Sendable {
    public var productID: String
    public var isVerified: Bool
    public var revocationDate: Date?
    public var expirationDate: Date?
    public var isUpgraded: Bool

    public init(productID: String, isVerified: Bool, revocationDate: Date? = nil,
                expirationDate: Date? = nil, isUpgraded: Bool = false) {
        self.productID = productID
        self.isVerified = isVerified
        self.revocationDate = revocationDate
        self.expirationDate = expirationDate
        self.isUpgraded = isUpgraded
    }
}

public enum EntitlementResolver {
    /// Only verified, unrevoked, unexpired, non-upgraded transactions for
    /// known products grant anything.
    public static func activeProducts(from transactions: [TransactionSnapshot], knownProducts: Set<String>,
                                      now: Date) -> Set<String> {
        var active = Set<String>()
        for t in transactions {
            guard t.isVerified, knownProducts.contains(t.productID), t.revocationDate == nil, !t.isUpgraded else {
                continue
            }
            if let expiry = t.expirationDate, expiry <= now { continue }
            active.insert(t.productID)
        }
        return active
    }
}

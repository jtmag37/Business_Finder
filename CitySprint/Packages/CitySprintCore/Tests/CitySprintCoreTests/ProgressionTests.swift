import XCTest
@testable import CitySprintCore

final class ScoringTests: XCTestCase {
    func testStarRules() {
        XCTAssertEqual(makeResult(finished: false).stars, 0)
        XCTAssertEqual(makeResult(time: 70, par: 60, coins: 0).stars, 1)
        XCTAssertEqual(makeResult(time: 55, par: 60, coins: 0).stars, 2)
        XCTAssertEqual(makeResult(time: 70, par: 60, coins: 7).stars, 2)
        XCTAssertEqual(makeResult(time: 55, par: 60, coins: 7).stars, 3)
        XCTAssertEqual(makeResult(time: 55, par: 60, coins: 7, potholes: 1).stars, 2, "pothole breaks clean ride")
        XCTAssertEqual(makeResult(time: 55, par: 60, coins: 7, reds: 1).stars, 2, "red light breaks clean ride")
        XCTAssertEqual(makeResult(time: 60, par: 60, coins: 0).stars, 2, "par is inclusive")
    }

    func testScoreBreakdown() {
        let result = makeResult(time: 70, par: 60, coins: 12, comboPoints: 75)
        let b = result.breakdown
        XCTAssertEqual(b.coinPoints, 120)
        XCTAssertEqual(b.comboPoints, 75)
        XCTAssertEqual(b.timeBonus, Int((60 * 1.3 - 70) * 20))
        XCTAssertEqual(b.cleanBonus, ScoreRules.cleanBonus)
        XCTAssertEqual(result.score, b.total)
        XCTAssertEqual(makeResult(finished: false, coins: 50).score, 0)
        XCTAssertEqual(makeResult(time: 200, par: 60, coins: 0, reds: 1).score, 0)
    }

    func testNearMissPointsAreCapped() {
        XCTAssertEqual(ScoreRules.nearMissPoints(combo: 1), 25)
        XCTAssertEqual(ScoreRules.nearMissPoints(combo: 3), 75)
        XCTAssertEqual(ScoreRules.nearMissPoints(combo: 50), 125)
    }

    func testCoinStarThresholdRoundsUp() {
        let level = TestLevels.make((0..<10).map { LevelEntity(kind: .coin, lane: 1, y: Double($0) * 3 + 10) })
        XCTAssertEqual(level.coinsRequiredForStar(assist: false), 7)
        XCTAssertEqual(level.parTime(assist: true), (30 * ScoreRules.assistParMultiplier).rounded())
    }
}

final class ProgressionTests: XCTestCase {
    private func progressWithStars(_ stars: Int) -> PlayerProgress {
        var p = PlayerProgress()
        var remaining = stars
        outer: for city in CityID.allCases {
            for index in 0..<LevelGenerator.levelsPerCity {
                guard remaining > 0 else { break outer }
                let s = min(3, remaining)
                p.levels[LevelID.city(city, index: index).rawValue] = LevelRecord(bestStars: s, bestTime: 60,
                                                                                    bestScore: 100, completions: 1)
                remaining -= s
            }
        }
        return p
    }

    func testNewYorkIsUnlockedFromTheStart() {
        let p = PlayerProgress()
        XCTAssertTrue(ProgressionRules.isCityUnlocked(.newYork, in: p))
        XCTAssertFalse(ProgressionRules.isCityUnlocked(.paris, in: p))
        XCTAssertEqual(ProgressionRules.nextLockedCity(in: p), .paris)
        XCTAssertEqual(ProgressionRules.starsStillNeeded(for: .paris, in: p), 8)
    }

    func testCityUnlockThresholdsIncrease() {
        let thresholds = CityID.allCases.map(ProgressionRules.starsRequired(for:))
        XCTAssertEqual(thresholds, thresholds.sorted())
        XCTAssertEqual(Set(thresholds).count, thresholds.count)
        XCTAssertLessThanOrEqual(thresholds.last!, 240 - 30, "last city must be reachable without perfecting all others")
    }

    func testCitiesUnlockWithStars() {
        XCTAssertTrue(ProgressionRules.isCityUnlocked(.paris, in: progressWithStars(8)))
        XCTAssertFalse(ProgressionRules.isCityUnlocked(.tokyo, in: progressWithStars(17)))
        XCTAssertTrue(ProgressionRules.isCityUnlocked(.capeTown, in: progressWithStars(82)))
    }

    func testLevelsUnlockSequentially() {
        var p = PlayerProgress()
        XCTAssertTrue(ProgressionRules.isLevelUnlocked(city: .newYork, index: 0, in: p))
        XCTAssertFalse(ProgressionRules.isLevelUnlocked(city: .newYork, index: 1, in: p))
        p.record(makeResult())
        XCTAssertTrue(ProgressionRules.isLevelUnlocked(city: .newYork, index: 1, in: p))
        XCTAssertFalse(ProgressionRules.isLevelUnlocked(city: .newYork, index: 2, in: p))
        XCTAssertFalse(ProgressionRules.isLevelUnlocked(city: .paris, index: 0, in: p))
        XCTAssertFalse(ProgressionRules.isLevelUnlocked(city: .newYork, index: 10, in: p))
        XCTAssertEqual(ProgressionRules.nextLevel(after: .city(.newYork, index: 0), in: p)?.1, 1)
        XCTAssertNil(ProgressionRules.nextLevel(after: .city(.newYork, index: 1), in: p))
    }

    func testRecordKeepsBestValues() {
        var p = PlayerProgress()
        let first = p.record(makeResult(time: 55, par: 60, coins: 7))
        XCTAssertEqual(first.stars, 3)
        XCTAssertTrue(first.isNewBestScore)
        XCTAssertTrue(first.isNewBestTime)
        let worse = p.record(makeResult(time: 80, par: 60, coins: 0))
        XCTAssertFalse(worse.isNewBestScore)
        XCTAssertFalse(worse.isNewBestTime)
        XCTAssertEqual(worse.previousBestStars, 3)
        let record = p.record(for: .city(.newYork, index: 0))!
        XCTAssertEqual(record.bestStars, 3)
        XCTAssertEqual(record.bestTime, 55)
        XCTAssertEqual(record.completions, 2)
        XCTAssertEqual(p.stats.finishes, 2)
        XCTAssertEqual(p.stats.lifetimeCoins, 7)
    }

    func testUnfinishedRunDoesNotComplete() {
        var p = PlayerProgress()
        p.record(makeResult(finished: false))
        XCTAssertFalse(p.record(for: .city(.newYork, index: 0))?.isCompleted ?? true)
        XCTAssertEqual(p.totalStars, 0)
    }

    func testRecordReportsNewlyUnlockedCity() {
        var p = progressWithStars(6)
        let outcome = p.record(makeResult(time: 50, par: 60, coins: 7, level: .city(.newYork, index: 5)))
        XCTAssertEqual(p.totalStars, 9)
        XCTAssertEqual(outcome.newlyUnlockedCities, [.paris])
    }

    func testDailyResultsAreStoredSeparately() {
        var p = PlayerProgress()
        p.record(makeResult(level: .daily(dayKey: 20_261_119), daily: true))
        XCTAssertEqual(p.totalStars, 0)
        XCTAssertEqual(p.dailyRecord(dayKey: 20_261_119)?.completions, 1)
        XCTAssertEqual(p.stats.dailyCompleted, 1)
        p.record(makeResult(level: .daily(dayKey: 20_261_119), daily: true))
        XCTAssertEqual(p.stats.dailyCompleted, 1, "replaying the same day does not count twice")
    }

    func testCrashStats() {
        var p = PlayerProgress()
        p.recordCrash(distance: 120, nearMisses: 2, drafts: 1)
        XCTAssertEqual(p.stats.crashes, 1)
        XCTAssertEqual(p.stats.runs, 1)
        XCTAssertEqual(p.stats.nearMisses, 2)
        XCTAssertEqual(p.stats.drafts, 1)
        XCTAssertEqual(p.stats.distanceMeters, 120)
    }

    func testCosmeticsUnlockThroughPlay() {
        var p = PlayerProgress()
        let steel = CosmeticCatalog.item(id: "bike.steel")!
        XCTAssertFalse(CosmeticCatalog.isUnlocked(steel, in: p, isSupporter: false))
        XCTAssertFalse(p.equip(steel, isSupporter: false))
        p = progressWithStars(10)
        XCTAssertTrue(CosmeticCatalog.isUnlocked(steel, in: p, isSupporter: false))
        XCTAssertTrue(p.equip(steel, isSupporter: false))
        XCTAssertEqual(p.loadout.bike, "bike.steel")
    }

    func testSupporterItemsRequireEntitlement() {
        var p = PlayerProgress()
        let gold = CosmeticCatalog.item(id: "bike.gold")!
        XCTAssertFalse(CosmeticCatalog.isUnlocked(gold, in: p, isSupporter: false))
        XCTAssertTrue(p.equip(gold, isSupporter: true))
        // After a refund the equipped item falls back to the default.
        let resolved = CosmeticCatalog.resolvedItem(for: .bike, loadout: p.loadout, progress: p, isSupporter: false)
        XCTAssertEqual(resolved.id, CosmeticCatalog.defaultBike)
    }

    func testCosmeticCatalogIsConsistent() {
        let ids = CosmeticCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        for slot in CosmeticSlot.allCases {
            XCTAssertGreaterThanOrEqual(CosmeticCatalog.items(for: slot).count, 6)
        }
        let defaults = [CosmeticCatalog.defaultBike, CosmeticCatalog.defaultJersey, CosmeticCatalog.defaultHelmet]
        for id in defaults { XCTAssertEqual(CosmeticCatalog.item(id: id)?.requirement, .free) }
    }

    func testAchievementsAndLeaderboardIDsAreUnique() {
        let ids = AchievementCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(Set(LeaderboardIDs.all).count, CityID.allCases.count + 1)
        for id in ids + LeaderboardIDs.all {
            XCTAssertLessThanOrEqual(id.count, 100)
            XCTAssertTrue(id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_") }, id)
        }
    }

    func testAchievementPercentages() {
        var p = PlayerProgress()
        p.stats.nearMisses = 50
        let entry = AchievementCatalog.percentages(in: p).first { $0.id.hasSuffix("near_miss_100") }
        XCTAssertEqual(entry?.percent, 50)
    }

    func testCityScoreSumsBestScores() {
        let p = progressWithStars(9)
        XCTAssertEqual(p.cityScore(.newYork), 300)
    }

    // MARK: Merge

    func testMergeKeepsBestOfBoth() {
        var a = PlayerProgress()
        a.levels["nyc-01"] = LevelRecord(bestStars: 2, bestTime: 50, bestScore: 300, completions: 3)
        a.stats.nearMisses = 10
        a.loadout.bike = "bike.steel"
        a.loadoutModifiedAt = Date(timeIntervalSince1970: 100)
        var b = PlayerProgress()
        b.levels["nyc-01"] = LevelRecord(bestStars: 3, bestTime: 58, bestScore: 250, completions: 1)
        b.levels["nyc-02"] = LevelRecord(bestStars: 1, bestTime: 70, bestScore: 90, completions: 1)
        b.stats.nearMisses = 4
        b.loadout.bike = "bike.mint"
        b.loadoutModifiedAt = Date(timeIntervalSince1970: 200)

        let m = ProgressMerge.merge(a, b)
        XCTAssertEqual(m.levels["nyc-01"], LevelRecord(bestStars: 3, bestTime: 50, bestScore: 300, completions: 3))
        XCTAssertEqual(m.levels["nyc-02"]?.bestStars, 1)
        XCTAssertEqual(m.stats.nearMisses, 10)
        XCTAssertEqual(m.loadout.bike, "bike.mint", "newer loadout wins")
    }

    func testMergeIsCommutativeAndIdempotent() {
        var a = progressWithStars(20)
        a.stats.lifetimeCoins = 500
        a.loadout.jersey = "jersey.rain"
        var b = progressWithStars(35)
        b.levels["par-01"] = LevelRecord(bestStars: 1, bestTime: 90, bestScore: 10, completions: 1)
        b.daily["20261119"] = LevelRecord(bestStars: 2, bestTime: 80, bestScore: 400, completions: 1)
        b.loadout.jersey = "jersey.club"
        XCTAssertEqual(ProgressMerge.merge(a, b), ProgressMerge.merge(b, a))
        let m = ProgressMerge.merge(a, b)
        XCTAssertEqual(ProgressMerge.merge(m, m), m)
        XCTAssertEqual(ProgressMerge.merge(m, a), m)
    }

    // MARK: Purchases

    func testEntitlementsOnlyFromVerifiedTransactions() {
        let known: Set<String> = ["supporter"]
        let now = Date()
        XCTAssertEqual(EntitlementResolver.activeProducts(
            from: [TransactionSnapshot(productID: "supporter", isVerified: true)], knownProducts: known, now: now),
            ["supporter"])
        XCTAssertTrue(EntitlementResolver.activeProducts(
            from: [TransactionSnapshot(productID: "supporter", isVerified: false)], knownProducts: known, now: now).isEmpty)
        XCTAssertTrue(EntitlementResolver.activeProducts(
            from: [TransactionSnapshot(productID: "supporter", isVerified: true, revocationDate: now)],
            knownProducts: known, now: now).isEmpty)
        XCTAssertTrue(EntitlementResolver.activeProducts(
            from: [TransactionSnapshot(productID: "other", isVerified: true)], knownProducts: known, now: now).isEmpty)
        XCTAssertTrue(EntitlementResolver.activeProducts(
            from: [TransactionSnapshot(productID: "supporter", isVerified: true, expirationDate: now.addingTimeInterval(-1))],
            knownProducts: known, now: now).isEmpty)
    }
}

final class PersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testFileStoreRoundTrip() throws {
        let store = FileProgressStore(url: dir.appendingPathComponent("progress.json"))
        XCTAssertNil(try store.load())
        var p = PlayerProgress(now: Date(timeIntervalSince1970: 1_700_000_000))
        p.record(makeResult(), now: Date(timeIntervalSince1970: 1_700_000_100))
        try store.save(p)
        XCTAssertEqual(try store.load(), p)
        try store.reset()
        XCTAssertNil(try store.load())
    }

    func testCorruptFileFallsBackToBackup() throws {
        let url = dir.appendingPathComponent("progress.json")
        let store = FileProgressStore(url: url)
        var p = PlayerProgress(now: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(p)
        p.stats.runs = 5
        try store.save(p) // previous copy becomes the backup
        try Data("{not json".utf8).write(to: url)
        let loaded = try store.load()
        XCTAssertEqual(loaded?.stats.runs, 0, "should recover the backup copy")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.contains("corrupt") })
    }

    func testCorruptFileWithoutBackupStartsFresh() throws {
        let url = dir.appendingPathComponent("progress.json")
        try Data([0xFF, 0x00, 0x12]).write(to: url)
        XCTAssertNil(try FileProgressStore(url: url).load())
    }

    func testDecodeRejectsTamperedOrFutureData() throws {
        var p = PlayerProgress()
        p.levels["nyc-01"] = LevelRecord(bestStars: 9, bestTime: 1, bestScore: 1, completions: 1)
        XCTAssertThrowsError(try ProgressCoding.decode(ProgressCoding.encode(p)))

        var future = PlayerProgress()
        future.version = PlayerProgress.currentVersion + 1
        XCTAssertThrowsError(try ProgressCoding.decode(ProgressCoding.encode(future)))

        XCTAssertThrowsError(try ProgressCoding.decode(Data(count: 3_000_000)))
    }

    func testInMemoryStore() throws {
        let store = InMemoryProgressStore()
        XCTAssertNil(try store.load())
        try store.save(PlayerProgress())
        XCTAssertNotNil(try store.load())
    }
}

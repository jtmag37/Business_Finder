import SpriteKit
import XCTest
import CitySprintCore
@testable import CitySprint

@MainActor
final class AppModelTests: XCTestCase {
    private func makeModel(_ progress: PlayerProgress? = nil) -> (AppModel, InMemoryProgressStore) {
        let store = InMemoryProgressStore(progress)
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let model = AppModel(progressStore: store, settingsStore: SettingsStore(defaults: defaults))
        return (model, store)
    }

    func testLockedLevelsCannotBeLaunched() {
        let (model, _) = makeModel()
        model.play(city: .paris, index: 0)
        XCTAssertNil(model.activeGame)
        model.play(city: .newYork, index: 1)
        XCTAssertNil(model.activeGame)
        model.play(city: .newYork, index: 0)
        XCTAssertEqual(model.activeGame?.level.id, .city(.newYork, index: 0))
    }

    func testRecordingPersistsProgress() throws {
        let (model, store) = makeModel()
        let result = RunResult(levelID: .city(.newYork, index: 0), city: .newYork, isDaily: false, finished: true,
                               time: 40, parTime: 60, coins: 20, coinsForStar: 14, nearMisses: 3, maxCombo: 2,
                               comboPoints: 75, potholeHits: 0, redLightsRun: 0, distance: 600, assisted: false,
                               crashesBeforeFinish: 1)
        let outcome = model.record(result)
        XCTAssertEqual(outcome.stars, 3)
        XCTAssertEqual(model.progress.totalStars, 3)
        XCTAssertEqual(try store.load()?.totalStars, 3)
        XCTAssertTrue(model.isLevelUnlocked(.newYork, 1))
    }

    func testEquipRequiresUnlock() {
        let (model, _) = makeModel()
        let carbon = CosmeticCatalog.item(id: "bike.carbon")!
        XCTAssertFalse(model.equip(carbon))
        XCTAssertEqual(model.item(for: .bike).id, CosmeticCatalog.defaultBike)
    }

    func testResetProgress() {
        var seeded = PlayerProgress()
        seeded.levels["nyc-01"] = LevelRecord(bestStars: 3, bestTime: 50, bestScore: 900, completions: 1)
        let (model, _) = makeModel(seeded)
        XCTAssertEqual(model.progress.totalStars, 3)
        model.resetProgress()
        XCTAssertEqual(model.progress.totalStars, 0)
    }

    func testSettingsPersistAndTolerateOldPayloads() throws {
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let store = SettingsStore(defaults: defaults)
        var s = GameSettings()
        s.assistMode = true
        s.colorblindSignals = true
        store.save(s)
        XCTAssertEqual(store.load(), s)

        let legacy = try JSONDecoder().decode(GameSettings.self, from: Data(#"{"assistMode":true}"#.utf8))
        XCTAssertTrue(legacy.assistMode)
        XCTAssertTrue(legacy.haptics, "missing keys fall back to defaults")
    }

    func testColorblindSettingSwitchesPalette() {
        let (model, _) = makeModel()
        XCTAssertEqual(model.signalPalette.hazard, SignalPalette.standard.hazard)
        model.settings.colorblindSignals = true
        XCTAssertEqual(model.signalPalette.hazard, SignalPalette.colorblindSafe.hazard)
    }
}

final class KeychainTests: XCTestCase {
    func testRoundTripAndRemove() throws {
        let keychain = KeychainStore(service: "citysprint.tests.\(UUID().uuidString)")
        let account = "probe"
        defer { try? keychain.remove(account) }
        do {
            _ = try keychain.data(for: account)
        } catch KeychainStore.KeychainError.unexpectedStatus(let status) where status == errSecMissingEntitlement {
            throw XCTSkip("Keychain needs a code-signed test host (CI builds unsigned).")
        }
        XCTAssertNil(try keychain.data(for: account))
        try keychain.set(Data([1, 2, 3]), for: account)
        XCTAssertEqual(try keychain.data(for: account), Data([1, 2, 3]))
        try keychain.set(Data([9]), for: account)
        XCTAssertEqual(try keychain.data(for: account), Data([9]))
        keychain.setBool(true, for: account)
        XCTAssertTrue(keychain.bool(for: account))
        try keychain.remove(account)
        XCTAssertNil(try keychain.data(for: account))
    }
}

@MainActor
final class GameSceneTests: XCTestCase {
    private func makeScene(level: LevelDefinition) -> (SKView, GameScene) {
        let config = GameSceneConfig(level: level, assist: false, signals: .standard, reduceMotion: true,
                                     bike: CosmeticCatalog.item(id: CosmeticCatalog.defaultBike)!,
                                     jersey: CosmeticCatalog.item(id: CosmeticCatalog.defaultJersey)!,
                                     helmet: CosmeticCatalog.item(id: CosmeticCatalog.defaultHelmet)!,
                                     leftHandedHUD: false)
        let scene = GameScene(config: config)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        view.presentScene(scene)
        return (view, scene)
    }

    func testSceneSimulatesAndRendersEveryCity() {
        for city in CityID.allCases {
            let (view, scene) = makeScene(level: LevelGenerator.level(city: city, index: 5))
            var t: TimeInterval = 0
            var furthest = 0.0
            for _ in 0..<600 { // 10 seconds of frames
                scene.update(t)
                furthest = max(furthest, scene.sim.player.y)
                t += 1.0 / 60
            }
            XCTAssertGreaterThan(furthest, 40, "\(city) did not advance")
            _ = view
        }
    }

    func testCrashRestartsInstantly() {
        let level = LevelDefinition(id: .city(.newYork, index: 0), city: .newYork, index: 0, seed: 0, difficulty: 0,
                                    length: 200, parTime: 30, weather: .clear,
                                    entities: [LevelEntity(kind: .construction, lane: 1, y: 20)])
        let (_, scene) = makeScene(level: level)
        var t: TimeInterval = 0
        var crashedAt: TimeInterval?
        var restartedAt: TimeInterval?
        for _ in 0..<600 {
            scene.update(t)
            if crashedAt == nil, case .crashed = scene.sim.status { crashedAt = t }
            if crashedAt != nil, restartedAt == nil, scene.sim.isRunning, scene.attempts == 1 { restartedAt = t }
            t += 1.0 / 60
        }
        XCTAssertNotNil(crashedAt)
        XCTAssertNotNil(restartedAt)
        if let crash = crashedAt, let restart = restartedAt {
            XCTAssertLessThan(restart - crash, 1.0, "restart must take under a second")
        }
    }

    func testLevelGenerationIsFastEnoughForInstantLoads() {
        measure {
            _ = LevelGenerator.level(city: .tokyo, index: 9)
        }
    }
}

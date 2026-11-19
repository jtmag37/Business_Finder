import XCTest
@testable import CitySprintCore

final class SimulationTests: XCTestCase {
    func testCoinPickupAndFinish() {
        let level = TestLevels.make([LevelEntity(kind: .coin, lane: 1, y: 10)], length: 40)
        let sim = GameSimulation(level: level)
        let events = sim.run(seconds: 20)
        XCTAssertEqual(sim.coins, 1)
        XCTAssertTrue(events.contains(.coin(entity: 0)))
        XCTAssertEqual(sim.status, .finished)
        XCTAssertTrue(events.contains(.finished))
    }

    func testCoinInOtherLaneIsNotCollected() {
        let level = TestLevels.make([LevelEntity(kind: .coin, lane: 0, y: 10)], length: 40)
        let sim = GameSimulation(level: level)
        sim.run(seconds: 20)
        XCTAssertEqual(sim.coins, 0)
    }

    func testCrashIntoConstruction() {
        let level = TestLevels.make([LevelEntity(kind: .construction, lane: 1, y: 20)])
        let sim = GameSimulation(level: level)
        let events = sim.run(seconds: 10)
        XCTAssertEqual(sim.status, .crashed(.construction))
        XCTAssertTrue(events.contains(.crashed(.construction)))
    }

    func testLaneChangeAvoidsObstacle() {
        let level = TestLevels.make([LevelEntity(kind: .construction, lane: 1, y: 20)], length: 60)
        let sim = GameSimulation(level: level)
        sim.send(.moveRight)
        sim.run(seconds: 20)
        XCTAssertEqual(sim.status, .finished)
        XCTAssertEqual(sim.player.targetLane, 2)
    }

    func testCannotLeaveTheRoad() {
        let sim = GameSimulation(level: TestLevels.make([]))
        sim.send(.moveLeft)
        sim.send(.moveLeft)
        sim.send(.moveLeft)
        sim.run(seconds: 1)
        XCTAssertEqual(sim.player.targetLane, 0)
        XCTAssertEqual(sim.player.x, 0, accuracy: 0.0001)
    }

    func testCarDoorOpensIntoCurbLane() {
        let door = LevelEntity(kind: .parkedCarDoor, lane: 2.55, y: 30)
        let inCurbLane = GameSimulation(level: TestLevels.make([door]))
        inCurbLane.send(.moveRight)
        inCurbLane.run(seconds: 10)
        XCTAssertEqual(inCurbLane.status, .crashed(.door))

        let inMiddle = GameSimulation(level: TestLevels.make([door], length: 60))
        inMiddle.run(seconds: 15)
        XCTAssertEqual(inMiddle.status, .finished)
    }

    func testChangingLaneOnTramTracksCrashes() {
        let tram = LevelEntity(kind: .tramTracks, lane: 1, y: 20, length: 12)
        let sim = GameSimulation(level: TestLevels.make([tram]))
        sim.run(untilY: 24)
        XCTAssertTrue(sim.player.inTramZone)
        sim.send(.moveLeft)
        sim.run(seconds: 1)
        XCTAssertEqual(sim.status, .crashed(.tramTracks))
    }

    func testRidingStraightOverTramTracksIsSafe() {
        let tram = LevelEntity(kind: .tramTracks, lane: 1, y: 20, length: 12)
        let sim = GameSimulation(level: TestLevels.make([tram], length: 60))
        sim.run(seconds: 15)
        XCTAssertEqual(sim.status, .finished)
    }

    /// Light cycle is 10.7 s; red from 7.1 s. Offset 6 makes the light red
    /// between t = 1.1 s and 4.7 s, when a cruising rider reaches y = 20.
    private let redOnArrival = LevelEntity(kind: .trafficLight, lane: 1, y: 20, param: 6.0)

    func testRunningRedLightAddsPenalty() {
        let sim = GameSimulation(level: TestLevels.make([redOnArrival], length: 60))
        let events = sim.run(seconds: 15)
        XCTAssertEqual(sim.redLightsRun, 1)
        XCTAssertEqual(sim.penaltyTime, GameTuning.standard.redLightPenalty)
        XCTAssertTrue(events.contains(.ranRedLight(entity: 0)))
        XCTAssertEqual(sim.status, .finished)
        XCTAssertFalse(sim.makeResult().isClean)
    }

    func testBrakingHoldsAtRedLightUntilGreen() {
        let sim = GameSimulation(level: TestLevels.make([redOnArrival], length: 60))
        sim.run(untilY: 12)
        sim.send(.brake)
        sim.run(seconds: 1.5)
        XCTAssertTrue(sim.player.holdingAtLight)
        XCTAssertEqual(sim.player.speed, 0)
        let heldAt = sim.player.y
        XCTAssertLessThan(heldAt, 20)
        sim.run(seconds: 1)
        XCTAssertEqual(sim.player.y, heldAt, "should stay stopped while red")
        sim.run(seconds: 15)
        XCTAssertEqual(sim.redLightsRun, 0)
        XCTAssertEqual(sim.status, .finished)
    }

    func testAssistModeBrakesForRedLight() {
        let sim = GameSimulation(level: TestLevels.make([redOnArrival], length: 60), assist: true)
        sim.run(seconds: 20)
        XCTAssertEqual(sim.redLightsRun, 0)
        XCTAssertEqual(sim.status, .finished)
    }

    func testRainLengthensBraking() {
        func stoppingDistance(_ weather: Weather) -> Double {
            let sim = GameSimulation(level: TestLevels.make([], weather: weather))
            sim.run(seconds: 3)
            let start = sim.player.y
            sim.send(.brake)
            sim.run(seconds: 0.5)
            return sim.player.y - start
        }
        XCTAssertGreaterThan(stoppingDistance(.rain), stoppingDistance(.clear))
    }

    func testSprintIsFasterAndDrainsStamina() {
        let sim = GameSimulation(level: TestLevels.make([], length: 500))
        sim.run(seconds: 3)
        let cruise = sim.player.speed
        sim.send(.sprint)
        sim.run(seconds: 1)
        XCTAssertGreaterThan(sim.player.speed, cruise + 2)
        XCTAssertLessThan(sim.player.stamina, 0.8)
    }

    func testHeatDrainsStaminaFaster() {
        func staminaAfterSprint(_ weather: Weather) -> Double {
            let sim = GameSimulation(level: TestLevels.make([], length: 500, weather: weather))
            sim.send(.sprint)
            sim.run(seconds: 1)
            return sim.player.stamina
        }
        XCTAssertLessThan(staminaAfterSprint(.heat), staminaAfterSprint(.clear))
    }

    func testSprintRequiresStamina() {
        let sim = GameSimulation(level: TestLevels.make([], length: 2000))
        for _ in 0..<6 {
            sim.send(.sprint)
            sim.run(seconds: 1.5)
        }
        XCTAssertLessThan(sim.player.stamina, GameTuning.standard.minimumSprintStamina)
        sim.send(.sprint)
        sim.run(seconds: 0.1)
        XCTAssertFalse(sim.player.isSprinting)
    }

    func testWaterRestoresStamina() {
        let level = TestLevels.make([LevelEntity(kind: .water, lane: 1, y: 30)], length: 200)
        let sim = GameSimulation(level: level)
        sim.send(.sprint)
        sim.run(untilY: 25)
        let before = sim.player.stamina
        let events = sim.run(untilY: 35)
        XCTAssertTrue(events.contains(.water(entity: 0)))
        XCTAssertGreaterThan(sim.player.stamina, before + 0.2)
    }

    func testPotholeSlowsAndBreaksCleanRide() {
        let level = TestLevels.make([LevelEntity(kind: .pothole, lane: 1, y: 30)], length: 80)
        let sim = GameSimulation(level: level)
        sim.run(untilY: 29)
        let before = sim.player.speed
        let events = sim.run(untilY: 31)
        XCTAssertEqual(sim.potholeHits, 1)
        XCTAssertTrue(events.contains(.pothole(entity: 0)))
        XCTAssertLessThan(sim.player.speed, before * 0.7)
        sim.run(seconds: 20)
        XCTAssertEqual(sim.status, .finished)
        XCTAssertFalse(sim.makeResult().isClean)
    }

    func testCobblestonesCapSpeed() {
        let zone = LevelEntity(kind: .cobblestones, lane: 1, y: 10, length: 100)
        let sim = GameSimulation(level: TestLevels.make([zone], length: 200))
        sim.send(.sprint)
        sim.run(untilY: 60)
        XCTAssertTrue(sim.player.onCobbles)
        XCTAssertLessThanOrEqual(sim.player.speed, GameTuning.standard.cobbleSpeedCap + 0.01)
    }

    func testDraftingBehindBusThenSlingshot() {
        let bus = LevelEntity(kind: .bus, lane: 1, y: 30, speed: 10.5, travel: 400)
        let sim = GameSimulation(level: TestLevels.make([bus], length: 800))
        var events = sim.run(seconds: 7)
        XCTAssertEqual(sim.status, .running)
        XCTAssertTrue(sim.isDrafting)
        XCTAssertTrue(events.contains(.draftStarted(entity: 0)))
        XCTAssertGreaterThan(sim.player.speed, GameTuning.standard.cruiseSpeed)
        sim.send(.moveLeft)
        events = sim.run(seconds: 0.5)
        XCTAssertFalse(sim.isDrafting)
        XCTAssertTrue(events.contains { if case .draftBoost = $0 { return true } else { return false } })
        XCTAssertEqual(sim.draftBoosts, 1)
    }

    func testLateDodgeIsANearMissAndBuildsCombo() {
        let level = TestLevels.make([
            LevelEntity(kind: .construction, lane: 1, y: 30, length: 6),
            LevelEntity(kind: .construction, lane: 2, y: 50, length: 6),
        ], length: 120)
        let sim = GameSimulation(level: level)
        sim.run(untilY: 26)
        sim.send(.moveRight)
        var events = sim.run(untilY: 46)
        XCTAssertEqual(sim.nearMisses, 1)
        XCTAssertTrue(events.contains(.nearMiss(combo: 1, entity: 0)))
        sim.send(.moveLeft)
        events = sim.run(untilY: 65)
        XCTAssertEqual(sim.combo, 2)
        XCTAssertEqual(sim.maxCombo, 2)
        XCTAssertEqual(sim.comboPoints, ScoreRules.nearMissPoints(combo: 1) + ScoreRules.nearMissPoints(combo: 2))
        // Combo expires without further near misses.
        events = sim.run(seconds: GameTuning.standard.comboWindow + 0.1)
        XCTAssertEqual(sim.combo, 0)
        XCTAssertTrue(events.contains(.comboEnded(count: 2)))
    }

    func testEarlyLaneChangeIsNotANearMiss() {
        let level = TestLevels.make([LevelEntity(kind: .construction, lane: 1, y: 40, length: 6)], length: 80)
        let sim = GameSimulation(level: level)
        sim.send(.moveRight)
        sim.run(seconds: 15)
        XCTAssertEqual(sim.nearMisses, 0)
    }

    func testPedestrianCrossesRoad() {
        let ped = LevelEntity(kind: .pedestrian, lane: -0.9, y: 40, speed: 1.6, param: 1)
        let sim = GameSimulation(level: TestLevels.make([ped], length: 200))
        sim.run(untilY: 25)
        XCTAssertGreaterThan(sim.entities[0].lane, -0.9, "pedestrian should have started crossing")
    }

    func testSlowCarAheadInLaneCausesCrash() {
        let car = LevelEntity(kind: .car, lane: 1, y: 40, speed: 4, travel: 200)
        let sim = GameSimulation(level: TestLevels.make([car], length: 400))
        sim.run(seconds: 30)
        XCTAssertEqual(sim.status, .crashed(.vehicle))
    }

    func testAssistModeRemovesFlaggedObstacles() {
        let level = TestLevels.make([LevelEntity(kind: .construction, lane: 1, y: 20, assistSkip: true)], length: 60)
        let sim = GameSimulation(level: level, assist: true)
        sim.run(seconds: 15)
        XCTAssertEqual(sim.status, .finished)
        XCTAssertTrue(sim.entities.isEmpty)
    }

    func testResultReflectsRun() {
        let level = TestLevels.make((0..<4).map { LevelEntity(kind: .coin, lane: 1, y: 10 + Double($0) * 3) },
                                    length: 60, par: 30)
        let sim = GameSimulation(level: level)
        sim.run(seconds: 30)
        let result = sim.makeResult(crashesBeforeFinish: 2)
        XCTAssertTrue(result.finished)
        XCTAssertEqual(result.coins, 4)
        XCTAssertEqual(result.coinsForStar, 3)
        XCTAssertEqual(result.crashesBeforeFinish, 2)
        XCTAssertEqual(result.stars, 3)
    }

    func testCommandsIgnoredAfterRunEnds() {
        let sim = GameSimulation(level: TestLevels.make([], length: 20))
        sim.run(seconds: 10)
        XCTAssertEqual(sim.status, .finished)
        sim.send(.moveLeft)
        sim.step(GameSimulation.dt)
        XCTAssertEqual(sim.player.targetLane, 1)
    }

    func testGeneratedLevelsRunToCompletionWithoutInputHang() {
        // Every generated level must terminate (crash or finish) and never
        // crash in the protected start area.
        for city in CityID.allCases {
            for index in [0, 9] {
                let sim = GameSimulation(level: LevelGenerator.level(city: city, index: index))
                sim.run(seconds: 400)
                XCTAssertNotEqual(sim.status, .running, "\(city) \(index) did not end")
                if case .crashed = sim.status {
                    XCTAssertGreaterThan(sim.player.y, 35, "\(city) \(index) crashed in the start area")
                }
            }
        }
    }

    func testStepPerformance() {
        let level = LevelGenerator.level(city: .tokyo, index: 9)
        measure {
            let sim = GameSimulation(level: level, assist: true)
            for _ in 0..<(120 * 60) where sim.isRunning {
                sim.step(GameSimulation.dt)
                sim.drainEvents { _ in }
            }
        }
    }
}

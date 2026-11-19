import XCTest
@testable import CitySprintCore

final class LevelTests: XCTestCase {
    func testRandomIsDeterministic() {
        var a = SplitMix64(seed: 42)
        var b = SplitMix64(seed: 42)
        for _ in 0..<100 { XCTAssertEqual(a.next(), b.next()) }
        var c = SplitMix64(seed: 7)
        for _ in 0..<1000 {
            let u = c.unit()
            XCTAssertGreaterThanOrEqual(u, 0)
            XCTAssertLessThan(u, 1)
        }
    }

    func testStableHashMatchesFNV1aReference() {
        XCTAssertEqual(StableHash.fnv1a(""), 0xCBF2_9CE4_8422_2325)
        XCTAssertEqual(StableHash.fnv1a("a"), 0xAF63_DC4C_8601_EC8C)
    }

    func testLevelGenerationIsDeterministic() {
        for city in CityID.allCases {
            XCTAssertEqual(LevelGenerator.level(city: city, index: 4), LevelGenerator.level(city: city, index: 4))
        }
    }

    func testEveryCityLevelIsPassableAndWellFormed() {
        for city in CityID.allCases {
            for (index, level) in LevelGenerator.levels(for: city).enumerated() {
                let name = level.id.rawValue
                XCTAssertTrue(LevelValidator.isPassable(level), "\(name) is not passable")
                XCTAssertEqual(level.city, city)
                XCTAssertEqual(level.index, index)
                XCTAssertEqual(level.weather, CityCatalog.definition(for: city).weather)
                XCTAssertEqual(level.entities.map(\.y), level.entities.map(\.y).sorted(), "\(name) not sorted")
                XCTAssertGreaterThan(level.totalCoins, 15, "\(name) has too few coins")
                XCTAssertTrue(level.entities.contains { $0.kind.isLethal }, "\(name) has no hazards")
                // A run should take roughly 60-120 seconds.
                XCTAssertGreaterThanOrEqual(level.parTime, 55, name)
                XCTAssertLessThanOrEqual(level.parTime, 125, name)
                // Start area must be clear.
                XCTAssertFalse(level.entities.contains { $0.kind.isLethal && $0.y < 42 }, name)
            }
        }
    }

    func testDifficultyRisesWithinACity() {
        let levels = LevelGenerator.levels(for: .london)
        for pair in zip(levels, levels.dropFirst()) {
            XCTAssertLessThan(pair.0.difficulty, pair.1.difficulty)
            XCTAssertLessThan(pair.0.length, pair.1.length)
        }
    }

    func testCitySpecificHazards() {
        func count(_ city: CityID, _ kind: EntityKind) -> Int {
            LevelGenerator.levels(for: city).reduce(0) { sum, level in
                sum + level.entities.filter { $0.kind == kind }.count
            }
        }
        XCTAssertGreaterThan(count(.paris, .cobblestones), 0)
        XCTAssertEqual(count(.newYork, .cobblestones), 0)
        XCTAssertGreaterThan(count(.amsterdam, .tramTracks), 0)
        XCTAssertGreaterThan(count(.amsterdam, .cyclist), count(.newYork, .cyclist))
        XCTAssertEqual(count(.london, .tramTracks), 0)

        func lightsPerKm(_ city: CityID) -> Double {
            let levels = LevelGenerator.levels(for: city)
            let lights = levels.reduce(0) { $0 + $1.entities.filter { $0.kind == .trafficLight }.count }
            let km = levels.reduce(0) { $0 + $1.length } / 1000
            return Double(lights) / km
        }
        XCTAssertGreaterThan(lightsPerKm(.tokyo), lightsPerKm(.newYork) * 1.3, "Tokyo should have dense crossings")
    }

    func testWeatherPerCity() {
        XCTAssertEqual(CityCatalog.definition(for: .london).weather, .rain)
        XCTAssertEqual(CityCatalog.definition(for: .rioDeJaneiro).weather, .heat)
        XCTAssertLessThan(Weather.rain.effects.brakeMultiplier, 1)
        XCTAssertGreaterThan(Weather.heat.effects.staminaDrainMultiplier, 1)
    }

    func testDailyChallengeIsSharedAndChanges() {
        let date = Date(timeIntervalSince1970: 1_763_510_400) // 2025-11-19 00:00 UTC
        XCTAssertEqual(DailyChallenge.dayKey(for: date), 20_251_119)
        XCTAssertEqual(DailyChallenge.dayKey(for: Date(timeIntervalSince1970: 1_763_596_799)), 20_251_119)
        XCTAssertEqual(DailyChallenge.dayKey(for: Date(timeIntervalSince1970: 1_763_596_800)), 20_251_120)

        let a = DailyChallenge.level(for: date)
        let b = DailyChallenge.level(for: date.addingTimeInterval(3600))
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.isDaily)
        XCTAssertEqual(a.id.rawValue, "daily-20251119")

        let seeds = Set((0..<14).map { DailyChallenge.level(for: date.addingTimeInterval(Double($0) * 86_400)).seed })
        XCTAssertEqual(seeds.count, 14)
        for offset in 0..<30 {
            let level = DailyChallenge.level(for: date.addingTimeInterval(Double(offset) * 86_400))
            XCTAssertTrue(LevelValidator.isPassable(level), level.id.rawValue)
        }
        XCTAssertEqual(DailyChallenge.secondsUntilReset(from: date.addingTimeInterval(3600)), 23 * 3600, accuracy: 0.5)
    }

    func testLevelRoundTripsThroughJSON() throws {
        let level = LevelGenerator.level(city: .amsterdam, index: 3)
        let data = try JSONEncoder().encode(level)
        XCTAssertEqual(try JSONDecoder().decode(LevelDefinition.self, from: data), level)
    }

    func testLevelIDs() {
        XCTAssertEqual(LevelID.city(.newYork, index: 0).rawValue, "nyc-01")
        XCTAssertEqual(LevelID.city(.capeTown, index: 9).rawValue, "cpt-10")
        XCTAssertEqual(CityID(code: "ams"), .amsterdam)
    }

    // MARK: Validator

    func testValidatorDetectsFullyBlockedRoad() {
        var map = BlockMap(length: 100)
        map.block(mask: 0b111, from: 50, to: 55)
        XCTAssertFalse(LevelValidator.isPassable(map))
    }

    func testValidatorAllowsStaggeredObstacles() {
        var map = BlockMap(length: 120)
        map.block(mask: 0b010, from: 20, to: 30)
        map.block(mask: 0b001, from: 45, to: 55)
        map.block(mask: 0b100, from: 70, to: 80)
        XCTAssertTrue(LevelValidator.isPassable(map))
    }

    func testValidatorRequiresRoomToChangeLanes() {
        var map = BlockMap(length: 100)
        // Middle lane blocked from the start; the rider must move over, but a
        // tram crossing right there forbids lane changes.
        map.forbidLaneChange(from: 0, to: 40)
        map.block(mask: 0b010, from: 30, to: 40)
        XCTAssertFalse(LevelValidator.isPassable(map))
    }

    func testDoorBlocksOnlyCurbLane() {
        var map = BlockMap(length: 60)
        map.add(LevelEntity(kind: .parkedCarDoor, lane: 2.55, y: 20))
        XCTAssertTrue(map.isBlocked(lane: 2, from: 20, to: 21))
        XCTAssertFalse(map.isBlocked(lane: 1, from: 0, to: 60))
    }

    func testMoverCorridorCoversTravel() {
        var map = BlockMap(length: 200)
        map.add(LevelEntity(kind: .car, lane: 0, y: 50, speed: 4, travel: 40))
        XCTAssertTrue(map.isBlocked(lane: 0, from: 90, to: 92))
        XCTAssertFalse(map.isBlocked(lane: 1, from: 0, to: 200))
    }

    func testPalettesHaveReadableLaneMarkings() {
        for def in CityCatalog.all {
            XCTAssertGreaterThan(RGB.contrast(def.palette.road, def.palette.laneMark), 3, "\(def.id)")
        }
    }
}

import Foundation
@testable import CitySprintCore

enum TestLevels {
    static func make(_ entities: [LevelEntity], length: Double = 200, weather: Weather = .clear,
                     par: Double = 30, city: CityID = .newYork) -> LevelDefinition {
        LevelDefinition(id: .city(city, index: 0), city: city, index: 0, seed: 1, difficulty: 0.5,
                        length: length, parTime: par, weather: weather,
                        entities: entities.sorted { $0.y < $1.y })
    }
}

extension GameSimulation {
    static let dt = 1.0 / 120.0

    /// Steps for `seconds` or until the run ends; returns all events.
    @discardableResult
    func run(seconds: Double) -> [GameEvent] {
        var collected: [GameEvent] = []
        var t = 0.0
        while t < seconds && isRunning {
            step(Self.dt)
            drainEvents { collected.append($0) }
            t += Self.dt
        }
        return collected
    }

    @discardableResult
    func run(untilY y: Double, timeout: Double = 60) -> [GameEvent] {
        var collected: [GameEvent] = []
        var t = 0.0
        while player.y < y && t < timeout && isRunning {
            step(Self.dt)
            drainEvents { collected.append($0) }
            t += Self.dt
        }
        return collected
    }
}

func makeResult(finished: Bool = true, time: Double = 50, par: Double = 60, coins: Int = 10, coinsForStar: Int = 7,
                nearMisses: Int = 0, comboPoints: Int = 0, potholes: Int = 0, reds: Int = 0,
                level: LevelID = .city(.newYork, index: 0), city: CityID = .newYork, daily: Bool = false) -> RunResult {
    RunResult(levelID: level, city: city, isDaily: daily, finished: finished, time: time, parTime: par,
              coins: coins, coinsForStar: coinsForStar, nearMisses: nearMisses, maxCombo: nearMisses,
              comboPoints: comboPoints, potholeHits: potholes, redLightsRun: reds, distance: 700,
              assisted: false, crashesBeforeFinish: 0)
}

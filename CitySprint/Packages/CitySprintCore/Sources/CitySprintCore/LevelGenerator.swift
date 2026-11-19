import Foundation

/// Builds levels deterministically from (city, index) or from the daily date.
/// Every generated level is checked with `LevelValidator`, so a fair line
/// through the static hazards always exists.
public enum LevelGenerator {
    public static let levelsPerCity = 10
    public static let generatorVersion = "v1"

    public static func level(city: CityID, index: Int) -> LevelDefinition {
        precondition((0..<levelsPerCity).contains(index), "level index out of range")
        let seed = StableHash.fnv1a("citysprint.\(generatorVersion).\(city.rawValue).\(index)")
        let progress = Double(index) / Double(levelsPerCity - 1)
        let difficulty = min(1, 0.12 + progress * 0.6 + city.tier * 0.28)
        let length = 590 + Double(index) * 42 + city.tier * 30
        return generate(id: .city(city, index: index), city: city, index: index,
                        seed: seed, difficulty: difficulty, length: length)
    }

    public static func levels(for city: CityID) -> [LevelDefinition] {
        (0..<levelsPerCity).map { level(city: city, index: $0) }
    }

    /// The daily challenge: same seed (UTC date) for every player.
    public static func daily(dayKey: Int) -> LevelDefinition {
        let seed = dailySeed(dayKey: dayKey)
        let city = dailyCity(dayKey: dayKey)
        return generate(id: .daily(dayKey: dayKey), city: city, index: -1,
                        seed: seed, difficulty: 0.55, length: 900)
    }

    static func dailySeed(dayKey: Int) -> UInt64 {
        StableHash.fnv1a("citysprint.daily.\(generatorVersion).\(dayKey)")
    }

    /// The daily city without generating the whole level (cheap, for menus).
    public static func dailyCity(dayKey: Int) -> CityID {
        CityID.allCases[Int(dailySeed(dayKey: dayKey) % UInt64(CityID.allCases.count))]
    }

    /// Tiny obstacle-free level used by UI tests to exercise the results flow.
    public static func uiTestLevel(city: CityID = .newYork, daily: Bool = false) -> LevelDefinition {
        var entities: [LevelEntity] = []
        for i in 0..<5 { entities.append(LevelEntity(kind: .coin, lane: 1, y: 8 + Double(i) * 3)) }
        return LevelDefinition(id: daily ? .daily(dayKey: 20_000_101) : .city(city, index: 0), city: city,
                               index: daily ? -1 : 0, seed: 0, difficulty: 0,
                               length: 40, parTime: 10, weather: .clear, entities: entities)
    }

    // MARK: - Generation

    static func generate(id: LevelID, city: CityID, index: Int, seed: UInt64,
                         difficulty: Double, length: Double) -> LevelDefinition {
        // Retry with a derived seed in the (practically unreachable) case the
        // final validation fails, keeping the result deterministic.
        var attemptSeed = seed
        for _ in 0..<8 {
            let level = build(id: id, city: city, index: index, seed: attemptSeed,
                              difficulty: difficulty, length: length)
            if LevelValidator.isPassable(level) { return level }
            attemptSeed = attemptSeed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        }
        // Last resort: a level with only collectibles is always passable.
        var fallback = build(id: id, city: city, index: index, seed: seed, difficulty: 0, length: length)
        fallback.entities.removeAll { $0.kind.isLethal }
        return fallback
    }

    private struct Builder {
        var rng: SplitMix64
        let def: CityDefinition
        let tuning = GameTuning.standard
        let length: Double
        let difficulty: Double
        var entities: [LevelEntity] = []
        var map: BlockMap
        /// Metres where lethal obstacles must not be placed (crosswalks,
        /// rails, start and finish areas).
        var reserved: [Bool]

        init(seed: UInt64, def: CityDefinition, length: Double, difficulty: Double) {
            rng = SplitMix64(seed: seed)
            self.def = def
            self.length = length
            self.difficulty = difficulty
            map = BlockMap(length: length)
            reserved = [Bool](repeating: false, count: Int(length.rounded(.up)) + 1)
            reserve(0, 42)
            reserve(length - 28, length)
        }

        mutating func reserve(_ y0: Double, _ y1: Double) {
            let lo = max(0, Int(y0.rounded(.down)))
            let hi = min(reserved.count - 1, Int(y1.rounded(.up)))
            guard lo <= hi else { return }
            for i in lo...hi { reserved[i] = true }
        }

        func isReserved(_ y0: Double, _ y1: Double) -> Bool {
            let lo = max(0, Int(y0.rounded(.down)))
            let hi = min(reserved.count - 1, Int(y1.rounded(.up)))
            guard lo <= hi else { return true }
            for i in lo...hi where reserved[i] { return true }
            return false
        }

        /// Adds a lethal entity only if the level stays passable.
        @discardableResult
        mutating func tryPlaceLethal(_ e: LevelEntity) -> Bool {
            let sweep = e.kind.isMover ? e.travel : 0
            guard e.y + e.length + sweep < length - 20, !isReserved(e.y - 4, e.y + e.length + sweep + 4) else {
                return false
            }
            var candidate = map
            candidate.add(e)
            guard LevelValidator.isPassable(candidate) else { return false }
            map = candidate
            entities.append(e)
            return true
        }

        mutating func pickHazard() -> EntityKind {
            let total = def.hazards.reduce(0) { $0 + $1.weight }
            var roll = rng.unit() * total
            for h in def.hazards {
                roll -= h.weight
                if roll <= 0 { return h.kind }
            }
            return def.hazards.last?.kind ?? .car
        }

        mutating func vehicleColour() -> UInt8 {
            UInt8(rng.int(max(1, def.palette.vehicles.count)))
        }

        mutating func lanesInRandomOrder() -> [Int] {
            var lanes = [0, 1, 2]
            rng.shuffle(&lanes)
            return lanes
        }

        // MARK: Features

        mutating func placeLights() {
            var y = rng.range(def.lightSpacing) * 0.55 + 60
            while y < length - 70 {
                let phase = rng.range(0, tuning.lightCycle)
                entities.append(LevelEntity(kind: .trafficLight, lane: 1, y: y, param: phase))
                // Keep the approach and the junction itself clear so the
                // player can always stop safely at the line.
                reserve(y - 18, y + 8)
                if rng.chance(def.crosswalkChance) {
                    placePedestrian(at: y + 2.5)
                }
                y += rng.range(def.lightSpacing)
            }
        }

        mutating func placePedestrian(at y: Double) {
            let fromLeft = rng.chance(0.5)
            let speed = rng.range(1.3, 1.9) * (1 + difficulty * 0.25)
            entities.append(LevelEntity(kind: .pedestrian, lane: fromLeft ? -0.9 : 2.9, y: y, speed: speed,
                                        param: fromLeft ? 1 : -1, assistSkip: rng.chance(0.35),
                                        variant: UInt8(rng.int(6))))
            reserve(y - 14, y + 6)
        }

        mutating func placeFreePedestrians() {
            let count = Int((length / 100 * def.pedestriansPer100m * (0.6 + difficulty)).rounded())
            for _ in 0..<count {
                for _ in 0..<6 {
                    let y = rng.range(80, length - 60)
                    if !isReserved(y - 14, y + 6) {
                        placePedestrian(at: y)
                        break
                    }
                }
            }
        }

        mutating func placeZones() {
            let cobbles = Int((length / 1000 * def.cobblesPerKm).rounded())
            for _ in 0..<cobbles {
                let zoneLength = rng.range(40, 75)
                let y = rng.range(60, max(61, length - zoneLength - 40))
                entities.append(LevelEntity(kind: .cobblestones, lane: 1, y: y, length: zoneLength))
            }
            let trams = Int((length / 1000 * def.tramsPerKm).rounded())
            for _ in 0..<trams {
                for _ in 0..<6 {
                    let zoneLength = rng.range(9, 14)
                    let y = rng.range(80, length - 60)
                    if !isReserved(y - 10, y + zoneLength + 10) {
                        let tram = LevelEntity(kind: .tramTracks, lane: 1, y: y, length: zoneLength,
                                               variant: UInt8(rng.int(2)))
                        entities.append(tram)
                        map.add(tram)
                        reserve(y - 10, y + zoneLength + 10)
                        break
                    }
                }
            }
        }

        mutating func placeHazards() {
            var cursor = 48.0
            let gap = 25 - 13 * difficulty
            while cursor < length - 40 {
                let kind = pickHazard()
                var placed = false
                for lane in lanesInRandomOrder() where !placed {
                    if let e = makeHazard(kind, lane: lane, y: cursor) {
                        placed = place(e)
                    }
                }
                // Occasionally pair a second hazard in another lane to form
                // a "gate" on harder levels.
                if placed, rng.chance(difficulty * 0.35) {
                    let second = pickHazard()
                    for lane in lanesInRandomOrder() {
                        let y = cursor + rng.range(2, 6)
                        if let e = makeHazard(second, lane: lane, y: y), place(e) {
                            break
                        }
                    }
                }
                let extra = kind == .construction ? 14.0 : (kind == .bus ? 10.0 : 0)
                cursor += gap * rng.range(0.75, 1.3) + extra
            }
        }

        mutating func place(_ e: LevelEntity) -> Bool {
            if e.kind.isLethal { return tryPlaceLethal(e) }
            entities.append(e)
            return true
        }

        mutating func makeHazard(_ kind: EntityKind, lane: Int, y: Double) -> LevelEntity? {
            let skip = rng.chance(0.3)
            let d = difficulty
            switch kind {
            case .car:
                return LevelEntity(kind: .car, lane: Double(lane), y: y, speed: rng.range(3.5, 6.0),
                                   travel: rng.range(22, 42), swerve: swerve(lane: lane, chance: 0.12 * d),
                                   assistSkip: skip, variant: vehicleColour())
            case .bus:
                return LevelEntity(kind: .bus, lane: Double(lane), y: y, speed: rng.range(10.2, 11.0),
                                   travel: rng.range(85, 130), assistSkip: false, variant: vehicleColour())
            case .scooter:
                return LevelEntity(kind: .scooter, lane: Double(lane), y: y, speed: rng.range(5.5, 7.2),
                                   travel: rng.range(25, 45), swerve: swerve(lane: lane, chance: 0.35 + 0.3 * d),
                                   assistSkip: skip, variant: vehicleColour())
            case .cyclist:
                return LevelEntity(kind: .cyclist, lane: Double(lane), y: y, speed: rng.range(5.0, 6.6),
                                   travel: rng.range(25, 50), swerve: swerve(lane: lane, chance: 0.25 + 0.25 * d),
                                   assistSkip: skip, variant: UInt8(rng.int(6)))
            case .parkedCarDoor:
                return LevelEntity(kind: .parkedCarDoor, lane: 2.55, y: y, assistSkip: skip, variant: vehicleColour())
            case .construction:
                return LevelEntity(kind: .construction, lane: Double(lane), y: y, length: rng.range(12, 22 + 8 * d),
                                   assistSkip: skip)
            case .pothole:
                return LevelEntity(kind: .pothole, lane: Double(lane) + rng.range(-0.15, 0.15), y: y,
                                   assistSkip: skip, variant: UInt8(rng.int(3)))
            default:
                return nil
            }
        }

        mutating func swerve(lane: Int, chance: Double) -> Double {
            guard rng.chance(chance) else { return 0 }
            if lane == 0 { return 1 }
            if lane == 2 { return -1 }
            return rng.chance(0.5) ? 1 : -1
        }

        mutating func placeCollectibles() {
            var y = 30.0
            while y < length - 20 {
                let count = 3 + rng.int(3)
                let span = Double(count) * 3
                for lane in lanesInRandomOrder() where !map.isBlocked(lane: lane, from: y - 1, to: y + span + 1) {
                    for i in 0..<count {
                        entities.append(LevelEntity(kind: .coin, lane: Double(lane), y: y + Double(i) * 3,
                                                    assistSkip: false))
                    }
                    break
                }
                y += rng.range(24, 38)
            }
            var w = rng.range(150, 220)
            while w < length - 40 {
                for lane in lanesInRandomOrder() where !map.isBlocked(lane: lane, from: w - 2, to: w + 2) {
                    entities.append(LevelEntity(kind: .water, lane: Double(lane), y: w))
                    break
                }
                w += rng.range(190, 260)
            }
        }
    }

    private static func build(id: LevelID, city: CityID, index: Int, seed: UInt64,
                              difficulty: Double, length: Double) -> LevelDefinition {
        let def = CityCatalog.definition(for: city)
        var b = Builder(seed: seed, def: def, length: length, difficulty: difficulty)
        b.placeLights()
        b.placeZones()
        b.placeFreePedestrians()
        if difficulty > 0 { b.placeHazards() }
        b.placeCollectibles()
        let entities = b.entities.sorted { lhs, rhs in
            lhs.y != rhs.y ? lhs.y < rhs.y : lhs.kind.rawValue < rhs.kind.rawValue
        }
        let par = parTime(length: length, entities: entities, weather: def.weather)
        return LevelDefinition(id: id, city: city, index: index, seed: seed, difficulty: difficulty,
                               length: length, parTime: par, weather: def.weather, entities: entities)
    }

    /// Par is an achievable-but-brisk time: mostly cruising with some
    /// sprinting and drafting, waiting at roughly a third of the lights.
    static func parTime(length: Double, entities: [LevelEntity], weather: Weather) -> Double {
        let t = GameTuning.standard
        let nominal = t.cruiseSpeed * weather.effects.cruiseMultiplier * 1.07
        var time = length / nominal
        for e in entities {
            switch e.kind {
            case .trafficLight: time += 1.2
            case .cobblestones: time += e.length / t.cobbleSpeedCap - e.length / nominal
            default: break
            }
        }
        return (time * 2).rounded(.up) / 2
    }
}

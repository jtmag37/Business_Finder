import Foundation

public enum PlayerCommand: Sendable, Equatable {
    case moveLeft
    case moveRight
    /// Tap: sprint, or release the brake when holding at a light.
    case sprint
    case brake
}

public enum TrafficLightPhase: Sendable, Equatable {
    case go
    case caution
    case stop
}

public enum CrashCause: UInt8, Sendable, Equatable {
    case vehicle
    case door
    case pedestrian
    case construction
    case tramTracks
    case cyclist
}

/// Events emitted during a step. Payloads are plain values so the event
/// buffer never allocates once its capacity is reserved.
public enum GameEvent: Sendable, Equatable {
    case coin(entity: Int)
    case water(entity: Int)
    case nearMiss(combo: Int, entity: Int)
    case comboEnded(count: Int)
    case pothole(entity: Int)
    case ranRedLight(entity: Int)
    case laneChange
    case sprintStarted
    case brakeApplied
    case draftStarted(entity: Int)
    case draftBoost(strength: Double)
    case enteredCobbles
    case crashed(CrashCause)
    case finished
}

public enum RunStatus: Sendable, Equatable {
    case running
    case crashed(CrashCause)
    case finished
}

public struct PlayerState: Sendable, Equatable {
    public var targetLane: Int = 1
    /// Lateral position in lane units.
    public var x: Double = 1
    /// Front wheel position along the road (m).
    public var y: Double = 0
    public var speed: Double = 4
    public var stamina: Double = 1
    public var sprintTimer: Double = 0
    public var brakeTimer: Double = 0
    public var holdingAtLight = false
    public var boostTimer: Double = 0
    public var boostStrength: Double = 0
    public var draftCharge: Double = 0
    public var onCobbles = false
    public var inTramZone = false

    public var isSprinting: Bool { sprintTimer > 0 }
    public var isBraking: Bool { brakeTimer > 0 || holdingAtLight }
    public var isChangingLane: Bool { abs(x - Double(targetLane)) > 0.0001 }
}

/// Runtime state of one level entity.
public struct EntityState: Sendable, Equatable {
    public enum Phase: UInt8, Sendable {
        /// Waiting (movers not yet activated, static obstacles).
        case idle
        /// Moving / crossing / opening.
        case active
        /// No longer interactive (passed, turning off, collected) but may
        /// still be visible for a moment.
        case exiting
        /// Can be dropped by the renderer.
        case gone
    }

    public let kind: EntityKind
    public let spawnLane: Double
    public let spawnY: Double
    public let length: Double
    public let width: Double
    public let maxSpeed: Double
    public let travel: Double
    public let swerve: Double
    public let param: Double
    public let variant: UInt8

    public var lane: Double
    public var y: Double
    public var speed: Double = 0
    public var travelled: Double = 0
    public var timer: Double = 0
    /// Car doors: 0 closed ... 1 open.
    public var openAmount: Double = 0
    public var phase: Phase = .idle
    public var passed = false
    public var dodged = false
    public var touched = false
    /// Turn-off direction for movers leaving the road (+1 right, -1 left).
    public var exitDirection: Double = 1

    init(_ e: LevelEntity) {
        kind = e.kind
        spawnLane = e.lane
        spawnY = e.y
        length = e.length
        width = e.width
        maxSpeed = e.speed
        travel = e.travel
        swerve = e.swerve
        param = e.param
        variant = e.variant
        lane = e.lane
        y = e.y
        if e.kind.isMover && e.kind != .bus { speed = e.speed }
    }

    public var isInteractive: Bool { phase == .idle || phase == .active }

    /// True while a swerving mover is signalling before it moves over.
    public var isSignalling: Bool {
        swerve != 0 && phase == .active && timer < GameTuning.standard.swerveDelay
    }

    /// Lateral extent [min, max] in lane units for collision purposes.
    public var lateralExtent: (Double, Double) {
        if kind == .parkedCarDoor {
            // Hinged at the curb edge, swings into the right-hand lane.
            let reach = width * openAmount
            return (lane - reach, lane)
        }
        return (lane - width / 2, lane + width / 2)
    }
}

/// Deterministic fixed-step simulation of one run. The renderer feeds it
/// commands and steps it at a fixed rate; nothing here allocates per step.
public final class GameSimulation {
    public let level: LevelDefinition
    public let tuning: GameTuning
    public let effects: WeatherEffects
    public let assist: Bool

    public private(set) var player = PlayerState()
    public private(set) var entities: [EntityState]
    public private(set) var status: RunStatus = .running
    public private(set) var time: Double = 0
    public private(set) var penaltyTime: Double = 0
    public private(set) var coins = 0
    public private(set) var nearMisses = 0
    public private(set) var combo = 0
    public private(set) var maxCombo = 0
    public private(set) var comboTimer: Double = 0
    public private(set) var comboPoints = 0
    public private(set) var potholeHits = 0
    public private(set) var redLightsRun = 0
    public private(set) var draftBoosts = 0
    /// Index of the bus being drafted, or -1.
    public private(set) var draftingEntity = -1
    /// Entities below this index are gone.
    public private(set) var lowIndex = 0
    /// Entities at or above this index have not been reached yet.
    public private(set) var highIndex = 0

    private var commands: [PlayerCommand] = []
    private var events: [GameEvent] = []
    private let hitHalfWidth: Double
    private let hitLength: Double

    public init(level: LevelDefinition, assist: Bool = false, tuning: GameTuning = .standard) {
        self.level = level
        self.assist = assist
        self.tuning = tuning
        self.effects = level.weather.effects
        let scale = assist ? tuning.assistHitboxScale : 1
        hitHalfWidth = tuning.playerHalfWidth * scale
        hitLength = tuning.playerLength * scale
        entities = level.entities.compactMap { e in
            assist && e.assistSkip ? nil : EntityState(e)
        }
        commands.reserveCapacity(8)
        events.reserveCapacity(32)
        player.speed = tuning.cruiseSpeed * 0.5
    }

    // MARK: - Public API

    public var isRunning: Bool { status == .running }
    public var totalTime: Double { time + penaltyTime }
    public var progress: Double { min(1, max(0, player.y / level.length)) }
    public var parTime: Double { level.parTime(assist: assist) }
    public var isDrafting: Bool { draftingEntity >= 0 }

    public func send(_ command: PlayerCommand) {
        guard status == .running, commands.count < 8 else { return }
        commands.append(command)
    }

    /// Calls `body` for each event raised since the last drain.
    public func drainEvents(_ body: (GameEvent) -> Void) {
        for event in events { body(event) }
        events.removeAll(keepingCapacity: true)
    }

    public func lightPhase(of entity: EntityState) -> TrafficLightPhase {
        lightPhase(offset: entity.param)
    }

    public func lightPhase(offset: Double) -> TrafficLightPhase {
        let cycle = tuning.lightCycle
        var t = (time + offset).truncatingRemainder(dividingBy: cycle)
        if t < 0 { t += cycle }
        if t < tuning.lightGreen { return .go }
        if t < tuning.lightGreen + tuning.lightYellow { return .caution }
        return .stop
    }

    public func makeResult(crashesBeforeFinish: Int = 0) -> RunResult {
        RunResult(
            levelID: level.id, city: level.city, isDaily: level.isDaily,
            finished: status == .finished, time: (totalTime * 100).rounded() / 100, parTime: parTime,
            coins: coins, coinsForStar: level.coinsRequiredForStar(assist: assist),
            nearMisses: nearMisses, maxCombo: maxCombo, comboPoints: comboPoints,
            potholeHits: potholeHits, redLightsRun: redLightsRun,
            distance: min(player.y, level.length), assisted: assist,
            crashesBeforeFinish: crashesBeforeFinish, drafts: draftBoosts
        )
    }

    /// Advances the simulation by `dt` seconds (use a fixed step).
    public func step(_ dt: Double) {
        guard status == .running else { return }
        time += dt
        applyCommands()
        updatePlayer(dt)
        updateEntities(dt)
        guard status == .running else { return }
        updateCombo(dt)
        if player.y >= level.length {
            status = .finished
            emit(.finished)
        }
    }

    // MARK: - Commands

    private func applyCommands() {
        guard !commands.isEmpty else { return }
        for command in commands {
            switch command {
            case .moveLeft: changeLane(by: -1)
            case .moveRight: changeLane(by: 1)
            case .sprint: startSprint()
            case .brake:
                player.brakeTimer = tuning.brakePulse
                player.sprintTimer = 0
                emit(.brakeApplied)
            }
        }
        commands.removeAll(keepingCapacity: true)
    }

    private func changeLane(by delta: Int) {
        let target = player.targetLane + delta
        guard target >= 0, target < tuning.laneCount else { return }
        let fromLane = player.targetLane
        player.targetLane = target
        emit(.laneChange)
        // Mark hazards we are dodging late so passing them counts as a near miss.
        var i = lowIndex
        while i < highIndex {
            let e = entities[i]
            if e.kind.isLethal, e.isInteractive, !e.dodged {
                let (lo, hi) = e.lateralExtent
                let inOldLane = hi > Double(fromLane) - hitHalfWidth && lo < Double(fromLane) + hitHalfWidth
                let gap = e.y - player.y
                let closing = player.speed - (e.kind.isMover ? e.speed : 0)
                if inOldLane, gap > 0, closing > 0.1, gap / closing < tuning.dodgeWindow {
                    entities[i].dodged = true
                }
            }
            i += 1
        }
    }

    private func startSprint() {
        if player.holdingAtLight || player.brakeTimer > 0 {
            player.holdingAtLight = false
            player.brakeTimer = 0
        }
        guard player.stamina >= tuning.minimumSprintStamina else { return }
        if player.sprintTimer <= 0 { emit(.sprintStarted) }
        player.sprintTimer = tuning.sprintDuration
    }

    // MARK: - Player

    private func updatePlayer(_ dt: Double) {
        // Stamina
        if player.sprintTimer > 0 {
            player.sprintTimer -= dt
            player.stamina -= tuning.sprintDrainPerSecond * effects.staminaDrainMultiplier * dt
            if player.stamina <= 0 {
                player.stamina = 0
                player.sprintTimer = 0
            }
        } else {
            let regen = tuning.staminaRegenPerSecond * effects.staminaRegenMultiplier
                * (isDrafting ? tuning.draftRegenMultiplier : 1)
            player.stamina = min(1, player.stamina + regen * dt)
        }

        updateLightHold()

        // Target speed
        var target = tuning.cruiseSpeed * effects.cruiseMultiplier
        if player.sprintTimer > 0 { target = tuning.sprintSpeed * effects.cruiseMultiplier }
        if player.boostTimer > 0 {
            target += tuning.boostSpeed * player.boostStrength * (player.boostTimer / tuning.boostDuration)
            player.boostTimer = max(0, player.boostTimer - dt)
        }
        if draftingEntity >= 0 {
            let bus = entities[draftingEntity]
            target = max(target, bus.speed)
            // Auto-hold a safe gap unless the rider deliberately sprints.
            if bus.y - player.y < tuning.draftHoldGap && player.sprintTimer <= 0 {
                target = min(target, max(0, bus.speed - 1.5))
            }
        }
        if player.onCobbles { target = min(target, tuning.cobbleSpeedCap) }

        if player.holdingAtLight {
            player.speed = 0
        } else if player.brakeTimer > 0 {
            player.brakeTimer -= dt
            player.speed = max(0, player.speed - tuning.brakeDeceleration * effects.brakeMultiplier * dt)
        } else if player.speed < target {
            player.speed = min(target, player.speed + tuning.acceleration * dt)
        } else {
            player.speed = max(target, player.speed - tuning.coastDeceleration * dt)
        }

        // Lateral movement
        let tx = Double(player.targetLane)
        let dx = tx - player.x
        let maxStep = tuning.laneChangeSpeed * dt
        player.x = abs(dx) <= maxStep ? tx : player.x + (dx > 0 ? maxStep : -maxStep)

        player.y += player.speed * dt
    }

    /// Finds the next traffic light ahead and decides whether to hold.
    private func updateLightHold() {
        var nextLight = -1
        var i = lowIndex
        while i < highIndex {
            if entities[i].kind == .trafficLight && !entities[i].passed {
                nextLight = i
                break
            }
            i += 1
        }
        guard nextLight >= 0 else {
            player.holdingAtLight = false
            return
        }
        let phase = lightPhase(of: entities[nextLight])
        let distance = entities[nextLight].y - player.y
        if player.holdingAtLight {
            if phase == .go { player.holdingAtLight = false }
            return
        }
        guard phase != .go, distance > 0 else { return }
        // Braked to a crawl just before the line: hold until green.
        if distance < tuning.lightHoldDistance && player.speed < 2.0 && player.brakeTimer > 0 {
            player.holdingAtLight = true
            player.brakeTimer = 0
            player.speed = 0
            return
        }
        // Assist mode brakes automatically for red/amber lights.
        if assist {
            let decel = tuning.brakeDeceleration * effects.brakeMultiplier
            let stopping = player.speed * player.speed / (2 * decel)
            if distance < stopping + 3 && player.sprintTimer <= 0 {
                player.brakeTimer = max(player.brakeTimer, 0.1)
            }
        }
    }

    // MARK: - Entities

    private func updateEntities(_ dt: Double) {
        let py = player.y
        while highIndex < entities.count && entities[highIndex].spawnY < py + tuning.scanAhead {
            highIndex += 1
        }

        player.onCobbles = false
        player.inTramZone = false
        var draftCandidate = -1
        var draftGap = Double.greatestFiniteMagnitude

        let pLo = player.x - hitHalfWidth
        let pHi = player.x + hitHalfWidth
        let pRear = py - hitLength

        var i = lowIndex
        while i < highIndex {
            if entities[i].phase == .gone {
                i += 1
                continue
            }
            advance(entity: i, dt: dt, playerY: py)
            let e = entities[i]

            // Fully behind the camera: drop it.
            if e.y + e.length < py - tuning.behindMargin {
                entities[i].phase = .gone
                i += 1
                continue
            }

            if e.isInteractive {
                let (lo, hi) = e.lateralExtent
                let overlapsY = py > e.y && pRear < e.y + e.length
                let overlapsX = pHi > lo && pLo < hi

                switch e.kind {
                case .coin, .water:
                    if overlapsY && overlapsX { collect(i) }
                case .pothole:
                    if overlapsY && overlapsX && !e.touched {
                        entities[i].touched = true
                        player.speed *= tuning.potholeSpeedFactor
                        potholeHits += 1
                        breakCombo()
                        emit(.pothole(entity: i))
                    }
                case .cobblestones:
                    if py > e.y && py < e.y + e.length {
                        if !e.touched {
                            entities[i].touched = true
                            emit(.enteredCobbles)
                        }
                        player.onCobbles = true
                    }
                case .tramTracks:
                    if py > e.y && pRear < e.y + e.length {
                        player.inTramZone = true
                        if player.isChangingLane {
                            crash(.tramTracks)
                            return
                        }
                    }
                case .trafficLight:
                    if !e.passed && py >= e.y {
                        entities[i].passed = true
                        if lightPhase(of: e) == .stop {
                            penaltyTime += tuning.redLightPenalty
                            redLightsRun += 1
                            breakCombo()
                            emit(.ranRedLight(entity: i))
                        }
                    }
                default:
                    if e.kind.isLethal {
                        if overlapsY && overlapsX {
                            crash(cause(for: e.kind))
                            return
                        }
                        if !e.passed && pRear > e.y + e.length {
                            entities[i].passed = true
                            let gap = max(lo - pHi, pLo - hi)
                            if e.dodged || (gap >= 0 && gap < tuning.nearMissLateralGap) {
                                registerNearMiss(entity: i)
                            }
                            if e.kind.isMover {
                                // Overtaken traffic falls behind and stops interacting.
                                entities[i].phase = .exiting
                            }
                        }
                        if e.kind == .bus && e.phase == .active {
                            let gap = e.y - py
                            if abs(player.x - e.lane) < tuning.draftLateralTolerance
                                && gap > 0 && gap < tuning.draftMaxGap && gap < draftGap {
                                draftCandidate = i
                                draftGap = gap
                            }
                        }
                    }
                }
            }
            i += 1
        }

        while lowIndex < highIndex && entities[lowIndex].phase == .gone {
            lowIndex += 1
        }
        updateDraft(candidate: draftCandidate, dt: dt)
    }

    private func advance(entity i: Int, dt: Double, playerY py: Double) {
        let kind = entities[i].kind
        switch kind {
        case .car, .bus, .scooter, .cyclist:
            var e = entities[i]
            let activation = kind == .bus ? tuning.busActivationDistance : tuning.activationDistance
            if e.phase == .idle && e.y - py < activation {
                e.phase = .active
                e.exitDirection = e.spawnLane < 1 ? -1 : 1
            }
            if e.phase == .active {
                e.timer += dt
                if kind == .bus {
                    e.speed = min(e.maxSpeed, e.speed + tuning.busAcceleration * dt)
                }
                let move = e.speed * dt
                e.y += move
                e.travelled += move
                if e.swerve != 0 && e.timer > tuning.swerveDelay {
                    let target = e.spawnLane + e.swerve
                    let step = tuning.swerveSpeed * dt
                    let d = target - e.lane
                    e.lane = abs(d) <= step ? target : e.lane + (d > 0 ? step : -step)
                }
                if e.travelled >= e.travel {
                    // Turns off into a side street.
                    e.phase = .exiting
                    e.timer = 0
                }
            } else if e.phase == .exiting {
                e.timer += dt
                e.y += e.speed * dt
                if e.travelled >= e.travel {
                    e.lane += e.exitDirection * 2.5 * dt
                    if e.timer > 1.2 { e.phase = .gone }
                } else {
                    // Overtaken: ease off so it drifts behind the rider.
                    e.speed = max(0, min(e.speed, player.speed * 0.75))
                }
            }
            entities[i] = e
        case .parkedCarDoor:
            if entities[i].isInteractive && entities[i].y - py < tuning.doorTriggerDistance {
                entities[i].phase = .active
                entities[i].timer += dt
                entities[i].openAmount = min(1, entities[i].timer / tuning.doorOpenSeconds)
            }
        case .pedestrian:
            if entities[i].phase == .idle && entities[i].y - py < tuning.pedestrianTriggerDistance {
                entities[i].phase = .active
            }
            if entities[i].phase == .active {
                entities[i].lane += entities[i].param * entities[i].maxSpeed * dt
                let l = entities[i].lane
                if l < -1.2 || l > 3.2 { entities[i].phase = .exiting }
            }
        default:
            break
        }
    }

    private func updateDraft(candidate: Int, dt: Double) {
        if candidate >= 0 {
            if draftingEntity != candidate { emit(.draftStarted(entity: candidate)) }
            draftingEntity = candidate
            player.draftCharge = min(1, player.draftCharge + dt / tuning.draftChargeSeconds)
        } else if draftingEntity >= 0 {
            // Pulling out of the slipstream slingshots the rider forward.
            if player.draftCharge >= tuning.minimumDraftCharge {
                player.boostStrength = player.draftCharge
                player.boostTimer = tuning.boostDuration
                draftBoosts += 1
                emit(.draftBoost(strength: player.draftCharge))
            }
            draftingEntity = -1
            player.draftCharge = 0
        }
    }

    private func collect(_ i: Int) {
        entities[i].phase = .gone
        if entities[i].kind == .coin {
            coins += 1
            emit(.coin(entity: i))
        } else {
            player.stamina = min(1, player.stamina + tuning.waterStamina)
            emit(.water(entity: i))
        }
    }

    private func registerNearMiss(entity: Int) {
        nearMisses += 1
        combo += 1
        maxCombo = max(maxCombo, combo)
        comboTimer = tuning.comboWindow
        comboPoints += ScoreRules.nearMissPoints(combo: combo, cap: tuning.maxComboMultiplier)
        emit(.nearMiss(combo: combo, entity: entity))
    }

    private func breakCombo() {
        if combo > 0 { emit(.comboEnded(count: combo)) }
        combo = 0
        comboTimer = 0
    }

    private func updateCombo(_ dt: Double) {
        guard combo > 0 else { return }
        comboTimer -= dt
        if comboTimer <= 0 { breakCombo() }
    }

    private func crash(_ cause: CrashCause) {
        status = .crashed(cause)
        player.speed = 0
        emit(.crashed(cause))
    }

    private func cause(for kind: EntityKind) -> CrashCause {
        switch kind {
        case .parkedCarDoor: return .door
        case .pedestrian: return .pedestrian
        case .construction: return .construction
        case .cyclist: return .cyclist
        default: return .vehicle
        }
    }

    private func emit(_ event: GameEvent) {
        events.append(event)
    }
}

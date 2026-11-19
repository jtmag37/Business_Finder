import SpriteKit
import UIKit
import CitySprintCore

@MainActor
protocol GameSceneDelegate: AnyObject {
    func gameSceneDidFinish(_ result: RunResult)
    func gameSceneDidCrash(distance: Double, nearMisses: Int, drafts: Int)
}

struct GameSceneConfig {
    var level: LevelDefinition
    var assist: Bool
    var signals: SignalPalette
    var reduceMotion: Bool
    var bike: CosmeticItem
    var jersey: CosmeticItem
    var helmet: CosmeticItem
    var leftHandedHUD: Bool
}

/// Renders a `GameSimulation`. The simulation runs at a fixed 120 Hz step;
/// rendering reuses pooled nodes and pre-built textures, so steady-state
/// frames do not allocate.
final class GameScene: SKScene {
    static let fixedStep = 1.0 / 120.0
    static let crashFreeze = 0.45

    weak var gameDelegate: GameSceneDelegate?
    var haptics: HapticsService?
    var sound: SoundService?

    private(set) var config: GameSceneConfig
    private(set) var sim: GameSimulation
    private(set) var attempts = 0

    /// Freezes the simulation (pause menu, tutorial, results) while still
    /// rendering. Independent of SpriteKit's own `isPaused`, which SwiftUI
    /// and the system may toggle on their own.
    var isFrozen = false {
        didSet { if oldValue && !isFrozen { resetClock() } }
    }

    var safeInsets: UIEdgeInsets = .zero {
        didSet { if oldValue != safeInsets { layoutHUD() } }
    }

    // Layout
    private var laneW: CGFloat = 80
    private var ppm: CGFloat = 20
    private var playerScreenOffset: CGFloat = 0
    private var cameraXOffset: CGFloat = 0
    private var built = false

    // Nodes
    private let cam = SKCameraNode()
    private let world = SKNode()
    private var atlas: SKTextureAtlas?
    private var playerNode = SKSpriteNode()
    private var draftGlow = SKSpriteNode()
    private var entityNodes: [SKNode?] = []
    private var pools: [[SKNode]] = Array(repeating: [], count: EntityKind.allCases.count)
    private var releasedUpTo = 0
    private var dashes: [SKSpriteNode] = []
    private var leftLots: [SKSpriteNode] = []
    private var rightLots: [SKSpriteNode] = []
    private var rainDrops: [SKSpriteNode] = []
    private var speedLines: [SKSpriteNode] = []
    private var pops: [SKSpriteNode] = []
    private var nextPop = 0
    private let flash = SKSpriteNode(color: .white, size: .zero)
    private let weatherTint = SKSpriteNode(color: .clear, size: .zero)

    // HUD
    private let hud = SKNode()
    private let progressBack = SKSpriteNode(color: UIColor(white: 0, alpha: 0.35), size: .zero)
    private let progressFill = SKSpriteNode(color: .white, size: .zero)
    private let timerLabel = SKLabelNode()
    private let coinLabel = SKLabelNode()
    private let staminaBack = SKSpriteNode(color: UIColor(white: 0, alpha: 0.35), size: .zero)
    private let staminaFill = SKSpriteNode(color: .white, size: .zero)
    private let comboLabel = SKLabelNode()
    private let toastLabel = SKLabelNode()
    private var shownTenths = -1
    private var shownCoins = -1

    // Loop state
    private var lastUpdate: TimeInterval?
    private var accumulator = 0.0
    private var crashTimer = 0.0
    private var shake = 0.0
    private var elapsed = 0.0
    private var finishedReported = false

    // Input
    private var touchStart: CGPoint?
    private var touchStartTime: TimeInterval = 0
    private var touchConsumed = false

    private let popAction = SKAction.group([
        SKAction.scale(to: 2.2, duration: 0.25),
        SKAction.fadeOut(withDuration: 0.25),
    ])
    private let comboPulse = SKAction.sequence([
        SKAction.scale(to: 1.25, duration: 0.08), SKAction.scale(to: 1.0, duration: 0.12),
    ])
    private let toastAction = SKAction.sequence([
        SKAction.fadeIn(withDuration: 0.1), SKAction.wait(forDuration: 1.1), SKAction.fadeOut(withDuration: 0.3),
    ])
    private let flashAction = SKAction.sequence([
        SKAction.fadeAlpha(to: 0.55, duration: 0.04), SKAction.fadeAlpha(to: 0, duration: 0.35),
    ])

    init(config: GameSceneConfig) {
        self.config = config
        self.sim = GameSimulation(level: config.level, assist: config.assist)
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
        backgroundColor = CityCatalog.definition(for: config.level.city).palette.sidewalk.uiColor
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - Setup

    override func didMove(to view: SKView) {
        view.isMultipleTouchEnabled = false
        if !built { build() }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard built, size != oldSize, size.width > 0 else { return }
        // Rebuild layout-dependent textures/nodes for the new size (rotation
        // is locked, so this only happens on first layout or iPad resizes).
        teardown()
        build()
    }

    private func teardown() {
        removeAllChildren()
        world.removeAllChildren()
        cam.removeAllChildren()
        hud.removeAllChildren()
        entityNodes = Array(repeating: nil, count: sim.entities.count)
        pools = Array(repeating: [], count: EntityKind.allCases.count)
        releasedUpTo = 0
        dashes.removeAll()
        leftLots.removeAll()
        rightLots.removeAll()
        rainDrops.removeAll()
        speedLines.removeAll()
        pops.removeAll()
        built = false
    }

    private func build() {
        guard size.width > 0, size.height > 0 else { return }
        built = true
        laneW = min(size.width / 5.6, size.height / 9)
        ppm = size.height / 40
        playerScreenOffset = -size.height * 0.3
        cameraXOffset = laneW * 0.375

        let def = CityCatalog.definition(for: config.level.city)
        let factory = TextureFactory(city: def, signals: config.signals,
                                     metrics: .init(laneWidth: laneW, pointsPerMeter: ppm),
                                     bike: config.bike, jersey: config.jersey, helmet: config.helmet)
        let atlas = factory.makeAtlas()
        self.atlas = atlas

        addChild(world)
        addChild(cam)
        camera = cam

        buildBackground(def)
        buildPlayer()
        buildEffects(def)
        buildHUD()
        resetEntityNodes()
        prewarmPools()
        render()
    }

    private func tex(_ name: String) -> SKTexture {
        atlas?.textureNamed(name) ?? SKTexture()
    }

    private func x(lane: Double) -> CGFloat { CGFloat(lane - 1) * laneW }
    private func y(_ meters: Double) -> CGFloat { CGFloat(meters) * ppm }

    private func buildBackground(_ def: CityDefinition) {
        let p = def.palette
        let h = size.height + 40
        // Static strips are camera children: they never move.
        let sidewalkL = SKSpriteNode(color: p.sidewalk.uiColor, size: CGSize(width: laneW * 0.5, height: h))
        sidewalkL.position = CGPoint(x: x(lane: -0.5) - laneW * 0.25 - cameraXOffset, y: 0)
        let road = SKSpriteNode(color: p.road.uiColor, size: CGSize(width: laneW * 3, height: h))
        road.position = CGPoint(x: -cameraXOffset, y: 0)
        let parking = SKSpriteNode(color: p.road.blended(with: RGB(0x000000), 0.12),
                                   size: CGSize(width: laneW * 0.75, height: h))
        parking.position = CGPoint(x: x(lane: 2.5) + laneW * 0.375 - cameraXOffset, y: 0)
        let sidewalkR = SKSpriteNode(color: p.sidewalk.uiColor, size: CGSize(width: laneW * 0.5, height: h))
        sidewalkR.position = CGPoint(x: x(lane: 2.5) + laneW * 0.75 + laneW * 0.25 - cameraXOffset, y: 0)
        let curbL = SKSpriteNode(color: p.curb.uiColor, size: CGSize(width: 4, height: h))
        curbL.position = CGPoint(x: x(lane: -0.5) - cameraXOffset, y: 0)
        let edgeR = SKSpriteNode(color: p.laneMark.uiColor(alpha: 0.7), size: CGSize(width: 3, height: h))
        edgeR.position = CGPoint(x: x(lane: 2.5) - cameraXOffset, y: 0)
        let curbR = SKSpriteNode(color: p.curb.uiColor, size: CGSize(width: 4, height: h))
        curbR.position = CGPoint(x: x(lane: 2.5) + laneW * 0.75 - cameraXOffset, y: 0)
        for (i, node) in [sidewalkL, road, parking, sidewalkR, curbL, edgeR, curbR].enumerated() {
            node.zPosition = -100 + CGFloat(i) * 0.1
            cam.addChild(node)
        }
        // Buildings / greenery lots scroll with the world (pooled).
        let visibleMeters = Double(size.height / ppm)
        let lotCount = Int(visibleMeters / 10) + 3
        let leftWidth = max(20, size.width / 2 + x(lane: -0.5) - laneW * 0.5 - cameraXOffset + 0)
        let rightStart = x(lane: 2.5) + laneW * 1.25
        let rightWidth = max(20, size.width / 2 - (rightStart - cameraXOffset))
        for _ in 0..<lotCount {
            let l = SKSpriteNode(texture: tex("building0"), size: CGSize(width: leftWidth, height: y(10)))
            l.position.x = x(lane: -0.5) - laneW * 0.5 - leftWidth / 2
            l.zPosition = -50
            world.addChild(l)
            leftLots.append(l)
            let r = SKSpriteNode(texture: tex("building1"), size: CGSize(width: rightWidth, height: y(10)))
            r.position.x = rightStart + rightWidth / 2
            r.zPosition = -50
            world.addChild(r)
            rightLots.append(r)
        }
        let dashCount = (Int(visibleMeters / 6) + 3) * 2
        for i in 0..<dashCount {
            let d = SKSpriteNode(texture: tex("dash"))
            d.position.x = x(lane: i % 2 == 0 ? 0.5 : 1.5)
            d.zPosition = -40
            world.addChild(d)
            dashes.append(d)
        }
    }

    private func buildPlayer() {
        playerNode = SKSpriteNode(texture: tex("player"))
        playerNode.zPosition = 20
        world.addChild(playerNode)
        draftGlow = SKSpriteNode(color: config.signals.draft.uiColor(alpha: 0.35),
                                 size: CGSize(width: laneW * 0.5, height: y(4)))
        draftGlow.zPosition = 19
        draftGlow.isHidden = true
        world.addChild(draftGlow)
        for _ in 0..<8 {
            let line = SKSpriteNode(texture: tex("speedLine"))
            line.zPosition = 18
            line.isHidden = true
            world.addChild(line)
            speedLines.append(line)
        }
        for _ in 0..<10 {
            let pop = SKSpriteNode(texture: tex("particle"))
            pop.zPosition = 25
            pop.alpha = 0
            pop.color = config.signals.coin.uiColor
            pop.colorBlendFactor = 1
            world.addChild(pop)
            pops.append(pop)
        }
    }

    private func buildEffects(_ def: CityDefinition) {
        weatherTint.size = CGSize(width: size.width + 40, height: size.height + 40)
        weatherTint.zPosition = 60
        switch def.weather {
        case .rain: weatherTint.color = UIColor(red: 0.3, green: 0.4, blue: 0.55, alpha: 0.14)
        case .heat: weatherTint.color = UIColor(red: 1, green: 0.55, blue: 0.15, alpha: 0.1)
        case .sun: weatherTint.color = UIColor(red: 1, green: 0.9, blue: 0.5, alpha: 0.07)
        case .wind, .clear: weatherTint.color = .clear
        }
        cam.addChild(weatherTint)
        if (def.weather == .rain || def.weather == .wind) && !config.reduceMotion {
            var rng = SplitMix64(seed: 99)
            let count = def.weather == .rain ? 45 : 14
            for _ in 0..<count {
                let drop = SKSpriteNode(texture: tex("rain"))
                drop.zPosition = 61
                drop.position = CGPoint(x: rng.range(-0.5, 0.5) * Double(size.width),
                                        y: rng.range(-0.5, 0.5) * Double(size.height))
                if def.weather == .wind {
                    drop.zRotation = .pi / 2
                    drop.alpha = 0.35
                }
                cam.addChild(drop)
                rainDrops.append(drop)
            }
        }
        flash.size = CGSize(width: size.width + 40, height: size.height + 40)
        flash.alpha = 0
        flash.zPosition = 90
        flash.color = config.signals.hazard.uiColor
        cam.addChild(flash)
    }

    private func buildHUD() {
        hud.zPosition = 100
        cam.addChild(hud)
        let font = "AvenirNext-Heavy"
        let base = min(28, UIFontMetrics(forTextStyle: .headline).scaledValue(for: 18))
        for label in [timerLabel, coinLabel, comboLabel, toastLabel] {
            label.fontName = font
            label.fontColor = .white
            label.verticalAlignmentMode = .center
            hud.addChild(label)
        }
        timerLabel.fontSize = base
        coinLabel.fontSize = base
        comboLabel.fontSize = base * 1.3
        comboLabel.fontColor = config.signals.coin.uiColor
        comboLabel.alpha = 0
        toastLabel.fontSize = base
        toastLabel.alpha = 0
        progressFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        staminaFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        progressFill.color = CityCatalog.definition(for: config.level.city).palette.accent.uiColor
        for node in [progressBack, progressFill, staminaBack, staminaFill] { hud.addChild(node) }
        layoutHUD()
    }

    private func layoutHUD() {
        guard built else { return }
        let top = size.height / 2 - max(safeInsets.top, 20) - 18
        let bottom = -size.height / 2 + max(safeInsets.bottom, 16) + 18
        let barW = size.width * 0.5
        progressBack.size = CGSize(width: barW, height: 8)
        progressBack.position = CGPoint(x: 0, y: top)
        progressFill.size = CGSize(width: barW, height: 8)
        progressFill.position = CGPoint(x: -barW / 2, y: top)
        timerLabel.horizontalAlignmentMode = .left
        timerLabel.position = CGPoint(x: -size.width / 2 + 16, y: top - 30)
        // Left column: the SwiftUI pause button owns the top-right corner.
        coinLabel.horizontalAlignmentMode = .left
        coinLabel.position = CGPoint(x: -size.width / 2 + 16, y: top - 30 - timerLabel.fontSize * 1.3)
        comboLabel.position = CGPoint(x: 0, y: top - 70)
        toastLabel.position = CGPoint(x: 0, y: top - 105)
        let stamW = size.width * 0.35
        staminaBack.size = CGSize(width: stamW, height: 10)
        staminaFill.size = CGSize(width: stamW, height: 10)
        let sx = config.leftHandedHUD ? size.width / 2 - 16 - stamW : -size.width / 2 + 16
        staminaBack.position = CGPoint(x: sx + stamW / 2, y: bottom)
        staminaFill.position = CGPoint(x: sx, y: bottom)
    }

    // MARK: - Pools

    private func resetEntityNodes() {
        if !entityNodes.isEmpty {
            for i in entityNodes.indices { release(i) }
        }
        entityNodes = Array(repeating: nil, count: sim.entities.count)
        releasedUpTo = 0
    }

    private func prewarmPools() {
        let counts: [EntityKind: Int] = [.coin: 24, .car: 6, .pedestrian: 4, .scooter: 4, .cyclist: 4, .pothole: 4,
                                         .construction: 3, .bus: 2, .parkedCarDoor: 2, .trafficLight: 2,
                                         .water: 2, .tramTracks: 1, .cobblestones: 1]
        for (kind, count) in counts {
            for _ in 0..<count {
                let node = makeNode(kind)
                node.isHidden = true
                world.addChild(node)
                pools[Int(kind.rawValue)].append(node)
            }
        }
    }

    private func acquire(_ kind: EntityKind) -> SKNode {
        let k = Int(kind.rawValue)
        if let node = pools[k].popLast() {
            node.isHidden = false
            return node
        }
        let node = makeNode(kind)
        world.addChild(node)
        return node
    }

    private func release(_ i: Int) {
        guard i < entityNodes.count, let node = entityNodes[i] else { return }
        node.isHidden = true
        node.removeAllActions()
        pools[Int(sim.entities[i].kind.rawValue)].append(node)
        entityNodes[i] = nil
    }

    private func makeNode(_ kind: EntityKind) -> SKNode {
        switch kind {
        case .parkedCarDoor:
            let container = SKNode()
            let car = SKSpriteNode(texture: tex("parked0"))
            car.name = "car"
            let door = SKSpriteNode(texture: tex("door"))
            door.anchorPoint = CGPoint(x: 1, y: 0.5)
            door.name = "door"
            door.zPosition = 1
            container.addChild(car)
            container.addChild(door)
            container.zPosition = 6
            return container
        case .trafficLight:
            let container = SKNode()
            let line = SKSpriteNode(texture: tex("stopLine"))
            line.name = "line"
            let head = SKSpriteNode(texture: tex("lightGo"))
            head.name = "head"
            head.position = CGPoint(x: x(lane: -0.5) - laneW * 0.25, y: head.size.height / 2)
            head.zPosition = 30
            let zone = SKSpriteNode(color: config.signals.lightStop.uiColor(alpha: 0.18),
                                    size: CGSize(width: laneW * 3, height: y(6)))
            zone.name = "zone"
            zone.position = CGPoint(x: x(lane: 1) , y: -y(3))
            container.addChild(zone)
            container.addChild(line)
            container.addChild(head)
            container.zPosition = 2
            return container
        case .cobblestones:
            let container = SKNode()
            for _ in 0..<20 {
                let tile = SKSpriteNode(texture: tex("cobbleTile"))
                tile.isHidden = true
                container.addChild(tile)
            }
            container.zPosition = -30
            return container
        case .car, .bus, .scooter, .cyclist:
            let sprite = SKSpriteNode(texture: tex(kind == .cyclist ? "cyclist0" : "car0"))
            let left = SKSpriteNode(texture: tex("signal"))
            left.name = "signalL"
            let right = SKSpriteNode(texture: tex("signal"))
            right.name = "signalR"
            left.zPosition = 1
            right.zPosition = 1
            sprite.addChild(left)
            sprite.addChild(right)
            sprite.zPosition = kind == .bus ? 9 : 8
            return sprite
        case .tramTracks:
            let sprite = SKSpriteNode(texture: tex("tram0"))
            sprite.zPosition = -30
            return sprite
        case .pothole:
            let sprite = SKSpriteNode(texture: tex("pothole0"))
            sprite.zPosition = -20
            return sprite
        case .coin, .water:
            let sprite = SKSpriteNode(texture: tex(kind == .coin ? "coin" : "water"))
            sprite.zPosition = 5
            return sprite
        case .construction:
            let sprite = SKSpriteNode(texture: tex("construction"))
            sprite.zPosition = 7
            return sprite
        case .pedestrian:
            let sprite = SKSpriteNode(texture: tex("ped0"))
            sprite.zPosition = 10
            return sprite
        }
    }

    /// One-time configuration when a node is attached to an entity.
    private func configure(_ node: SKNode, for e: EntityState) {
        let vehicleCount = CityCatalog.definition(for: config.level.city).palette.vehicles.count
        let v = Int(e.variant)
        switch e.kind {
        case .car, .bus, .scooter:
            guard let s = node as? SKSpriteNode else { return }
            let prefix = e.kind == .car ? "car" : (e.kind == .bus ? "bus" : "scooter")
            s.texture = tex("\(prefix)\(v % vehicleCount)")
            s.size = CGSize(width: laneW * CGFloat(e.width), height: y(e.length))
            positionSignals(s)
        case .cyclist:
            guard let s = node as? SKSpriteNode else { return }
            s.texture = tex("cyclist\(v % 6)")
            s.size = CGSize(width: laneW * CGFloat(e.width), height: y(e.length))
            positionSignals(s)
        case .parkedCarDoor:
            if let car = node.childNode(withName: "car") as? SKSpriteNode {
                car.texture = tex("parked\(v % vehicleCount)")
                car.size = CGSize(width: laneW * 0.62, height: y(4.4))
                // Car sits in the parking strip; its driver door is at the hinge.
                car.position = CGPoint(x: laneW * 0.31 + 2, y: -y(1.6))
            }
            if let door = node.childNode(withName: "door") as? SKSpriteNode {
                door.size = CGSize(width: laneW * CGFloat(e.width), height: max(6, y(0.25)))
                door.position = .zero
            }
        case .construction:
            (node as? SKSpriteNode)?.size = CGSize(width: laneW * CGFloat(e.width), height: y(e.length))
        case .tramTracks:
            guard let s = node as? SKSpriteNode else { return }
            s.texture = tex(e.variant % 2 == 0 ? "tram0" : "tram1")
            s.size = CGSize(width: laneW * 3, height: y(e.length))
        case .pothole:
            guard let s = node as? SKSpriteNode else { return }
            s.texture = tex("pothole\(v % 3)")
            s.size = CGSize(width: laneW * CGFloat(e.width), height: y(e.length))
        case .pedestrian:
            guard let s = node as? SKSpriteNode else { return }
            s.texture = tex("ped\(v % 6)")
            s.size = CGSize(width: laneW * CGFloat(e.width), height: y(0.8))
            s.zRotation = e.param > 0 ? -.pi / 2 : .pi / 2
        case .cobblestones:
            let tileH = y(4)
            let count = min(node.children.count, Int((e.length / 4).rounded(.up)))
            for (k, tile) in node.children.enumerated() {
                tile.isHidden = k >= count
                (tile as? SKSpriteNode)?.size = CGSize(width: laneW * 3, height: tileH)
                tile.position = CGPoint(x: 0, y: -y(e.length) / 2 + tileH * (CGFloat(k) + 0.5))
            }
        case .trafficLight:
            if let line = node.childNode(withName: "line") as? SKSpriteNode {
                line.position = CGPoint(x: x(lane: 1), y: 0)
            }
        case .coin, .water:
            node.setScale(1)
            node.alpha = 1
        }
    }

    private func positionSignals(_ s: SKSpriteNode) {
        let h = s.size.height / 2 - 4
        s.childNode(withName: "signalL")?.position = CGPoint(x: -s.size.width / 2, y: h)
        s.childNode(withName: "signalR")?.position = CGPoint(x: s.size.width / 2, y: h)
    }

    // MARK: - Loop

    override func update(_ currentTime: TimeInterval) {
        guard built else { return }
        if isFrozen {
            lastUpdate = currentTime
            return
        }
        let frame = min(0.1, max(0, currentTime - (lastUpdate ?? currentTime)))
        lastUpdate = currentTime
        elapsed += frame

        if crashTimer > 0 {
            crashTimer -= frame
            if crashTimer <= 0 { restart(countAttempt: true) }
        } else if sim.isRunning {
            accumulator += frame
            var steps = 0
            while accumulator >= GameScene.fixedStep && steps < 12 && sim.isRunning {
                sim.step(GameScene.fixedStep)
                sim.drainEvents(handle)
                accumulator -= GameScene.fixedStep
                steps += 1
            }
            if steps == 12 { accumulator = 0 }
        }
        render()
        updateEffects(frame)
    }

    /// Call after unpausing so the paused interval is not simulated.
    func resetClock() {
        lastUpdate = nil
        accumulator = 0
    }

    private func handle(_ event: GameEvent) {
        switch event {
        case .coin(let i):
            sound?.play(.coin)
            haptics?.play(.coin)
            pop(at: sim.entities[i])
        case .water(let i):
            sound?.play(.water)
            haptics?.play(.coin)
            pop(at: sim.entities[i])
            toast(String(localized: "Refreshed!"))
        case .nearMiss(let combo, _):
            sound?.play(.nearMiss)
            haptics?.play(.nearMiss(combo))
            comboLabel.text = combo > 1 ? String(localized: "Near miss ×\(combo)") : String(localized: "Near miss!")
            comboLabel.removeAllActions()
            comboLabel.alpha = 1
            if !config.reduceMotion { comboLabel.run(comboPulse) }
        case .comboEnded:
            comboLabel.run(.fadeOut(withDuration: 0.3))
        case .pothole:
            sound?.play(.penalty)
            haptics?.play(.bump)
            shake = config.reduceMotion ? 0 : 0.2
            toast(String(localized: "Pothole!"))
        case .ranRedLight:
            sound?.play(.penalty)
            haptics?.play(.warning)
            toast(String(localized: "Red light +3s"))
        case .laneChange:
            haptics?.play(.laneChange)
        case .sprintStarted:
            sound?.play(.whoosh)
        case .brakeApplied:
            break
        case .draftStarted:
            toast(String(localized: "Slipstream"))
        case .draftBoost:
            sound?.play(.boost)
            haptics?.play(.bump)
            toast(String(localized: "Slingshot!"))
        case .enteredCobbles:
            haptics?.play(.bump)
            toast(String(localized: "Cobblestones"))
        case .crashed:
            sound?.play(.crash)
            haptics?.play(.crash)
            crashTimer = GameScene.crashFreeze
            shake = config.reduceMotion ? 0 : 0.35
            flash.removeAllActions()
            if config.reduceMotion { flash.alpha = 0.3 } else { flash.run(flashAction) }
            gameDelegate?.gameSceneDidCrash(distance: sim.player.y, nearMisses: sim.nearMisses, drafts: sim.draftBoosts)
        case .finished:
            guard !finishedReported else { return }
            finishedReported = true
            sound?.play(.finish)
            haptics?.play(.success)
            gameDelegate?.gameSceneDidFinish(sim.makeResult(crashesBeforeFinish: attempts))
        }
    }

    /// Instant restart of the same level (well under one second after a crash).
    func restart(countAttempt: Bool) {
        if countAttempt { attempts += 1 }
        sim = GameSimulation(level: config.level, assist: config.assist)
        crashTimer = 0
        accumulator = 0
        finishedReported = false
        flash.removeAllActions()
        flash.alpha = 0
        comboLabel.alpha = 0
        toastLabel.alpha = 0
        shownTenths = -1
        shownCoins = -1
        resetEntityNodes()
        render()
    }

    /// Full reset including the attempt counter (Retry from the menu).
    func restartFresh() {
        attempts = 0
        restart(countAttempt: false)
    }

    // MARK: - Rendering

    private func render() {
        guard built else { return }
        let p = sim.player
        let camY = y(p.y) - playerScreenOffset
        var shakeX: CGFloat = 0
        if shake > 0 {
            shakeX = CGFloat(sin(elapsed * 90) * shake * 10)
        }
        cam.position = CGPoint(x: cameraXOffset + shakeX, y: camY)
        let bottomM = Double((camY - size.height / 2) / ppm) - 2
        let topM = Double((camY + size.height / 2) / ppm) + 2

        // Player
        playerNode.position = CGPoint(x: x(lane: p.x), y: y(p.y - 0.95))
        let lean = Double(p.targetLane) - p.x
        playerNode.zRotation = CGFloat(-lean * 0.35)
        if sim.isDrafting {
            draftGlow.isHidden = false
            draftGlow.position = CGPoint(x: playerNode.position.x, y: playerNode.position.y + y(1.5))
            draftGlow.alpha = CGFloat(0.4 + p.draftCharge * 0.6)
        } else {
            draftGlow.isHidden = true
        }

        // Scrolling decor
        let dashStart = Int((bottomM / 6).rounded(.down))
        let perDivider = dashes.count / 2
        for (k, d) in dashes.enumerated() {
            d.position.y = y(Double(dashStart + k / 2) * 6)
            d.isHidden = k / 2 >= perDivider
        }
        let lotStart = Int((bottomM / 10).rounded(.down))
        for k in 0..<leftLots.count {
            let n = lotStart + k
            let ly = y(Double(n) * 10 + 5)
            updateLot(leftLots[k], index: n, side: 0, y: ly)
            updateLot(rightLots[k], index: n, side: 1, y: ly)
        }

        // Release nodes for entities the simulation has left behind.
        while releasedUpTo < sim.lowIndex {
            release(releasedUpTo)
            releasedUpTo += 1
        }
        // Entities in the active window
        var i = sim.lowIndex
        while i < sim.highIndex {
            let e = sim.entities[i]
            let visible = e.phase != .gone && e.y + e.length > bottomM && e.y < topM
            if !visible {
                release(i)
            } else {
                let node: SKNode
                if let existing = entityNodes[i] {
                    node = existing
                } else {
                    node = acquire(e.kind)
                    configure(node, for: e)
                    entityNodes[i] = node
                }
                place(node, e)
            }
            i += 1
        }

        // HUD
        let tenths = Int(sim.totalTime * 10)
        if tenths != shownTenths {
            shownTenths = tenths
            let total = tenths / 10
            timerLabel.text = String(format: "%d:%02d.%d", total / 60, total % 60, tenths % 10)
            timerLabel.fontColor = sim.totalTime > sim.parTime ? config.signals.lightStop.uiColor : .white
        }
        if sim.coins != shownCoins {
            shownCoins = sim.coins
            coinLabel.text = "● \(sim.coins)/\(config.level.coinCount(assist: config.assist))"
        }
        progressFill.xScale = CGFloat(max(0.001, sim.progress))
        staminaFill.xScale = CGFloat(max(0.001, p.stamina))
        staminaFill.color = p.stamina < GameTuning.standard.minimumSprintStamina
            ? config.signals.lightStop.uiColor : config.signals.water.uiColor
    }

    private func updateLot(_ node: SKSpriteNode, index n: Int, side: Int, y ly: CGFloat) {
        node.position.y = ly
        // Deterministic per-lot variation; side streets every 6th lot.
        let h = (UInt64(bitPattern: Int64(n)) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(side) &* 0xBF58_476D_1CE4_E5B9) >> 33
        if n % 6 == 5 {
            node.isHidden = true
            return
        }
        node.isHidden = false
        let variant = Int(h % 11)
        let name = variant >= TextureFactory.buildingVariants ? "tree" : "building\(variant)"
        node.texture = tex(name)
    }

    private func place(_ node: SKNode, _ e: EntityState) {
        let cx = x(lane: e.lane)
        let cy = y(e.y + e.length / 2)
        switch e.kind {
        case .car, .bus, .scooter, .cyclist:
            node.position = CGPoint(x: cx, y: cy)
            var rot: CGFloat = 0
            if e.phase == .active && e.swerve != 0 && !e.isSignalling {
                let remaining = (e.spawnLane + e.swerve) - e.lane
                rot = abs(remaining) > 0.01 ? (remaining > 0 ? -0.25 : 0.25) : 0
            } else if e.phase == .exiting && e.travelled >= e.travel {
                rot = CGFloat(-e.exitDirection * 0.6)
            }
            node.zRotation = rot
            let blink = e.isSignalling && Int(elapsed * 6) % 2 == 0
            node.childNode(withName: "signalL")?.isHidden = !(blink && e.swerve < 0)
            node.childNode(withName: "signalR")?.isHidden = !(blink && e.swerve > 0)
        case .parkedCarDoor:
            node.position = CGPoint(x: x(lane: e.spawnLane), y: y(e.y + e.length / 2))
            node.childNode(withName: "door")?.zRotation = CGFloat(-Double.pi / 2 * (1 - e.openAmount))
        case .trafficLight:
            node.position = CGPoint(x: 0, y: y(e.y))
            let phase = sim.lightPhase(of: e)
            if let head = node.childNode(withName: "head") as? SKSpriteNode {
                head.texture = tex(phase == .go ? "lightGo" : (phase == .caution ? "lightCaution" : "lightStop"))
            }
            node.childNode(withName: "zone")?.isHidden = phase == .go || e.passed
        case .coin:
            node.position = CGPoint(x: cx, y: cy)
            if !config.reduceMotion { node.xScale = CGFloat(abs(cos(elapsed * 3 + e.spawnY))) * 0.6 + 0.4 }
        case .tramTracks, .cobblestones:
            node.position = CGPoint(x: 0, y: cy)
        default:
            node.position = CGPoint(x: cx, y: cy)
        }
    }

    private func updateEffects(_ frame: Double) {
        if shake > 0 { shake = max(0, shake - frame) }
        // Rain / wind streaks (camera space).
        if !rainDrops.isEmpty {
            let isWind = config.level.weather == .wind
            let speed = CGFloat(frame) * (isWind ? 900 : 1100)
            let halfW = size.width / 2 + 20, halfH = size.height / 2 + 20
            for d in rainDrops {
                if isWind {
                    d.position.x -= speed
                    if d.position.x < -halfW { d.position.x = halfW }
                } else {
                    d.position.y -= speed
                    d.position.x -= speed * 0.12
                    if d.position.y < -halfH { d.position.y = halfH; d.position.x += CGFloat(frame) * 4000 }
                    if d.position.x < -halfW { d.position.x += halfW * 2 }
                    if d.position.x > halfW { d.position.x -= halfW * 2 }
                }
            }
        }
        // Speed lines while sprinting or boosting.
        let fast = sim.player.isSprinting || sim.player.boostTimer > 0
        for (k, line) in speedLines.enumerated() {
            line.isHidden = !fast || config.reduceMotion
            guard !line.isHidden else { continue }
            let phase = (elapsed * 3 + Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
            let side: Double = k % 2 == 0 ? -0.35 : 0.35
            line.position = CGPoint(x: x(lane: sim.player.x + side * Double(1 + k % 3) * 0.6),
                                    y: y(sim.player.y - 1 - phase * 6))
            line.alpha = CGFloat(1 - phase)
        }
    }

    private func pop(at e: EntityState) {
        guard !pops.isEmpty else { return }
        let node = pops[nextPop]
        nextPop = (nextPop + 1) % pops.count
        node.removeAllActions()
        node.position = CGPoint(x: x(lane: e.lane), y: y(e.y + e.length / 2))
        node.setScale(1)
        node.alpha = 0.9
        node.color = e.kind == .coin ? config.signals.coin.uiColor : config.signals.water.uiColor
        if config.reduceMotion {
            node.alpha = 0
        } else {
            node.run(popAction)
        }
    }

    private func toast(_ text: String) {
        toastLabel.text = text
        toastLabel.removeAllActions()
        toastLabel.alpha = 0
        toastLabel.run(toastAction)
    }

    // MARK: - Input

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isFrozen, let t = touches.first else { return }
        touchStart = t.location(in: view)
        touchStartTime = t.timestamp
        touchConsumed = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let start = touchStart else { return }
        let p = t.location(in: view)
        let dx = p.x - start.x
        let dy = p.y - start.y // UIKit space: positive = downwards
        let threshold: CGFloat = 22
        if abs(dx) > threshold && abs(dx) > abs(dy) {
            sim.send(dx < 0 ? .moveLeft : .moveRight)
            // Allow chaining two lane changes in one drag.
            touchStart = p
            touchConsumed = true
        } else if dy > threshold * 1.4 && abs(dy) > abs(dx) * 1.2 && !touchConsumed {
            sim.send(.brake)
            touchConsumed = true
        } else if dy < -threshold && abs(dy) > abs(dx) {
            touchConsumed = true // swipe up: ignored, but not a tap
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        defer { touchStart = nil }
        if !touchConsumed && t.timestamp - touchStartTime < 0.35 {
            sim.send(.sprint)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStart = nil
    }

    // MARK: - Accessibility / testing hooks

    /// Keyboard / Switch Control / UI-test entry point for the same commands.
    func perform(_ command: PlayerCommand) {
        guard !isFrozen else { return }
        sim.send(command)
    }
}

import Foundation
import Observation
import SpriteKit
import CitySprintCore

/// Bridges the SpriteKit scene and the SwiftUI overlays (pause, results).
@MainActor
@Observable
final class GameViewModel: GameSceneDelegate {
    enum Phase: Equatable {
        case playing
        case paused
        case finished(RunResult, RecordOutcome)
    }

    private(set) var phase: Phase = .playing
    private(set) var attempts = 0
    private(set) var showTutorial: Bool
    let level: LevelDefinition
    let scene: GameScene
    private let app: AppModel

    init(level: LevelDefinition, app: AppModel) {
        self.level = level
        self.app = app
        let config = GameSceneConfig(
            level: level, assist: app.settings.assistMode, signals: app.signalPalette,
            reduceMotion: app.reduceMotion, bike: app.item(for: .bike), jersey: app.item(for: .jersey),
            helmet: app.item(for: .helmet), leftHandedHUD: app.settings.leftHandedHUD)
        scene = GameScene(config: config)
        showTutorial = level.index == 0 && level.city == .newYork && app.progress.stats.finishes == 0
        scene.gameDelegate = self
        scene.haptics = app.haptics
        scene.sound = app.sound
    }

    var title: String {
        level.isDaily ? String(localized: "Daily Challenge") : "\(level.city.displayName) \(level.index + 1)"
    }

    func pause() {
        guard phase == .playing else { return }
        scene.isPaused = true
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        scene.resetClock()
        scene.isPaused = false
        phase = .playing
    }

    func retry() {
        scene.restartFresh()
        attempts = 0
        scene.resetClock()
        scene.isPaused = false
        phase = .playing
    }

    func dismissTutorial() {
        scene.resetClock()
        showTutorial = false
    }

    func nextLevel() -> (CityID, Int)? {
        app.nextLevel(after: level.id)
    }

    // MARK: GameSceneDelegate

    func gameSceneDidFinish(_ result: RunResult) {
        let outcome = app.record(result)
        scene.isPaused = true
        phase = .finished(result, outcome)
        if outcome.stars > 0 { app.sound.play(.star) }
    }

    func gameSceneDidCrash(distance: Double, nearMisses: Int, drafts: Int) {
        attempts += 1
        showTutorial = false
        app.recordCrash(distance: distance, nearMisses: nearMisses, drafts: drafts)
    }
}

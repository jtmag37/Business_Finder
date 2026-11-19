import Foundation
import Observation
import SwiftUI
import UIKit
import CitySprintCore

/// A level the player has chosen to ride.
struct GameLaunch: Identifiable, Equatable {
    let id = UUID()
    let level: LevelDefinition

    static func == (lhs: GameLaunch, rhs: GameLaunch) -> Bool { lhs.id == rhs.id }
}

enum Route: Hashable {
    case worldMap
    case city(CityID)
    case daily
    case garage
    case settings
}

/// App-wide state: progress, settings and the Apple-service integrations.
@MainActor
@Observable
final class AppModel {
    private(set) var progress: PlayerProgress
    var settings: GameSettings {
        didSet {
            guard settings != oldValue else { return }
            settingsStore.save(settings)
            applySettings()
            if settings.iCloudSync && !oldValue.iCloudSync { syncWithCloud() }
        }
    }
    var path: [Route] = []
    var activeGame: GameLaunch?
    private(set) var lastSyncError: Bool = false

    let store: StoreService
    let gameCenter: GameCenterService
    let haptics = HapticsService()
    let sound = SoundService()

    private let progressStore: ProgressStoring
    private let settingsStore: SettingsStore
    private let cloud: CloudSyncService
    private var syncTask: Task<Void, Never>?

    init(progressStore: ProgressStoring? = nil, settingsStore: SettingsStore = SettingsStore(),
         store: StoreService? = nil, gameCenter: GameCenterService? = nil, cloud: CloudSyncService? = nil) {
        let resolvedStore: ProgressStoring
        if let progressStore {
            resolvedStore = progressStore
        } else if AppConfig.isUITesting || AppConfig.isUnitTesting {
            resolvedStore = InMemoryProgressStore()
        } else if let url = try? FileProgressStore.defaultURL() {
            resolvedStore = FileProgressStore(url: url)
        } else {
            resolvedStore = InMemoryProgressStore()
        }
        self.progressStore = resolvedStore
        self.settingsStore = AppConfig.isUITesting ? SettingsStore(defaults: UserDefaults(suiteName: "uitests") ?? .standard)
                                                   : settingsStore
        if AppConfig.isUITesting { UserDefaults(suiteName: "uitests")?.removePersistentDomain(forName: "uitests") }
        self.settings = self.settingsStore.load()
        self.progress = (try? resolvedStore.load()) ?? PlayerProgress(now: Date())
        self.store = store ?? StoreService()
        self.gameCenter = gameCenter ?? GameCenterService()
        self.cloud = cloud ?? CloudSyncService()
        if let stars = AppConfig.seededStars { seed(stars: stars) }
        applySettings()
    }

    // MARK: Lifecycle

    func onLaunch() {
        sound.start()
        haptics.prepare()
        store.start()
        gameCenter.authenticate()
        syncWithCloud()
    }

    func onBackground() {
        save()
        syncWithCloud()
    }

    // MARK: Derived state

    var isSupporter: Bool { store.isSupporter }

    var reduceMotion: Bool { settings.reduceMotion || UIAccessibility.isReduceMotionEnabled }

    var signalPalette: SignalPalette { settings.colorblindSignals ? .colorblindSafe : .standard }

    func isCityUnlocked(_ city: CityID) -> Bool { ProgressionRules.isCityUnlocked(city, in: progress) }

    func isLevelUnlocked(_ city: CityID, _ index: Int) -> Bool {
        ProgressionRules.isLevelUnlocked(city: city, index: index, in: progress)
    }

    func item(for slot: CosmeticSlot) -> CosmeticItem {
        CosmeticCatalog.resolvedItem(for: slot, loadout: progress.loadout, progress: progress, isSupporter: isSupporter)
    }

    var todayKey: Int { DailyChallenge.dayKey(for: Date()) }

    // MARK: Play

    func play(city: CityID, index: Int) {
        guard isLevelUnlocked(city, index) else { return }
        let level = AppConfig.isUITesting ? LevelGenerator.uiTestLevel(city: city) : LevelGenerator.level(city: city, index: index)
        activeGame = GameLaunch(level: level)
    }

    func playDaily() {
        let level = AppConfig.isUITesting ? LevelGenerator.uiTestLevel(daily: true) : DailyChallenge.level(for: Date())
        activeGame = GameLaunch(level: level)
    }

    /// Records a finished run and pushes scores/achievements to Game Center.
    func record(_ result: RunResult) -> RecordOutcome {
        let outcome = progress.record(result, isSupporter: isSupporter)
        save()
        if result.finished && !result.assisted {
            // Assisted runs still earn stars and unlocks, but leaderboards
            // only compare unassisted rides so they stay fair.
            if result.isDaily {
                gameCenter.submit(score: result.score, to: LeaderboardIDs.daily)
            } else {
                gameCenter.submit(score: progress.cityScore(result.city), to: LeaderboardIDs.city(result.city))
            }
        }
        gameCenter.report(achievements: AchievementCatalog.percentages(in: progress))
        scheduleSync()
        return outcome
    }

    func recordCrash(distance: Double, nearMisses: Int, drafts: Int) {
        progress.recordCrash(distance: distance, nearMisses: nearMisses, drafts: drafts)
        // Saved lazily (next finish / background) to keep restarts instant.
    }

    func nextLevel(after id: LevelID) -> (CityID, Int)? {
        ProgressionRules.nextLevel(after: id, in: progress)
    }

    // MARK: Cosmetics

    @discardableResult
    func equip(_ item: CosmeticItem) -> Bool {
        let ok = progress.equip(item, isSupporter: isSupporter)
        if ok {
            save()
            haptics.play(.select)
            scheduleSync()
        }
        return ok
    }

    // MARK: Persistence

    func save() {
        try? progressStore.save(progress)
    }

    func resetProgress() {
        progress = PlayerProgress(now: Date())
        try? progressStore.reset()
        save()
        if settings.iCloudSync {
            Task { try? await cloud.deleteCloudCopy() }
        }
    }

    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.syncWithCloud()
        }
    }

    func syncWithCloud() {
        guard settings.iCloudSync, AppConfig.appleServicesEnabled else { return }
        let local = progress
        Task { [weak self, cloud] in
            do {
                let merged = try await cloud.sync(local: local)
                guard let self else { return }
                // Merge again in case progress changed while syncing.
                let combined = ProgressMerge.merge(self.progress, merged)
                if combined != self.progress {
                    self.progress = combined
                    self.save()
                }
                self.lastSyncError = false
            } catch {
                self?.lastSyncError = true
            }
        }
    }

    private func applySettings() {
        haptics.isEnabled = settings.haptics
        sound.isEnabled = settings.soundEffects
    }

    private func seed(stars: Int) {
        var remaining = stars
        for city in CityID.allCases {
            for index in 0..<LevelGenerator.levelsPerCity where remaining > 0 {
                let s = min(3, remaining)
                progress.levels[LevelID.city(city, index: index).rawValue] =
                    LevelRecord(bestStars: s, bestTime: 60, bestScore: 500, completions: 1)
                remaining -= s
            }
        }
    }
}

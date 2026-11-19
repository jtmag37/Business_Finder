import Foundation
import GameKit
import Observation
import UIKit

/// Game Center: leaderboards per city + daily, achievements. Fully optional:
/// the game works the same when the player is signed out or offline. Score
/// submissions made while unavailable are queued (scores only, no personal
/// data) and retried later.
@MainActor
@Observable
final class GameCenterService {
    private(set) var isAuthenticated = false
    private let enabled: Bool
    private let defaults: UserDefaults
    private let queueKey = "citysprint.gc.pendingScores"

    private struct PendingScore: Codable, Equatable {
        var leaderboardID: String
        var score: Int
    }

    init(enabled: Bool = AppConfig.appleServicesEnabled, defaults: UserDefaults = .standard) {
        self.enabled = enabled
        self.defaults = defaults
    }

    func authenticate() {
        guard enabled else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, _ in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    Self.topViewController()?.present(viewController, animated: true)
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if self.isAuthenticated {
                    GKAccessPoint.shared.location = .topLeading
                    await self.flushPending()
                }
            }
        }
    }

    func setAccessPointVisible(_ visible: Bool) {
        guard enabled, isAuthenticated else { return }
        GKAccessPoint.shared.isActive = visible
    }

    func submit(score: Int, to leaderboardID: String) {
        guard enabled, score > 0 else { return }
        var pending = loadPending()
        if let i = pending.firstIndex(where: { $0.leaderboardID == leaderboardID }) {
            pending[i].score = max(pending[i].score, score)
        } else {
            pending.append(PendingScore(leaderboardID: leaderboardID, score: score))
        }
        savePending(pending)
        Task { await flushPending() }
    }

    func report(achievements: [(id: String, percent: Double)]) {
        guard enabled, isAuthenticated else { return }
        let items = achievements.filter { $0.percent > 0 }.map { entry -> GKAchievement in
            let a = GKAchievement(identifier: entry.id)
            a.percentComplete = min(100, entry.percent)
            a.showsCompletionBanner = true
            return a
        }
        guard !items.isEmpty else { return }
        GKAchievement.report(items) { _ in }
    }

    func showDashboard(leaderboardID: String? = nil) {
        guard enabled, isAuthenticated else { return }
        let vc: GKGameCenterViewController
        if let leaderboardID {
            vc = GKGameCenterViewController(leaderboardID: leaderboardID, playerScope: .global, timeScope: .allTime)
        } else {
            vc = GKGameCenterViewController(state: .dashboard)
        }
        vc.gameCenterDelegate = DashboardDismisser.shared
        Self.topViewController()?.present(vc, animated: true)
    }

    func showAchievements() {
        guard enabled, isAuthenticated else { return }
        let vc = GKGameCenterViewController(state: .achievements)
        vc.gameCenterDelegate = DashboardDismisser.shared
        Self.topViewController()?.present(vc, animated: true)
    }

    private func flushPending() async {
        guard isAuthenticated else { return }
        var remaining: [PendingScore] = []
        for item in loadPending() {
            do {
                try await GKLeaderboard.submitScore(item.score, context: 0, player: GKLocalPlayer.local,
                                                    leaderboardIDs: [item.leaderboardID])
            } catch {
                remaining.append(item)
            }
        }
        savePending(remaining)
    }

    private func loadPending() -> [PendingScore] {
        guard let data = defaults.data(forKey: queueKey) else { return [] }
        return (try? JSONDecoder().decode([PendingScore].self, from: data)) ?? []
    }

    private func savePending(_ items: [PendingScore]) {
        defaults.set(try? JSONEncoder().encode(Array(items.suffix(32))), forKey: queueKey)
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

private final class DashboardDismisser: NSObject, GKGameCenterControllerDelegate {
    static let shared = DashboardDismisser()

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        gameCenterViewController.dismiss(animated: true)
    }
}

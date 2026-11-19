import SwiftUI
import CitySprintCore

struct ResultsView: View {
    let result: RunResult
    let outcome: RecordOutcome
    let attempts: Int
    let hasNext: Bool
    let onRetry: () -> Void
    let onNext: () -> Void
    let onExit: () -> Void

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(AppModel.self) private var app
    @State private var revealed = 0

    private var reduceMotion: Bool { systemReduceMotion || app.settings.reduceMotion }

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text("Finished!")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("resultsTitle")
                    stars
                    statsGrid
                    breakdown
                    unlocks
                    buttons
                }
                .padding(24)
                .frame(maxWidth: 420)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                .padding()
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .task { await revealStars() }
    }

    private var stars: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < revealed ? "star.fill" : "star")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(i < revealed ? Color.yellow : Color.secondary)
                    .scaleEffect(i < revealed && !reduceMotion ? 1.0 : 0.9)
                    .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.5), value: revealed)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(outcome.stars) of 3 stars"))
        .accessibilityIdentifier("resultStars")
    }

    private var statsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Label("Time", systemImage: "stopwatch")
                Text(formatTime(result.time)).bold()
                    + Text(" / ") + Text(formatTime(result.parTime)).foregroundColor(.secondary)
            }
            GridRow {
                Label("Coins", systemImage: "circle.circle")
                Text("\(result.coins) (need \(result.coinsForStar))").bold()
            }
            GridRow {
                Label("Near misses", systemImage: "bolt.horizontal")
                Text("\(result.nearMisses) · best combo ×\(result.maxCombo)").bold()
            }
            if !result.isClean {
                GridRow {
                    Label("Penalties", systemImage: "exclamationmark.triangle")
                    Text("\(result.potholeHits) potholes · \(result.redLightsRun) red lights").bold()
                }
            }
            if attempts > 0 {
                GridRow {
                    Label("Attempts", systemImage: "arrow.counterclockwise")
                    Text("\(attempts + 1)").bold()
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var breakdown: some View {
        let b = result.breakdown
        return VStack(spacing: 4) {
            Text("Score \(b.total)")
                .font(.title.bold().monospacedDigit())
                .accessibilityIdentifier("resultScore")
            Text("Coins \(b.coinPoints) · Combos \(b.comboPoints) · Time \(b.timeBonus) · Clean \(b.cleanBonus)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if outcome.isNewBestScore {
                Text("New best!").font(.headline).foregroundStyle(.orange)
            }
            if result.assisted {
                Text("Assist mode: leaderboards only include unassisted rides.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var unlocks: some View {
        let cosmetics = outcome.newlyUnlockedCosmetics.compactMap(CosmeticCatalog.item(id:))
        if !outcome.newlyUnlockedCities.isEmpty || !cosmetics.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(outcome.newlyUnlockedCities) { city in
                    Label("\(city.displayName) unlocked!", systemImage: "lock.open.fill")
                }
                ForEach(cosmetics) { item in
                    Label("New \(item.displayName) in the Garage", systemImage: "gift.fill")
                }
            }
            .font(.headline)
            .foregroundStyle(.green)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if hasNext {
                Button("Next level", action: onNext)
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("nextLevelButton")
            }
            HStack(spacing: 10) {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("retryButton")
                Button(action: onExit) {
                    Label("Map", systemImage: "map").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("exitButton")
            }
        }
    }

    private func revealStars() async {
        if reduceMotion {
            revealed = outcome.stars
            return
        }
        for i in 0..<outcome.stars {
            try? await Task.sleep(for: .milliseconds(250))
            revealed = i + 1
            app.haptics.play(.select)
        }
    }
}

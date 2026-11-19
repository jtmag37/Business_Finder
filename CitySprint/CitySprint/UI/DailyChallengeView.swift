import SwiftUI
import CitySprintCore

struct DailyChallengeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let key = DailyChallenge.dayKey(for: context.date)
            let city = LevelGenerator.dailyCity(dayKey: key)
            let record = app.progress.dailyRecord(dayKey: key)
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("Today's ride").font(.headline).foregroundStyle(.secondary)
                        Text(city.displayName).font(.largeTitle.bold())
                        Label(city.weather.label, systemImage: city.weather.symbol)
                    }
                    Text("One seeded course per day — the same for every rider in the world. Resets at midnight UTC.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Label("Resets in \(countdown(DailyChallenge.secondsUntilReset(from: context.date)))", systemImage: "clock")
                        .font(.subheadline.monospacedDigit())

                    if let record, record.isCompleted {
                        VStack(spacing: 6) {
                            StarsView(stars: record.bestStars, size: .title2)
                            Text("Best score \(record.bestScore)").font(.headline)
                            if let t = record.bestTime { Text("Best time \(formatTime(t))") }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
                    }

                    Button {
                        app.playDaily()
                    } label: {
                        Label(record == nil ? LocalizedStringKey("Ride today's challenge") : LocalizedStringKey("Ride again"),
                              systemImage: "play.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: .orange))
                    .accessibilityIdentifier("playDailyButton")

                    if app.gameCenter.isAuthenticated {
                        Button {
                            app.gameCenter.showDashboard(leaderboardID: LeaderboardIDs.daily)
                        } label: {
                            Label("Daily leaderboard", systemImage: "list.number")
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("Completed challenges: \(app.progress.stats.dailyCompleted)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Daily Challenge")
    }

    private func countdown(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}

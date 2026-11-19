import SwiftUI
import CitySprintCore

struct CityView: View {
    @Environment(AppModel.self) private var app
    let city: CityID

    var body: some View {
        let palette = city.palette
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(city.weather.label, systemImage: city.weather.symbol)
                        .font(.subheadline.weight(.semibold))
                    Text(city.hazardSummary)
                        .font(.body)
                    Label("\(app.progress.stars(in: city)) / 30 stars", systemImage: "star.fill")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [palette.road.color, palette.accent.color.opacity(0.85)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 12)], spacing: 12) {
                    ForEach(0..<LevelGenerator.levelsPerCity, id: \.self) { index in
                        LevelButton(city: city, index: index)
                    }
                }

                Text("Stars: finish the ride · beat the par time · grab 70% of coins with a clean ride (no potholes, no red lights).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if app.gameCenter.isAuthenticated {
                    Button {
                        app.gameCenter.showDashboard(leaderboardID: LeaderboardIDs.city(city))
                    } label: {
                        Label("\(city.displayName) leaderboard", systemImage: "list.number")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle(city.displayName)
    }
}

private struct LevelButton: View {
    @Environment(AppModel.self) private var app
    let city: CityID
    let index: Int

    var body: some View {
        let unlocked = app.isLevelUnlocked(city, index)
        let record = app.progress.record(for: .city(city, index: index))
        Button {
            app.play(city: city, index: index)
        } label: {
            VStack(spacing: 6) {
                if unlocked {
                    Text("\(index + 1)").font(.title2.bold().monospacedDigit())
                } else {
                    Image(systemName: "lock.fill").font(.title2)
                }
                StarsView(stars: record?.bestStars ?? 0)
                if let best = record?.bestTime {
                    Text(formatTime(best)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(city.palette.accent.color.opacity(unlocked ? 0.8 : 0.2), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unlocked
            ? Text("Level \(index + 1), \(record?.bestStars ?? 0) of 3 stars")
            : Text("Level \(index + 1), locked. Finish the previous level to unlock."))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("level_\(city.code)_\(index + 1)")
    }
}

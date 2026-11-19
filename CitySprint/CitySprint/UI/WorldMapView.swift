import SwiftUI
import CitySprintCore

struct WorldMapView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                MapCanvas()
                    .aspectRatio(1.8, contentMode: .fit)
                    .padding(.horizontal)

                if let next = ProgressionRules.nextLockedCity(in: app.progress) {
                    let needed = ProgressionRules.starsStillNeeded(for: next, in: app.progress)
                    Label("Earn \(needed) more stars to unlock \(next.displayName)", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                        .accessibilityIdentifier("nextUnlockHint")
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                    ForEach(CityID.allCases) { city in
                        CityCard(city: city)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .navigationTitle("World Map")
    }
}

private struct MapCanvas: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.55, green: 0.75, blue: 0.9))
                // Abstract continents (simple blobs, not a real map projection).
                Canvas { ctx, size in
                    let land = Color(red: 0.62, green: 0.78, blue: 0.52)
                    let blobs: [CGRect] = [
                        CGRect(x: 0.08, y: 0.12, width: 0.28, height: 0.36),  // North America
                        CGRect(x: 0.26, y: 0.5, width: 0.16, height: 0.38),   // South America
                        CGRect(x: 0.42, y: 0.1, width: 0.16, height: 0.24),   // Europe
                        CGRect(x: 0.45, y: 0.36, width: 0.17, height: 0.5),   // Africa
                        CGRect(x: 0.58, y: 0.1, width: 0.32, height: 0.4),    // Asia
                        CGRect(x: 0.8, y: 0.62, width: 0.15, height: 0.22),   // Australia
                    ]
                    for b in blobs {
                        let r = CGRect(x: b.minX * size.width, y: b.minY * size.height,
                                       width: b.width * size.width, height: b.height * size.height)
                        ctx.fill(Path(roundedRect: r, cornerRadius: min(r.width, r.height) * 0.45), with: .color(land))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18))

                ForEach(CityID.allCases) { city in
                    let unlocked = app.isCityUnlocked(city)
                    NavigationLink(value: Route.city(city)) {
                        Image(systemName: unlocked ? "mappin.circle.fill" : "lock.circle.fill")
                            .font(.title2)
                            .foregroundStyle(unlocked ? city.palette.accent.color : .gray, .white)
                            .background(Circle().fill(.white).padding(4))
                    }
                    .disabled(!unlocked)
                    .position(x: city.mapPosition.x * geo.size.width, y: city.mapPosition.y * geo.size.height)
                    .accessibilityLabel(Text(city.displayName))
                    .accessibilityHint(unlocked ? Text("Opens the city") : Text("Locked"))
                }
            }
        }
    }
}

struct CityCard: View {
    @Environment(AppModel.self) private var app
    let city: CityID

    var body: some View {
        let unlocked = app.isCityUnlocked(city)
        let stars = app.progress.stars(in: city)
        let palette = city.palette
        NavigationLink(value: Route.city(city)) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: palette.buildings.map(\.color), startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .overlay {
                        Image(systemName: unlocked ? city.weather.symbol : "lock.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(city.displayName).font(.headline)
                    if unlocked {
                        ProgressView(value: Double(stars), total: 30)
                            .tint(palette.accent.color)
                        Text("\(stars) / 30 stars · \(app.progress.completedLevels(in: city)) / 10 levels")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Needs \(ProgressionRules.starsRequired(for: city)) stars")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
            .opacity(unlocked ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("city_\(city.rawValue)")
    }
}

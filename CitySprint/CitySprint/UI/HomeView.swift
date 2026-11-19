import SwiftUI
import CitySprintCore

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            HomeView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .worldMap: WorldMapView()
                    case .city(let city): CityView(city: city)
                    case .daily: DailyChallengeView()
                    case .garage: GarageView()
                    case .settings: SettingsView()
                    }
                }
        }
        .fullScreenCover(item: $app.activeGame) { launch in
            GameView(launch: launch, app: app) { next in
                app.activeGame = nil
                if let next {
                    // Chain straight into the next level.
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        app.play(city: next.0, index: next.1)
                    }
                }
            }
            .environment(app)
        }
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SkylineHeader()
                    .frame(height: 200)
                    .accessibilityHidden(true)

                VStack(spacing: 4) {
                    Text("City Sprint")
                        .font(.largeTitle.weight(.black))
                    Label("\(app.progress.totalStars) / \(app.progress.maxPossibleStars) stars", systemImage: "star.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("totalStars")
                }

                VStack(spacing: 12) {
                    NavigationLink(value: Route.worldMap) {
                        Label("Ride", systemImage: "bicycle")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("playButton")

                    NavigationLink(value: Route.daily) {
                        Label("Daily Challenge", systemImage: "calendar")
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: .orange))
                    .accessibilityIdentifier("dailyButton")

                    HStack(spacing: 12) {
                        NavigationLink(value: Route.garage) {
                            Label("Garage", systemImage: "paintpalette.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: .indigo))
                        .accessibilityIdentifier("garageButton")

                        NavigationLink(value: Route.settings) {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: .gray))
                        .accessibilityIdentifier("settingsButton")
                    }

                    if app.gameCenter.isAuthenticated {
                        HStack(spacing: 12) {
                            Button {
                                app.gameCenter.showDashboard()
                            } label: {
                                Label("Leaderboards", systemImage: "list.number")
                            }
                            Button {
                                app.gameCenter.showAchievements()
                            } label: {
                                Label("Achievements", systemImage: "rosette")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: 480)
                .padding(.horizontal)
            }
            .padding(.bottom, 32)
        }
        .navigationTitle("")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { app.gameCenter.setAccessPointVisible(true) }
        .onDisappear { app.gameCenter.setAccessPointVisible(false) }
    }
}

/// Original stylised skyline: layered blocks in each city's palette.
struct SkylineHeader: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                let sky = Gradient(colors: [Color(red: 0.98, green: 0.62, blue: 0.4), Color(red: 0.36, green: 0.3, blue: 0.62)])
                ctx.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .linearGradient(sky, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                var rng = SplitMix64(seed: 7)
                for (layer, city) in [CityID.paris, .newYork, .tokyo].enumerated() {
                    let colors = city.palette.buildings
                    let baseY = size.height * (0.55 + CGFloat(layer) * 0.12)
                    var x: CGFloat = -20
                    while x < size.width + 20 {
                        let w = CGFloat(rng.range(24, 56))
                        let h = CGFloat(rng.range(30, 110)) * (1 - CGFloat(layer) * 0.2)
                        let color = colors[rng.int(colors.count)].color.opacity(0.65 + Double(layer) * 0.15)
                        ctx.fill(Path(CGRect(x: x, y: baseY - h, width: w, height: h + size.height)), with: .color(color))
                        x += w + 2
                    }
                }
                // Road and a rider gliding across.
                let roadY = size.height * 0.86
                ctx.fill(Path(CGRect(x: 0, y: roadY, width: size.width, height: size.height - roadY)), with: .color(.black.opacity(0.75)))
                let riderX = CGFloat((t * 60).truncatingRemainder(dividingBy: Double(size.width + 80))) - 40
                let x = reduceMotion ? size.width * 0.5 : riderX
                ctx.fill(Path(ellipseIn: CGRect(x: x - 14, y: roadY + 4, width: 12, height: 12)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: x + 4, y: roadY + 4, width: 12, height: 12)), with: .color(.white))
                ctx.fill(Path(roundedRect: CGRect(x: x - 6, y: roadY - 14, width: 12, height: 16), cornerRadius: 5),
                         with: .color(.red))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 0))
    }
}

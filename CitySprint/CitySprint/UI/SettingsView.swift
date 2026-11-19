import SwiftUI
import CitySprintCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmReset = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Toggle(isOn: $app.settings.assistMode) {
                    VStack(alignment: .leading) {
                        Text("Assist mode")
                        Text("Fewer obstacles, a more forgiving hitbox, automatic braking at red lights and 15% more time for the par star. Leaderboards only include unassisted rides.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("assistToggle")
                Toggle(isOn: $app.settings.colorblindSignals) {
                    VStack(alignment: .leading) {
                        Text("Colour-blind-safe signals")
                        Text("Uses an Okabe–Ito palette for hazards, coins and traffic lights. Lights also differ by shape and position.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("colorblindToggle")
                Toggle(isOn: $app.settings.reduceMotion) {
                    VStack(alignment: .leading) {
                        Text("Reduce motion")
                        Text("Turns off screen shake, speed lines, weather streaks and pop animations. Also follows the system setting.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("reduceMotionToggle")
                Toggle("Stamina bar on the right (left-handed)", isOn: $app.settings.leftHandedHUD)
            } header: {
                Text("Accessibility")
            }

            Section("Feedback") {
                Toggle("Haptics", isOn: $app.settings.haptics)
                Toggle("Sound effects", isOn: $app.settings.soundEffects)
            }

            Section {
                Toggle("Sync progress with iCloud", isOn: $app.settings.iCloudSync)
                if app.settings.iCloudSync && app.lastSyncError {
                    Text("iCloud isn't available right now. Your progress is saved on this device and will sync later.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Progress is stored on this device and, if enabled, in your private iCloud database. We never see it.")
            }

            Section("Statistics") {
                stat("Rides", app.progress.stats.runs)
                stat("Finishes", app.progress.stats.finishes)
                stat("Crashes", app.progress.stats.crashes)
                stat("Near misses", app.progress.stats.nearMisses)
                stat("Coins collected", app.progress.stats.lifetimeCoins)
                LabeledContent("Distance ridden") {
                    Text(Measurement(value: app.progress.stats.distanceMeters / 1000, unit: UnitLength.kilometers),
                         format: .measurement(width: .abbreviated, usage: .road))
                }
            }

            Section {
                NavigationLink("Privacy") { PrivacyView() }
                Button("Restore Purchases") { Task { await app.store.restore() } }
                Button("Reset progress", role: .destructive) { confirmReset = true }
                    .accessibilityIdentifier("resetProgressButton")
            } footer: {
                Text("City Sprint \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset everything", role: .destructive) { app.resetProgress() }
        } message: {
            Text("Stars, unlocks and statistics on this device and in iCloud will be erased. Purchases are not affected.")
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: Int) -> some View {
        LabeledContent(title) { Text(value, format: .number) }
    }
}

struct PrivacyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Your privacy").font(.title.bold())
                Text("City Sprint does not collect personal data, does not use analytics or advertising, and does not track you.")
                Text("• Progress is saved on your device. If iCloud sync is on, a copy is kept in your private iCloud database, which only you can access.")
                Text("• Game Center (optional) is provided by Apple under Apple's privacy policy. Scores you submit are visible on leaderboards.")
                Text("• Purchases are processed by Apple. We never see your payment details.")
                Text("• The game works fully offline.")
            }
            .padding()
        }
        .navigationTitle("Privacy")
    }
}

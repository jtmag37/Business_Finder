import Foundation

/// Non-sensitive preferences. Stored in UserDefaults (declared in the privacy
/// manifest with reason CA92.1: app-only access).
struct GameSettings: Codable, Equatable {
    var assistMode = false
    var colorblindSignals = false
    var reduceMotion = false
    var haptics = true
    var soundEffects = true
    var iCloudSync = true
    var leftHandedHUD = false

    // Tolerate settings saved by older versions that lack newer keys.
    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = GameSettings()
        assistMode = try c.decodeIfPresent(Bool.self, forKey: .assistMode) ?? d.assistMode
        colorblindSignals = try c.decodeIfPresent(Bool.self, forKey: .colorblindSignals) ?? d.colorblindSignals
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
        haptics = try c.decodeIfPresent(Bool.self, forKey: .haptics) ?? d.haptics
        soundEffects = try c.decodeIfPresent(Bool.self, forKey: .soundEffects) ?? d.soundEffects
        iCloudSync = try c.decodeIfPresent(Bool.self, forKey: .iCloudSync) ?? d.iCloudSync
        leftHandedHUD = try c.decodeIfPresent(Bool.self, forKey: .leftHandedHUD) ?? d.leftHandedHUD
    }
}

final class SettingsStore {
    private let defaults: UserDefaults
    private let key = "citysprint.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> GameSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(GameSettings.self, from: data) else {
            return GameSettings()
        }
        return settings
    }

    func save(_ settings: GameSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}

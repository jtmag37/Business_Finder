import Foundation

/// Static configuration. Contains no secrets: the app has no backend and
/// talks only to Apple services, which authenticate via the device/Apple ID.
enum AppConfig {
    static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.example.citysprint" }

    /// One-time, cosmetic-only purchase. Configure the same ID in App Store
    /// Connect (non-consumable) and in `CitySprint.storekit`.
    static var supporterProductID: String { bundleID + ".supporter" }

    static var knownProductIDs: Set<String> { [supporterProductID] }

    /// CloudKit container; must match the entitlements file.
    static var cloudContainerID: String { "iCloud." + bundleID }

    static let arguments = ProcessInfo.processInfo.arguments

    /// Set by UI tests: in-memory progress, no Apple services, short levels.
    static let isUITesting = arguments.contains("-uiTesting")

    static let isUnitTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Game Center, CloudKit and StoreKit are disabled under test so tests are
    /// hermetic and never touch the network.
    static var appleServicesEnabled: Bool { !isUITesting && !isUnitTesting }

    /// UI tests that need real generated levels (screenshots) pass this.
    static let uiTestRealLevels = arguments.contains("-uiTestRealLevels")

    /// UI tests can pre-seed stars to unlock content: "-seedStars 30".
    static var seededStars: Int? {
        guard let i = arguments.firstIndex(of: "-seedStars"), i + 1 < arguments.count else { return nil }
        return Int(arguments[i + 1])
    }
}

import Foundation

public enum CityID: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case newYork
    case paris
    case tokyo
    case london
    case amsterdam
    case rioDeJaneiro
    case sydney
    case capeTown

    public var id: String { rawValue }

    /// Short code used in level identifiers ("nyc-01").
    public var code: String {
        switch self {
        case .newYork: return "nyc"
        case .paris: return "par"
        case .tokyo: return "tyo"
        case .london: return "lon"
        case .amsterdam: return "ams"
        case .rioDeJaneiro: return "rio"
        case .sydney: return "syd"
        case .capeTown: return "cpt"
        }
    }

    /// Position in the unlock order, 0...7.
    public var order: Int { CityID.allCases.firstIndex(of: self) ?? 0 }

    /// 0 for the first city, 1 for the last. Used to scale difficulty.
    public var tier: Double { Double(order) / Double(CityID.allCases.count - 1) }

    public init?(code: String) {
        guard let match = CityID.allCases.first(where: { $0.code == code }) else { return nil }
        self = match
    }
}

public enum Weather: String, Codable, Sendable {
    case clear
    case rain
    case heat
    case wind
    case sun

    public var effects: WeatherEffects {
        switch self {
        case .clear: return WeatherEffects()
        // Wet roads: braking distance grows.
        case .rain: return WeatherEffects(brakeMultiplier: 0.55)
        // Heat: stamina drains faster while sprinting and recovers slower.
        case .heat: return WeatherEffects(staminaDrainMultiplier: 1.45, staminaRegenMultiplier: 0.8)
        // Headwind: slightly lower cruising speed.
        case .wind: return WeatherEffects(cruiseMultiplier: 0.93)
        case .sun: return WeatherEffects(staminaDrainMultiplier: 1.15)
        }
    }
}

public struct WeatherEffects: Equatable, Sendable {
    public var brakeMultiplier: Double
    public var staminaDrainMultiplier: Double
    public var staminaRegenMultiplier: Double
    public var cruiseMultiplier: Double

    public init(
        brakeMultiplier: Double = 1,
        staminaDrainMultiplier: Double = 1,
        staminaRegenMultiplier: Double = 1,
        cruiseMultiplier: Double = 1
    ) {
        self.brakeMultiplier = brakeMultiplier
        self.staminaDrainMultiplier = staminaDrainMultiplier
        self.staminaRegenMultiplier = staminaRegenMultiplier
        self.cruiseMultiplier = cruiseMultiplier
    }
}

/// 24-bit sRGB colour. Kept framework-free so palettes live with the game data.
public struct RGB: Hashable, Codable, Sendable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8

    public init(_ hex: UInt32) {
        r = UInt8((hex >> 16) & 0xFF)
        g = UInt8((hex >> 8) & 0xFF)
        b = UInt8(hex & 0xFF)
    }

    public var red: Double { Double(r) / 255 }
    public var green: Double { Double(g) / 255 }
    public var blue: Double { Double(b) / 255 }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let l1 = max(a.luminance, b.luminance)
        let l2 = min(a.luminance, b.luminance)
        return (l1 + 0.05) / (l2 + 0.05)
    }
}

/// Visual identity of a city. Roofs/buildings are drawn procedurally in the
/// app using these colours and the architecture style; no photographs,
/// landmarks or logos are used.
public struct CityPalette: Sendable {
    public var road: RGB
    public var laneMark: RGB
    public var sidewalk: RGB
    public var curb: RGB
    public var buildings: [RGB]
    public var roofDetail: RGB
    public var vehicles: [RGB]
    public var accent: RGB
    public var greenery: RGB
    public var water: RGB

    public init(road: RGB, laneMark: RGB, sidewalk: RGB, curb: RGB, buildings: [RGB], roofDetail: RGB,
                vehicles: [RGB], accent: RGB, greenery: RGB, water: RGB) {
        self.road = road
        self.laneMark = laneMark
        self.sidewalk = sidewalk
        self.curb = curb
        self.buildings = buildings
        self.roofDetail = roofDetail
        self.vehicles = vehicles
        self.accent = accent
        self.greenery = greenery
        self.water = water
    }
}

/// Colours for gameplay-critical signals. The colour-blind set uses the
/// Okabe–Ito palette, and every signal is also distinguished by shape.
public struct SignalPalette: Sendable {
    public var hazard: RGB
    public var coin: RGB
    public var water: RGB
    public var lightGo: RGB
    public var lightCaution: RGB
    public var lightStop: RGB
    public var draft: RGB

    public static let standard = SignalPalette(
        hazard: RGB(0xFF4D3D), coin: RGB(0xFFC83D), water: RGB(0x3DB8FF),
        lightGo: RGB(0x2ED158), lightCaution: RGB(0xFFC300), lightStop: RGB(0xFF3B30),
        draft: RGB(0x7CF7FF)
    )

    public static let colorblindSafe = SignalPalette(
        hazard: RGB(0xD55E00), coin: RGB(0xF0E442), water: RGB(0x56B4E9),
        lightGo: RGB(0x009E73), lightCaution: RGB(0xE69F00), lightStop: RGB(0xD55E00),
        draft: RGB(0xCC79A7)
    )
}

public enum ArchitectureStyle: String, Codable, Sendable {
    case gridTowers        // New York: tall flat roofs, rooftop tanks
    case mansardBlocks     // Paris: zinc-blue mansard roofs, courtyards
    case denseNeon         // Tokyo: small dense blocks with glowing signs
    case terraceBrick      // London: brick terraces with chimney pots
    case canalGables       // Amsterdam: narrow gabled houses beside canals
    case hillsideColor     // Rio: bright stacked houses, palms
    case harbourModern     // Sydney: sandstone & glass, fig trees
    case capeColonial      // Cape Town: white gables, mountain greens
}

public struct WeightedKind: Sendable {
    public var kind: EntityKind
    public var weight: Double

    public init(_ kind: EntityKind, _ weight: Double) {
        self.kind = kind
        self.weight = weight
    }
}

public struct CityDefinition: Sendable {
    public var id: CityID
    public var weather: Weather
    public var starsToUnlock: Int
    public var palette: CityPalette
    public var architecture: ArchitectureStyle
    /// Relative frequencies of the main obstacle stream.
    public var hazards: [WeightedKind]
    /// Distance between traffic lights.
    public var lightSpacing: ClosedRange<Double>
    /// Chance that a traffic light also has a pedestrian crossing.
    public var crosswalkChance: Double
    /// Extra free-standing pedestrian crossings per 100 m.
    public var pedestriansPer100m: Double
    /// Cobblestone zones per km (speed cap).
    public var cobblesPerKm: Double
    /// Tram-track crossings per km (no lane changes on the rails).
    public var tramsPerKm: Double
}

public enum CityCatalog {
    public static let all: [CityDefinition] = CityID.allCases.map(definition(for:))

    public static func definition(for id: CityID) -> CityDefinition {
        switch id {
        case .newYork:
            return CityDefinition(
                id: id, weather: .clear, starsToUnlock: 0,
                palette: CityPalette(
                    road: RGB(0x3B3F47), laneMark: RGB(0xF2F2F2), sidewalk: RGB(0x9EA3AB), curb: RGB(0xC9CDD3),
                    buildings: [RGB(0x8C4A3A), RGB(0x5E6B7A), RGB(0xA0623F), RGB(0x46505C)],
                    roofDetail: RGB(0x6E4B2E),
                    vehicles: [RGB(0xF5C518), RGB(0xF5C518), RGB(0x2F6FDE), RGB(0xD9D9D9), RGB(0x1E1E1E)],
                    accent: RGB(0xF5C518), greenery: RGB(0x4F8A3C), water: RGB(0x3E6E8E)),
                architecture: .gridTowers,
                hazards: [WeightedKind(.car, 0.32), WeightedKind(.parkedCarDoor, 0.2), WeightedKind(.bus, 0.12),
                          WeightedKind(.pothole, 0.14), WeightedKind(.construction, 0.1), WeightedKind(.scooter, 0.12)],
                lightSpacing: 210...280, crosswalkChance: 0.4, pedestriansPer100m: 0.08,
                cobblesPerKm: 0, tramsPerKm: 0)
        case .paris:
            return CityDefinition(
                id: id, weather: .clear, starsToUnlock: 8,
                palette: CityPalette(
                    road: RGB(0x4A4A50), laneMark: RGB(0xEDEDE6), sidewalk: RGB(0xC8BFAE), curb: RGB(0xDAD3C4),
                    buildings: [RGB(0xE3D7BF), RGB(0xD8CBB0), RGB(0xEADFCB), RGB(0xCFC2A6)],
                    roofDetail: RGB(0x5D6F82),
                    vehicles: [RGB(0xFFFFFF), RGB(0x8FA3B8), RGB(0x2D2D2D), RGB(0x9C2F2F)],
                    accent: RGB(0x5D6F82), greenery: RGB(0x6E9A4E), water: RGB(0x5B7F95)),
                architecture: .mansardBlocks,
                hazards: [WeightedKind(.car, 0.26), WeightedKind(.scooter, 0.26), WeightedKind(.parkedCarDoor, 0.16),
                          WeightedKind(.bus, 0.1), WeightedKind(.pothole, 0.1), WeightedKind(.construction, 0.12)],
                lightSpacing: 190...250, crosswalkChance: 0.5, pedestriansPer100m: 0.1,
                cobblesPerKm: 3, tramsPerKm: 0)
        case .tokyo:
            return CityDefinition(
                id: id, weather: .clear, starsToUnlock: 18,
                palette: CityPalette(
                    road: RGB(0x2E3138), laneMark: RGB(0xFFFFFF), sidewalk: RGB(0x8E949C), curb: RGB(0xB5BBC2),
                    buildings: [RGB(0x3A3F58), RGB(0x55607A), RGB(0x6B4F7A), RGB(0x2F4C5E)],
                    roofDetail: RGB(0xFF5FA2),
                    vehicles: [RGB(0xFFFFFF), RGB(0x2A9D8F), RGB(0x264653), RGB(0xE9C46A)],
                    accent: RGB(0xFF5FA2), greenery: RGB(0x5C9E6A), water: RGB(0x3C5A78)),
                architecture: .denseNeon,
                hazards: [WeightedKind(.car, 0.3), WeightedKind(.scooter, 0.18), WeightedKind(.bus, 0.12),
                          WeightedKind(.construction, 0.12), WeightedKind(.cyclist, 0.12), WeightedKind(.pothole, 0.06),
                          WeightedKind(.parkedCarDoor, 0.1)],
                // Dense crossings: lights very frequent, most with pedestrians.
                lightSpacing: 120...165, crosswalkChance: 0.85, pedestriansPer100m: 0.18,
                cobblesPerKm: 0, tramsPerKm: 0)
        case .london:
            return CityDefinition(
                id: id, weather: .rain, starsToUnlock: 30,
                palette: CityPalette(
                    road: RGB(0x3A3D42), laneMark: RGB(0xF4F1E8), sidewalk: RGB(0x8A8E94), curb: RGB(0xA9ADB2),
                    buildings: [RGB(0x8E4B3B), RGB(0x7A4434), RGB(0xA45A45), RGB(0x6C6A66)],
                    roofDetail: RGB(0x4A4F57),
                    vehicles: [RGB(0xC8102E), RGB(0x111111), RGB(0x2B5DA8), RGB(0xD8D8D8)],
                    accent: RGB(0xC8102E), greenery: RGB(0x4E7D44), water: RGB(0x4D6B7C)),
                architecture: .terraceBrick,
                hazards: [WeightedKind(.bus, 0.24), WeightedKind(.car, 0.26), WeightedKind(.parkedCarDoor, 0.16),
                          WeightedKind(.pothole, 0.14), WeightedKind(.construction, 0.12), WeightedKind(.scooter, 0.08)],
                lightSpacing: 180...240, crosswalkChance: 0.5, pedestriansPer100m: 0.1,
                cobblesPerKm: 0, tramsPerKm: 0)
        case .amsterdam:
            return CityDefinition(
                id: id, weather: .wind, starsToUnlock: 42,
                palette: CityPalette(
                    road: RGB(0x6B3B36), laneMark: RGB(0xF3EDE4), sidewalk: RGB(0xA89A8C), curb: RGB(0xC2B6A8),
                    buildings: [RGB(0x5B3A29), RGB(0x2F4F4F), RGB(0x8B5A3C), RGB(0x3C3C55)],
                    roofDetail: RGB(0xF3EDE4),
                    vehicles: [RGB(0xFFFFFF), RGB(0x1F3B70), RGB(0x6E6E6E)],
                    accent: RGB(0xFF7A00), greenery: RGB(0x5E8F45), water: RGB(0x3F6F86)),
                architecture: .canalGables,
                hazards: [WeightedKind(.cyclist, 0.38), WeightedKind(.scooter, 0.16), WeightedKind(.car, 0.14),
                          WeightedKind(.pothole, 0.08), WeightedKind(.construction, 0.1), WeightedKind(.parkedCarDoor, 0.06),
                          WeightedKind(.bus, 0.08)],
                lightSpacing: 200...260, crosswalkChance: 0.45, pedestriansPer100m: 0.1,
                cobblesPerKm: 0, tramsPerKm: 2.5)
        case .rioDeJaneiro:
            return CityDefinition(
                id: id, weather: .heat, starsToUnlock: 55,
                palette: CityPalette(
                    road: RGB(0x45474D), laneMark: RGB(0xFFF4D6), sidewalk: RGB(0xE8E1D4), curb: RGB(0x2B2B2B),
                    buildings: [RGB(0xF4A261), RGB(0x2A9D8F), RGB(0xE76F51), RGB(0xF2D06B)],
                    roofDetail: RGB(0xB5543A),
                    vehicles: [RGB(0xF2D06B), RGB(0x2A9D8F), RGB(0xFFFFFF), RGB(0xE63946)],
                    accent: RGB(0x00A86B), greenery: RGB(0x2F8F46), water: RGB(0x2E9CCA)),
                architecture: .hillsideColor,
                hazards: [WeightedKind(.scooter, 0.3), WeightedKind(.bus, 0.18), WeightedKind(.car, 0.22),
                          WeightedKind(.pothole, 0.16), WeightedKind(.construction, 0.08), WeightedKind(.parkedCarDoor, 0.06)],
                lightSpacing: 200...270, crosswalkChance: 0.4, pedestriansPer100m: 0.1,
                cobblesPerKm: 0, tramsPerKm: 0)
        case .sydney:
            return CityDefinition(
                id: id, weather: .sun, starsToUnlock: 68,
                palette: CityPalette(
                    road: RGB(0x3F4247), laneMark: RGB(0xFFFFFF), sidewalk: RGB(0xD9C7A3), curb: RGB(0xBFAE8A),
                    buildings: [RGB(0xD9B382), RGB(0x8FB8C9), RGB(0xC79A6B), RGB(0x6F9AAB)],
                    roofDetail: RGB(0xE07A3F),
                    vehicles: [RGB(0xFFFFFF), RGB(0x1D4E89), RGB(0xF2B134), RGB(0x3A3A3A)],
                    accent: RGB(0x1D9BF0), greenery: RGB(0x3E7D4A), water: RGB(0x1C7CB8)),
                architecture: .harbourModern,
                hazards: [WeightedKind(.car, 0.28), WeightedKind(.bus, 0.16), WeightedKind(.construction, 0.14),
                          WeightedKind(.scooter, 0.14), WeightedKind(.cyclist, 0.1), WeightedKind(.pothole, 0.08),
                          WeightedKind(.parkedCarDoor, 0.1)],
                lightSpacing: 190...250, crosswalkChance: 0.5, pedestriansPer100m: 0.1,
                cobblesPerKm: 0, tramsPerKm: 1.5)
        case .capeTown:
            return CityDefinition(
                id: id, weather: .wind, starsToUnlock: 82,
                palette: CityPalette(
                    road: RGB(0x404349), laneMark: RGB(0xFFFFFF), sidewalk: RGB(0xC9C2B4), curb: RGB(0xE8E2D4),
                    buildings: [RGB(0xF5F1E6), RGB(0x6FA8DC), RGB(0xE9C46A), RGB(0xD27D6B)],
                    roofDetail: RGB(0x7A5C3E),
                    vehicles: [RGB(0xFFFFFF), RGB(0x2D6A4F), RGB(0xBC4749), RGB(0x6C757D)],
                    accent: RGB(0x2D6A4F), greenery: RGB(0x4C7A3A), water: RGB(0x2B7BB9)),
                architecture: .capeColonial,
                hazards: [WeightedKind(.car, 0.26), WeightedKind(.pothole, 0.2), WeightedKind(.construction, 0.16),
                          WeightedKind(.bus, 0.14), WeightedKind(.scooter, 0.12), WeightedKind(.parkedCarDoor, 0.12)],
                lightSpacing: 210...280, crosswalkChance: 0.4, pedestriansPer100m: 0.08,
                cobblesPerKm: 0, tramsPerKm: 0)
        }
    }
}

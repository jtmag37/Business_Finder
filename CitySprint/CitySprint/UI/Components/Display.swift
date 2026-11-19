import SwiftUI
import CitySprintCore

extension RGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

/// User-facing names live in the app's String Catalog, not in the core.
extension CityID {
    var displayName: String {
        switch self {
        case .newYork: return String(localized: "New York")
        case .paris: return String(localized: "Paris")
        case .tokyo: return String(localized: "Tokyo")
        case .london: return String(localized: "London")
        case .amsterdam: return String(localized: "Amsterdam")
        case .rioDeJaneiro: return String(localized: "Rio de Janeiro")
        case .sydney: return String(localized: "Sydney")
        case .capeTown: return String(localized: "Cape Town")
        }
    }

    var hazardSummary: String {
        switch self {
        case .newYork: return String(localized: "Taxis, opening car doors and roadworks on a tight grid.")
        case .paris: return String(localized: "Cobblestones slow you down. Weaving scooters everywhere.")
        case .tokyo: return String(localized: "Dense crossings: lights and pedestrians at every block.")
        case .london: return String(localized: "Wet roads mean longer braking. Draft the double-deckers.")
        case .amsterdam: return String(localized: "Other cyclists and tram tracks — never switch lanes on the rails.")
        case .rioDeJaneiro: return String(localized: "Heat drains stamina fast. Grab every water bottle.")
        case .sydney: return String(localized: "Bright sun, light rail crossings and harbour traffic.")
        case .capeTown: return String(localized: "Headwinds and potholes on the way to the mountain.")
        }
    }

    /// Rough map position (0...1) for the stylised world map.
    var mapPosition: CGPoint {
        switch self {
        case .newYork: return CGPoint(x: 0.27, y: 0.33)
        case .paris: return CGPoint(x: 0.49, y: 0.27)
        case .tokyo: return CGPoint(x: 0.87, y: 0.35)
        case .london: return CGPoint(x: 0.47, y: 0.21)
        case .amsterdam: return CGPoint(x: 0.53, y: 0.17)
        case .rioDeJaneiro: return CGPoint(x: 0.36, y: 0.72)
        case .sydney: return CGPoint(x: 0.9, y: 0.78)
        case .capeTown: return CGPoint(x: 0.55, y: 0.8)
        }
    }

    var palette: CityPalette { CityCatalog.definition(for: self).palette }
    var weather: Weather { CityCatalog.definition(for: self).weather }
}

extension Weather {
    var symbol: String {
        switch self {
        case .clear: return "cloud.sun.fill"
        case .rain: return "cloud.rain.fill"
        case .heat: return "thermometer.sun.fill"
        case .wind: return "wind"
        case .sun: return "sun.max.fill"
        }
    }

    var label: String {
        switch self {
        case .clear: return String(localized: "Clear")
        case .rain: return String(localized: "Rain: longer braking")
        case .heat: return String(localized: "Heat: faster stamina drain")
        case .wind: return String(localized: "Headwind: lower cruising speed")
        case .sun: return String(localized: "Strong sun: sprinting tires you faster")
        }
    }
}

extension CosmeticItem {
    var displayName: String {
        switch id {
        case "bike.classic": return String(localized: "Classic Red")
        case "bike.steel": return String(localized: "Steel Commuter")
        case "bike.mint": return String(localized: "Mint Fixie")
        case "bike.carbon": return String(localized: "Carbon Racer")
        case "bike.sunset": return String(localized: "Sunset Tourer")
        case "bike.aurora": return String(localized: "Aurora")
        case "bike.gold": return String(localized: "Supporter Gold")
        case "jersey.club": return String(localized: "Club Navy")
        case "jersey.sprinter": return String(localized: "Sprinter")
        case "jersey.climber": return String(localized: "Climber Dots")
        case "jersey.rain": return String(localized: "Rain Cape")
        case "jersey.daily": return String(localized: "Daily Grinder")
        case "jersey.clean": return String(localized: "Clean Rider")
        case "jersey.draft": return String(localized: "Slipstream")
        case "jersey.world": return String(localized: "World Tour")
        case "jersey.supporter": return String(localized: "Supporter Black")
        case "helmet.white": return String(localized: "Classic White")
        case "helmet.neon": return String(localized: "Neon Nights")
        case "helmet.canal": return String(localized: "Canal Orange")
        case "helmet.tropic": return String(localized: "Tropic")
        case "helmet.harbour": return String(localized: "Harbour Blue")
        case "helmet.cape": return String(localized: "Cape Green")
        case "helmet.supporter": return String(localized: "Supporter Gold")
        default: return id
        }
    }
}

extension UnlockRequirement {
    var displayText: String {
        switch self {
        case .free: return String(localized: "Unlocked")
        case .totalStars(let n): return String(localized: "Earn \(n) stars")
        case .cityCompleted(let c): return String(localized: "Finish every level in \(c.displayName)")
        case .nearMisses(let n): return String(localized: "Make \(n) near misses")
        case .lifetimeCoins(let n): return String(localized: "Collect \(n) coins")
        case .dailyChallenges(let n): return String(localized: "Complete \(n) daily challenges")
        case .cleanFinishes(let n): return String(localized: "Finish \(n) clean rides")
        case .drafts(let n): return String(localized: "Slingshot out of a slipstream \(n) times")
        case .supporter: return String(localized: "Supporter Pack")
        }
    }
}

extension CosmeticSlot {
    var label: String {
        switch self {
        case .bike: return String(localized: "Bikes")
        case .jersey: return String(localized: "Jerseys")
        case .helmet: return String(localized: "Helmets")
        }
    }
}

/// Stars row with a VoiceOver summary.
struct StarsView: View {
    let stars: Int
    var size: Font = .caption

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .foregroundStyle(i < stars ? Color.yellow : Color.secondary)
            }
        }
        .font(size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(stars) of 3 stars"))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal)
            .background(tint.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
    }
}

func formatTime(_ seconds: Double) -> String {
    let tenths = Int((seconds * 10).rounded())
    return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
}

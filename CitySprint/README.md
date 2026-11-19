# City Sprint

A one-thumb road-cycling arcade game for iPhone and iPad. Ride short, punchy
levels through eight stylised cities, dodge traffic, draft buses, and chase
three stars.

- **Swift 5.9+ / iOS 17+**, SpriteKit gameplay, SwiftUI menus, portrait only.
- **Offline-first.** Everything works with no network connection.
- **No backend, no third-party SDKs, no analytics, no ads, no tracking.**
  Only Apple services: Game Center, CloudKit (private database), StoreKit 2.

## Gameplay

| Input | Action |
| --- | --- |
| Swipe left / right | Change lane (drag further to change two lanes) |
| Tap | Sprint (uses stamina). Also releases the brake at a light |
| Swipe down | Brake. Brake to a stop before a red light and you hold until green |

- **Obstacles:** cars and taxis, buses, opening car doors, potholes,
  pedestrians, delivery scooters, construction zones, tram tracks (changing
  lanes on the rails crashes you), traffic lights (running a red costs 3 s),
  other cyclists (Amsterdam), cobblestones (Paris, speed cap).
- **Collectibles:** coins, water bottles (restore stamina), and drafting: tuck
  in behind a moving bus to ride at its speed and recover stamina, then pull
  out for a slingshot boost.
- **Near misses:** dodging a hazard late, or passing it with very little
  room, builds a combo (up to ×5) for bonus points.
- **Stars:** 1 for finishing, 1 for beating par time (penalties included),
  1 for collecting 70% of the coins on a clean ride (no potholes, no red lights).
- **Crashing** restarts the level in under half a second.
- **Weather:** London rain (longer braking), Rio heat (faster stamina drain),
  Amsterdam and Cape Town headwind (lower cruise speed), Sydney sun.

### Cities and unlocks

| City | Stars needed | Signature |
| --- | --- | --- |
| New York | 0 | Taxis, car doors, roadworks |
| Paris | 8 | Cobblestones, scooters |
| Tokyo | 18 | Dense crossings: lights and pedestrians every block |
| London | 30 | Rain, double-decker buses to draft |
| Amsterdam | 42 | Other cyclists, tram tracks, headwind |
| Rio de Janeiro | 55 | Heat, scooters, potholes |
| Sydney | 68 | Sun, light-rail crossings |
| Cape Town | 82 | Wind, potholes, construction |

Each city has 10 levels (240 stars total). Within a city, each level opens
after the previous one is finished.

### Retention, without dark patterns

- **Daily challenge:** one seeded course per UTC day, identical for every
  player (custom deterministic PRNG, so it never varies by OS version).
- **Game Center:** a leaderboard per city (sum of best level scores), a daily
  leaderboard, and 17 achievements.
- **Cosmetics:** 7 bikes, 9 jerseys, 7 helmets, all earned through play
  (stars, finishing cities, near misses, daily challenges…). An optional
  one-time **Supporter Pack** adds three gold items. It is purely cosmetic.
- No energy or lives, no timers, no loot boxes, no currencies, no ads.

## Project layout

```
CitySprint/
├── project.yml                       XcodeGen spec (generates CitySprint.xcodeproj)
├── Packages/CitySprintCore/          Pure-Swift game logic (no UIKit/SpriteKit)
│   ├── Sources/CitySprintCore/
│   │   ├── GameSimulation.swift      Fixed-step simulation: physics, collisions, scoring events
│   │   ├── Level.swift               Entity kinds, level data (Codable), tuning constants
│   │   ├── LevelGenerator.swift      Deterministic level + daily generation
│   │   ├── LevelValidator.swift      Proves every level has a ridable line
│   │   ├── City.swift                Cities, weather, palettes, hazard mixes
│   │   ├── Scoring.swift             RunResult, score and star rules
│   │   ├── Progress.swift            PlayerProgress, recording, conflict-free merge
│   │   ├── Progression.swift         Unlock rules, cosmetics, achievements, daily, entitlements
│   │   ├── Persistence.swift         Atomic JSON file store with backup + validation
│   │   └── SeededRandom.swift        SplitMix64 + FNV-1a
│   └── Tests/CitySprintCoreTests/    Unit tests for all of the above
├── CitySprint/
│   ├── App/                          App entry, AppModel, configuration
│   ├── Game/                         SpriteKit scene, procedural texture atlas, game view
│   ├── Services/                     Game Center, CloudKit, StoreKit 2, Keychain, haptics, audio
│   ├── UI/                           SwiftUI menus (map, city, daily, garage, settings, results)
│   └── Resources/                    Assets, String Catalog, privacy manifest, StoreKit config
├── CitySprintTests/                  App-hosted unit tests (model, keychain, scene)
├── CitySprintUITests/                UI tests for the main flows
└── docs/                             App Store, security and privacy documentation
```

**Architecture.** `CitySprintCore` is the game engine and data layer: a
deterministic simulation that knows nothing about rendering. `GameScene`
steps it at a fixed 120 Hz and draws it; SwiftUI handles every menu and
overlay. `AppModel` owns progress/settings and talks to the Apple services.

**Performance.** All sprites are drawn procedurally once per level and packed
into one runtime `SKTextureAtlas`. Entity sprites, lane markings, buildings,
particles and weather come from node pools; the simulation keeps its entities
in a preallocated array and reports events through a reserved buffer, so
steady-state frames do not allocate. HUD labels only change when their value
changes.

## Building

Requirements: Xcode 16 or newer (Swift 5.9+), iOS 17 SDK, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
cd CitySprint
xcodegen generate
open CitySprint.xcodeproj
```

Before running on a device or submitting:

1. In `project.yml`, set `DEVELOPMENT_TEAM` and change the bundle ID
   `com.example.citysprint` to your own (then run `xcodegen generate` again).
   Update `productID` in `CitySprint/Resources/CitySprint.storekit` to
   `<your bundle id>.supporter`.
2. In the Apple Developer portal, enable **Game Center** and **iCloud
   (CloudKit)** for the App ID and create the container
   `iCloud.<your bundle id>`.
3. Set up App Store Connect as described in
   [docs/APP_STORE_SUBMISSION.md](docs/APP_STORE_SUBMISSION.md).

The scheme uses `CitySprint.storekit`, so the Supporter Pack can be bought in
the simulator without App Store Connect.

### Tests

```sh
# Game logic (fast, no simulator)
cd CitySprint/Packages/CitySprintCore && swift test

# App unit tests + UI tests
cd CitySprint && xcodebuild test -project CitySprint.xcodeproj -scheme CitySprint \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

CI (`.github/workflows/citysprint.yml`) runs both on every push that touches
`CitySprint/`.

UI tests launch the app with `-uiTesting`. That switches to in-memory progress,
turns off Game Center, CloudKit and StoreKit, and uses a short obstacle-free
test course. `-seedStars N` pre-seeds stars.

## Localization

All user-facing strings use SwiftUI string literals or `String(localized:)`
and live in `CitySprint/Resources/Localizable.xcstrings`. Xcode keeps the
catalog in sync on build (`SWIFT_EMIT_LOC_STRINGS`). To add a language, add it
in the project's Localizations and translate in the catalog. English ships first.

## Accessibility

- Dynamic Type everywhere in menus (system text styles only).
- VoiceOver labels and values on every control; level and cosmetic tiles
  read as one element ("Level 3, 2 of 3 stars").
- When VoiceOver or Switch Control is running, on-screen lane, brake and
  sprint buttons appear in-game.
- Colour-blind-safe signals (Okabe–Ito). Traffic lights also differ by shape
  (square = stop, triangle = caution, circle = go) and position, and coins
  carry a star glyph.
- Reduce Motion (system setting or in-app) turns off shake, speed lines,
  weather streaks and pop animations.
- Assist mode: about 30% fewer obstacles, a 25% smaller hitbox, automatic
  braking for red lights and 15% more par time. Assisted rides earn stars and
  unlocks but are not submitted to leaderboards.
- Option to move the stamina bar to the right for left-handed play.

## Art and IP

All art is drawn procedurally at runtime from simple shapes and per-city
palettes: architecture styles (grid towers, mansard roofs, canal gables, …),
colours and street furniture. There are no photos, logos, brand names,
real company vehicles or licensed landmarks. All sounds are synthesised at
launch.

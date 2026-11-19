# App Store submission checklist

## 1. Identity and signing

- [ ] Choose a bundle ID (e.g. `com.yourcompany.citysprint`). Replace
      `com.example.citysprint` in `project.yml` and the product ID in
      `CitySprint/Resources/CitySprint.storekit`. Run `xcodegen generate`.
- [ ] Set `DEVELOPMENT_TEAM` in `project.yml`.
- [ ] In Certificates, Identifiers & Profiles, enable these App ID capabilities:
      **Game Center**, **iCloud** (CloudKit), and **In-App Purchase**
      (on by default).
- [ ] Create the iCloud container `iCloud.<bundle id>`.
- [ ] Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` for each upload.

## 2. CloudKit

- [ ] Run a development build once while signed into iCloud. The
      `PlayerProgress` record type is created automatically in the
      Development environment. It has a single field, `payload` (Bytes).
- [ ] In the CloudKit Console, **Deploy Schema Changes** to Production before
      release.
- [ ] No indexes are needed (the app fetches one record by ID).

## 3. Game Center (App Store Connect → your app → Game Center)

Create these exactly. IDs are defined in `LeaderboardIDs` and `AchievementCatalog`.

**Leaderboards** (classic, "High score is better", integer):

| ID | Name | Type |
| --- | --- | --- |
| `citysprint.leaderboard.city_newyork` | New York | Classic |
| `citysprint.leaderboard.city_paris` | Paris | Classic |
| `citysprint.leaderboard.city_tokyo` | Tokyo | Classic |
| `citysprint.leaderboard.city_london` | London | Classic |
| `citysprint.leaderboard.city_amsterdam` | Amsterdam | Classic |
| `citysprint.leaderboard.city_riodejaneiro` | Rio de Janeiro | Classic |
| `citysprint.leaderboard.city_sydney` | Sydney | Classic |
| `citysprint.leaderboard.city_capetown` | Cape Town | Classic |
| `citysprint.leaderboard.daily` | Daily Challenge | **Recurring**, 1-day duration, starting 00:00 UTC |

**Achievements:**

| ID | Suggested title | Requirement |
| --- | --- | --- |
| `citysprint.achievement.first_finish` | First Ride | Earn 1 star |
| `citysprint.achievement.stars_30` | Commuter | 30 stars |
| `citysprint.achievement.stars_120` | Courier | 120 stars |
| `citysprint.achievement.stars_240` | World Tour | All 240 stars |
| `citysprint.achievement.near_miss_100` | Close Shave | 100 near misses |
| `citysprint.achievement.coins_5000` | Coin Collector | 5,000 coins |
| `citysprint.achievement.daily_7` | Daily Habit | 7 daily challenges |
| `citysprint.achievement.draft_25` | Slipstreamer | 25 slingshots |
| `citysprint.achievement.clean_10` | Clean Rider | 10 clean finishes |
| `citysprint.achievement.city_<city>` ×8 | City Finisher (one per city) | Finish all 10 levels |

City suffixes: `newyork`, `paris`, `tokyo`, `london`, `amsterdam`,
`riodejaneiro`, `sydney`, `capetown`.

## 4. In-app purchase

- [ ] Create a **Non-Consumable** with product ID `<bundle id>.supporter`.
      Reference name: "Supporter Pack". Price tier of your choice. Enable Family Sharing.
- [ ] Description: "Support development and unlock three gold cosmetic items.
      Does not affect gameplay."
- [ ] Review screenshot of the Garage → Supporter Pack section.
- [ ] Submit the IAP together with the first app version.
- [ ] A **Restore Purchases** button is in the Garage and in Settings (Guideline 3.1.1).

## 5. App Privacy ("nutrition label")

Answer **"Data Not Collected"**. Why:

- No analytics, crash-reporting SDK, ads or tracking.
- Progress is stored on device. iCloud sync uses the user's **private**
  CloudKit database, which the developer cannot access. Apple does not count
  this as collection.
- Game Center and StoreKit are Apple services covered by Apple's privacy policy.
- `PrivacyInfo.xcprivacy` declares no tracking, no collected data, and one
  required-reason API (UserDefaults, reason `CA92.1`).

You still need a **Privacy Policy URL**. Host `docs/PRIVACY_POLICY.md` (filled in) on any page you control.

## 6. Export compliance

`ITSAppUsesNonExemptEncryption = NO` is set in Info.plist. The app only uses
encryption provided by Apple's OS (HTTPS within Apple frameworks).

## 7. Age rating

Expected answers: no violence beyond cartoon/fantasy "crash" (a bump and a
restart, no injury depicted), no user-generated content, no gambling, no
unrestricted web access. The result should be **4+**.

## 8. Metadata

- Category: Games → Racing (secondary: Arcade or Casual).
- Supported devices: iPhone and iPad, portrait.
- Screenshots: 6.9" iPhone (1320×2868) and 13" iPad (2064×2752) at minimum.
  Use the simulator with `-seedStars 120` to show unlocked cities.
- Keywords idea: cycling, bike, city, runner, arcade, commute, daily challenge.
- Review notes: "No login required. Game Center is optional. The Supporter
  Pack is cosmetic only. To see later cities quickly, earn stars in New York."

## 9. Pre-flight

- [ ] `swift test` in `Packages/CitySprintCore` passes.
- [ ] `xcodebuild test` (unit + UI) passes on iPhone and iPad simulators.
- [ ] Test on a physical iPhone 12 or newer with Instruments → Game
      Performance template. Confirm a steady 60 fps on the hardest level
      (Tokyo 10) and no allocations in steady-state frames (Allocations,
      "Created & Still Living" flat during a run).
- [ ] Airplane mode: the full game, daily challenge, garage and progress all work.
- [ ] Signed out of Game Center and iCloud: no errors shown, game fully playable.
- [ ] StoreKit sandbox: buy, restore, and refund (via `.storekit` → Manage
      Transactions → Refund) correctly toggle the gold cosmetics.
- [ ] VoiceOver pass over every screen; Dynamic Type at AX5 has no clipped text.
- [ ] Archive (Release) → Validate App → Distribute.

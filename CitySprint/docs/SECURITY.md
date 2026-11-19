# Security and privacy design

## Attack surface

| Area | Decision |
| --- | --- |
| Backend | **None.** No servers, APIs or custom endpoints. |
| Network | The app makes no network requests itself. Only Apple frameworks (GameKit, CloudKit, StoreKit) talk to Apple. |
| ATS | Enforced with **no exceptions**. Info.plist has no `NSAppTransportSecurity` key, so the secure defaults apply. |
| Third-party code | **None.** No SDKs or Swift packages besides the local `CitySprintCore`. Nothing to pin, nothing to audit. |
| Secrets | **None in the codebase.** Apple services authenticate through the device's Apple ID. Product IDs and container IDs are public identifiers derived from the bundle ID. |
| Web views / URL schemes / deep links | None. |

## Purchases (StoreKit 2)

- Entitlements are computed only from `Transaction.currentEntitlements` and
  `Transaction.updates` results that are `VerificationResult.verified`.
  StoreKit checks the JWS signature on device.
- Unverified transactions are ignored. They are never finished as grants and
  never unlock content (`StoreService.handle`).
- Revoked (refunded), expired, upgraded and unknown-product transactions grant
  nothing (`EntitlementResolver`, unit-tested).
- The last verified entitlement is cached in the **Keychain**
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), not UserDefaults. It is
  only a display fallback until StoreKit answers at launch, and is overwritten
  by the verified result.
- The purchase is cosmetic only. If someone forged it, the only effect would be
  three gold colourways on their own device.

## Local data

- Progress: JSON in Application Support, written atomically with
  `completeFileProtectionUntilFirstUserAuthentication`, plus a backup copy.
- Every load (local file or CloudKit record) goes through
  `ProgressCoding.decode`, which enforces a size limit and the schema version,
  and range-checks values (stars 0–3, non-negative scores, finite times). Corrupt
  files are quarantined, not trusted.
- Settings (non-sensitive) are in UserDefaults. The privacy manifest declares this
  with reason `CA92.1`.
- Game Center scores waiting to be submitted offline are stored as
  `{leaderboardID, score}` pairs. They contain no personal data.

## Cloud sync

- Only the user's **private** CloudKit database is used. The developer cannot read it.
- Merges use a conflict-free, field-wise "best of both" function. A stale or
  malicious copy can never reduce progress, and the merge is idempotent and
  commutative (unit-tested).

## Leaderboard integrity

Scores are computed on device, which is inherent to any game without a
backend. Mitigations:

- Leaderboards only accept unassisted, finished runs.
- City leaderboards hold the sum of best level scores, which is bounded by
  level content. Out-of-range values in Game Center can be removed in App Store
  Connect.
- No rewards of value depend on leaderboard rank.

## Privacy

- No personal data is collected. There is no analytics, no IDFA or ATT
  prompt, no fingerprinting, and no logging of identifiers.
- The privacy manifest declares `NSPrivacyTracking = false`, with no tracking
  domains and no collected data types.

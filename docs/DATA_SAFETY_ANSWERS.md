# Data Safety Form Answers — Google Play

Play Console → App content → Data safety. Answer exactly as below.

## Section 1 — Data collection and security

- Does your app collect or share any of the required user data types? **Yes**
- Is all of the user data encrypted in transit? **Yes**
- Do you provide a way for users to request that their data be deleted? **Yes**
  - URL: `https://__PLACEHOLDER_DOMAIN__/delete-account`

## Section 2 — Data types

| Data type | Collected | Shared | Optional? | Purpose |
|---|---|---|---|---|
| Email address | Yes | No | No | Account management |
| User IDs (Supabase UID) | Yes | No | No | Account management |
| Name (display name) | Yes | No | Yes | App functionality |
| Financial info → Other financial info (trades, P&L, lots, balances) | Yes | Yes (service providers) | Yes | App functionality, analytics |
| Photos (chart screenshots) | Yes | Yes (service providers) | Yes | App functionality |
| App interactions (guard opens, signals followed) | Yes | No | No | Analytics, app functionality |
| Crash logs / diagnostics | Yes | No | No | App functionality |
| Device or other IDs (FCM token, purchase token) | Yes | Yes (service providers) | No | App functionality |

**Shared with** = service providers only (Supabase, MetaAPI, RevenueCat, Firebase, OpenAI).
No data is sold. No data is used for advertising.

## Section 3 — Security practices

- Encrypted in transit: **Yes** (TLS)
- Encrypted at rest: **Yes** (Supabase storage/database encryption)
- Data deletion mechanism: in-app + public URL (see above)
- Committed to Play Families policy: N/A (18+ only)
- Independent security review: No (not required)

## Section 4 — Must match app behaviour

- Manifest permissions: `INTERNET`, `POST_NOTIFICATIONS`, `CAMERA`, `READ_MEDIA_IMAGES`
  (screenshots only). No location, contacts, SMS, call logs.
- No advertising SDK; no third-party analytics beyond crash reporting.
- If AI/provider set changes, or ads are added, update this form.

## Section 5 — Consistency check

Data safety answers must match the Privacy Policy and the app's actual permissions before
submitting for review. A mismatch is a common rejection reason.

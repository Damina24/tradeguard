# App Content Declarations — Google Play & App Store

Play Console → App content. Fill each section as follows.

## 1. Privacy policy

- URL (required): `https://__PLACEHOLDER_DOMAIN__/privacy`
- Must be publicly reachable (no login) before you submit for review.

## 2. Data safety

See `docs/DATA_SAFETY_ANSWERS.md`. Required: encryption in transit, deletion URL.

## 3. Ads

- Does the app contain ads? **No.**
- (Play shows "No ads" badge. Do not add ad SDKs without updating this.)

## 4. App access

- Are all features available without special access? **No** — provide reviewer credentials.
- Instructions for reviewers (English):
  ```
  Use the demo mode: tap "Explore demo" on the welcome screen without signing in.
  All guard, journal, tools and signals screens are populated with sample data.
  For account features, sign in with:
    Email: reviewer@__PLACEHOLDER_DOMAIN__
    Password: __PLACEHOLDER_REVIEWER_PASSWORD__
  ```

## 5. Content rating

See `docs/CONTENT_RATING_ANSWERS.md`.

## 6. Target audience and content

- Target age group: **18 and over** (adults only). Do **not** select Designed for Families.
- Appeals to children? **No.**
- Contains content that may appeal to children? **No.**

## 7. News app

- Is this a news app? **No.** (The economic calendar shows factual scheduled events, not
  editorial news.) If editorial news is ever added, register as a news app.

## 8. COVID-19 contact tracing / status

- **No.**

## 9. Data deletion

- Provide in-app deletion **and** a public URL: `https://__PLACEHOLDER_DOMAIN__/delete-account`
- See `docs/ACCOUNT_DELETION.md`.

## 10. Financial features (Play Finance policy)

- This app offers: **financial education/analytics, informational trading signals, a trading
  journal, and optional copy-trading via a third-party broker API.**
- It is **not** a lender, personal-loan, or crypto-exchange app.
- Provide risk disclaimer URL: `https://__PLACEHOLDER_DOMAIN__/risk`
- No promises of profit; no "guaranteed" language anywhere.

## 11. Government apps

- **No.**

## 12. Health

- **No.**

## 13. Play App Signing

- Enable **Play App Signing** (required for new apps). Keep the upload keystore backed up.

## 14. Apple-specific (App Store Connect)

| Section | Answer |
|---|---|
| App Privacy | Match `DATA_SAFETY_ANSWERS.md` |
| Age rating | 17+ if WebView loads unrestricted web, else 12+ |
| In-App Purchase | Subscriptions (Pro/Elite) + non-consumable (Lifetime) |
| Export compliance | Uses HTTPS only → standard exemption |
| Sign-in required | Yes → supply reviewer credentials |
| Demo account | As above |

## 15. New personal-account testing rule

Accounts created after 13 Nov 2023 must run **Closed testing with ≥12 testers opted-in for
14 consecutive days** before applying for production access. Plan and tester list are in
`docs/IMPLEMENTATION_PLAN.md`.

# Google Play & App Store — Publishing Requirements Checklist

## A. Accounts & verification

- [ ] Google Play Developer account ($25 one-time) 🧑
- [ ] Verify developer identity (personal: government ID; org: D-U-N-S number) 🧑
- [ ] Apple Developer Program ($99/yr) 🧑
- [ ] Play App Signing enabled; upload keystore backed up 🧑

## B. App technical requirements (Play, 2024+)

- [ ] Target **API level 34+** (Android 14) — set in `android/app/build.gradle` 🧑 fill
- [ ] 64-bit support (Flutter default) + upload **AAB** (not APK)
- [ ] Application ID `com.tradeguard.app`
- [ ] Version code / name set (`pubspec.yaml` version)
- [ ] No `android:debuggable`, release build signed
- [ ] `data safety` consistent with permissions
- [ ] Foreground/background behaviour declares `POST_NOTIFICATIONS`

## C. Required store content

- [ ] Title (30), short description (80), full description (4000) — see `store/STORE_LISTING.md`
- [ ] Icon 512×512, feature graphic 1024×500, ≥2 screenshots 🧑
- [ ] Category: Finance
- [ ] Contact email + website 🧑
- [ ] Privacy policy URL (live, public) 🧑 `https://__PLACEHOLDER_DOMAIN__/privacy`
- [ ] Data deletion URL (live, public) 🧑 `https://__PLACEHOLDER_DOMAIN__/delete-account`

## D. Play Console → App content (all mandatory)

- [ ] Privacy policy
- [ ] App access (reviewer credentials / demo mode)
- [ ] Ads declaration — No
- [ ] Content rating questionnaire — see `docs/CONTENT_RATING_ANSWERS.md`
- [ ] Target audience — 18+, not for families
- [ ] News app — No
- [ ] Data safety — see `docs/DATA_SAFETY_ANSWERS.md`
- [ ] Government apps — No
- [ ] Financial features — declared with disclaimer URL
- [ ] Health — No

## E. Testing requirement (personal accounts, post 13-Nov-2023)

- [ ] Internal testing track used first
- [ ] **Closed testing: ≥12 testers opted-in for 14 consecutive days** 🧑
- [ ] Then apply for Production access
- [ ] Staged rollout 20% → 100%

## F. Payments

- [ ] Subscriptions created in Play Console (Pro, Elite) 🧑
- [ ] Lifetime product (non-renewing) created 🧑
- [ ] RevenueCat project + entitlement `pro`/`elite`/`lifetime` configured 🧑
- [ ] Billing includes the app; free trial terms disclosed

## G. Policy compliance (Finance)

- [ ] Risk disclaimer present in-app and in listing
- [ ] No guaranteed-profit or "best signals" claims anywhere
- [ ] No personal-loan / crypto-exchange features
- [ ] Account deletion works end-to-end

## H. Apple (App Store Connect)

- [ ] App record + bundle `com.tradeguard.app`
- [ ] App Privacy answers match Data Safety
- [ ] Age rating (17+ if unrestricted WebView, else 12+)
- [ ] Review notes with demo credentials
- [ ] TestFlight build before submission
- [ ] Export compliance: standard HTTPS exemption

## I. Launch checklist

- [ ] All `__PLACEHOLDER__` values replaced
- [ ] `flutter analyze` clean and `flutter test` green
- [ ] Crash-free smoke test on a physical device
- [ ] Privacy/terms/delete URLs return HTTP 200 publicly
- [ ] Screenshots show the disclaimer
- [ ] Version bumped and changelog written
- [ ] Rollback plan: previous AAB retained, staged rollout paused if needed

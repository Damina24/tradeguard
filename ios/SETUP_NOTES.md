# Human steps to enable the iOS build (dev machine is Windows)

The iOS runner project cannot be authored by hand reliably — Xcode's `.xcodeproj` must be
generated. Do this once from a Mac or from the Codemagic build VM:

```bash
flutter create --platforms=ios --org com.tradeguard .
```

That generates `ios/Runner.xcodeproj`, `ios/Runner/Info.plist`, `ios/Podfile` and the asset
catalogs with the placeholder icon. Then apply the settings below (also in
`ios/Runner/Info.plist.notes.md`).

## Bundle identifiers

| Target | Bundle ID |
|---|---|
| Runner | `com.tradeguard.app` |
| RunnerTests | `com.tradeguard.app.RunnerTests` |

Set in Xcode → Runner target → Signing & Capabilities, and in Codemagic via
`APP_STORE_CONNECT_*` / provisioning profiles.

## Info.plist keys to add

```xml
<key>CFBundleDisplayName</key>
<string>TradeGuard - Forex Signals</string>
<key>NSCameraUsageDescription</key>
<string>Take a chart screenshot to run AI analysis.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Attach a chart screenshot to a trade review.</string>
<key>UIBackgroundModes</key>
<array><string>remote-notification</string></array>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>tradeguard</string></array>
  </dict>
</array>
<key>UIStatusBarStyle</key>
<string>UIStatusBarStyleLightContent</string>
```

## Export compliance

`ITSAppUsesNonExemptEncryption` → `false` (HTTPS only), which skips the manual prompt.

## Sign in with Apple / Google (human input)

Two things are needed on top of the Info.plist keys above:

1. **Sign in with Apple** capability on the Runner target (Signing & Capabilities). Without it
   `getAppleIDCredential` throws "not available" and the app shows *"Sign in with Apple is not
   available on this device."*
2. A **URL Type** for Google sign-in — the scheme is the iOS client id with dots reversed, e.g.
   `com.googleusercontent.apps.1234567890-abcdef`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.__PLACEHOLDER__</string>
    </array>
  </dict>
</array>
```

`GOOGLE_IOS_CLIENT_ID` in `env/*.json` must match that client. See `docs/BACKEND_DEPLOY.md`.

## Push notifications

Add the **Push Notifications** capability plus the APNs key in App Store Connect, then upload
`GoogleService-Info.plist` (git-ignored) for FCM.

## Signing in CI (Codemagic)

1. Upload your `.p12` distribution certificate and provisioning profile, or let Codemagic
   manage signing with an App Store Connect API key.
2. Build command: `flutter build ipa --release --dart-define-from-file=env/prod.json`.

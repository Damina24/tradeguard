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

## Push notifications

Add the **Push Notifications** capability plus the APNs key in App Store Connect, then upload
`GoogleService-Info.plist` (git-ignored) for FCM.

## Signing in CI (Codemagic)

1. Upload your `.p12` distribution certificate and provisioning profile, or let Codemagic
   manage signing with an App Store Connect API key.
2. Build command: `flutter build ipa --release --dart-define-from-file=env/prod.json`.

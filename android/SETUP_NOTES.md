# Android platform build files included in this repo

`flutter build apk` / `flutter build appbundle` work out of the box: Flutter downloads and drives
the Gradle distribution declared in `android/gradle/wrapper/gradle-wrapper.properties`, so no
local Gradle install is required.

## Verified toolchain (Flutter 3.47.6 / Dart 3.13.5)

Flutter enforces hard minimums at build time — these are the errors you get if you fall below:

| Component | Version here | Flutter minimum | Source of truth |
|---|---|---|---|
| Gradle | 8.14.3 | **8.14.0** (error) | `gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle Plugin | 8.13.0 | **8.11.1** (error) | `settings.gradle.kts` `plugins { }` |
| Kotlin (KGP) | 2.2.20 | **2.2.20** (error) | `settings.gradle.kts` `plugins { }` |
| Java | 17 | **17** (error) | `flutter config --jdk-dir` |
| compileSdk / targetSdk | 36 | — | `app/build.gradle` |
| minSdk | `flutter.minSdkVersion` (24) | — | `app/build.gradle` |

`compileSdk` must be **>= 36** because `url_launcher` pulls in `androidx.browser:browser:1.9.0`,
whose AAR metadata demands compileSdk 36+ (`checkDebugAarMetadata` fails otherwise).

### Pin the JDK used by Gradle

Flutter chooses the JDK for Gradle from its own config and will happily pick Android Studio's
bundled JBR. Android Studio "Rabbit" ships **Java 25**, which Gradle 8.14.3 refuses
("Gradle version ... is lower/incompatible"). Pin a JDK 17 once:

```bash
flutter config --jdk-dir="C:/Program Files/Microsoft/jdk-17.0.20.8-hotspot"
```

### Missing Android SDK packages

`compileSdk` and the NDK version must exist locally. Install them with the **new Android CLI**
(`android.exe`) — the classic `sdkmanager.bat` shim mangles arguments like `ndk;28.2.13676358`
and reports "Package not found":

```bash
ANDROID_SDK=C:/Users/f/AppData/Local/Android/Sdk
"$ANDROID_SDK/cmdline-tools/latest/bin/android.exe" sdk install "platforms;android-36"
"$ANDROID_SDK/cmdline-tools/latest/bin/android.exe" sdk install "ndk;28.2.13676358"
```

`cmdline-tools` itself is **not** bundled with Android Studio on this machine; without it
`flutter doctor` reports `cmdline-tools component is missing`. See `INSTALL.md`.

### Gradle wrapper scripts (optional)

`gradlew`, `gradlew.bat` and `gradle/wrapper/gradle-wrapper.jar` are not committed (binaries).
To materialise them for use from Android Studio:

```bash
flutter create --platforms=android,ios --org com.tradeguard .
```

`flutter create` only adds missing files — it does **not** overwrite the hand-authored files below,
so it will not "fix" a broken `settings.gradle.kts`.

### Commands

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run
```

## Sign in with Apple / Google (human input)

The plugins are wired; they need project credentials.

- **Apple on Android** runs the flow in a Chrome Custom Tab, so it needs the Service ID
  `com.tradeguard.app.web` as `APPLE_WEB_CLIENT_ID` in `env/dev.json`. Without it the button reports
  *"Apple sign-in is not configured for this build"* instead of crashing.
- **Google** needs the *Web* OAuth client id as `GOOGLE_SERVER_CLIENT_ID` (Android mints the id token
  with it) and the iOS client id as `GOOGLE_IOS_CLIENT_ID`. `google-services.json` must sit in
  `android/app/`.
- The debug/release **SHA-1 fingerprints** of the upload keystore have to be listed on the Android
  OAuth client, otherwise Google returns `DEVELOPER_ERROR` (10).

Full walkthrough: `docs/BACKEND_DEPLOY.md`.

## Push notifications (human input)

`google-services.json` in `android/app/` enables FCM. The `guard_alerts` channel id already matches
`FcmPushService.channelId` and the manifest meta-data.

## Launcher icon

`AndroidManifest.xml` deliberately sets no `android:icon`, so the app builds with no launcher
artwork and no icon files live in `res/`. (Do not put stray `README.txt`/`.md` files in `res/` —
AAPT2 rejects any resource file that is not `.xml` or a raster image.) Before release, add adaptive
icons at `android/app/src/main/res/mipmap-*/ic_launcher.png` (512x512 source, no alpha) and point
`android:icon` at them. See `store/PUBLISHING_CHECKLIST.md`.

## What is already hand-authored here

- `app/build.gradle` — applicationId `com.tradeguard.app`, compile/target SDK 36, Java 17, release
  signing from `key.properties`, R8 + resource shrinking, core library desugaring.
- `settings.gradle.kts` — Kotlin DSL (Groovy syntax is invalid in a `.kts` file), AGP 8.13.0,
  Kotlin 2.2.20, Flutter plugin loader, `rootProject.name`.
- `build.gradle.kts` — `allprojects { repositories }`, shared `buildDir`, clean task.
- `app/src/main/AndroidManifest.xml` — permissions + `tradeguard://` deep link + FCM channel.
- `app/proguard-rules.pro`, `app/src/main/res/**` — themes, launch background, network policy.

## Release keystore (human input)

Create `android/key.properties` (git-ignored):

```properties
storePassword=__PLACEHOLDER__
keyPassword=__PLACEHOLDER__
keyAlias=upload
storeFile=C:/Users/f/keys/tradeguard-upload.jks
```

Generate the keystore with `keytool` and enable Play App Signing.

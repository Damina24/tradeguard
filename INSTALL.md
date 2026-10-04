# Install & Run — step by step (Windows)

Follow this once. At the end you will have a green `flutter analyze`, passing `flutter test`,
and the app running on your phone/emulator in **mock mode** (no API keys needed).

> Check your progress at any point with:
> `powershell -ExecutionPolicy Bypass -File tools\check_env.ps1`

---

## Step 1 — Git (already installed)

```powershell
git --version
```

If it prints a version, skip. Otherwise: `winget install --id Git.Git -e`

---

## Step 2 — Install Flutter 3.22+

> **Note:** winget has **no official Flutter SDK package** (it only carries `Google.DartSDK`
> and apps *built* with Flutter), so `winget install Flutter.Flutter` fails with
> *"No package found matching input criteria."* Use git clone or the ZIP instead.

Current stable is **Flutter 3.47.6 (Dart 3.13.5)** — comfortably above this project's
minimum of 3.22, so anything you install today will work.

### Option A — git clone (recommended; you already have Git 2.55)

Clone into your user folder (no spaces, not `C:\Program Files`):

```powershell
git clone --depth 1 -b stable https://github.com/flutter/flutter.git C:\Users\f\flutter
```

### Option B — manual ZIP

Download the official bundle, then extract it to `C:\Users\f\flutter`:

```
https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.6-stable.zip
```

> Do **not** put the SDK under `C:\Program Files` — the space in the path breaks the toolchain.

### Warm up the tool (first run downloads the Dart SDK, ~2 min)

```powershell
C:\Users\f\flutter\bin\flutter --version
```

---

## Step 3 — Put Flutter on your PATH

**Fastest way — one command** (updates your User PATH; opens no dialogs):

```powershell
[Environment]::SetEnvironmentVariable(
  "Path",
  [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\Users\f\flutter\bin",
  "User"
)
```

**Or via the GUI:**
1. Press `Win`, type **environment**, open **Edit the system environment variables**.
2. **Environment Variables…** → under *User variables* pick **Path** → **Edit** → **New**.
3. Add `C:\Users\f\flutter\bin` → **OK** on every dialog.

Either way, **close and reopen** PowerShell and VS Code, then verify:

```powershell
flutter --version
```

---

## Step 4 — Install the Android toolchain

> **Already present on this machine:** Android Studio (`C:\Program Files\Android\Android Studio`)
> and the SDK at `C:\Users\f\AppData\Local\Android\Sdk` (platforms 34/35/37, build-tools 34/35/36,
> platform-tools, `adb`). `winget install --id Google.AndroidStudio -e` only answers *"cannot be
> upgraded using WinGet"* — that is fine, skip it.

### 4a. Command-line Tools — the one thing Android Studio does **not** install

Without these, `flutter doctor` reports `cmdline-tools component is missing` and AGP cannot
install SDK packages for you:

```powershell
$ProgressPreference = 'SilentlyContinue'
$sdk  = 'C:\Users\f\AppData\Local\Android\Sdk'
$url  = 'https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip'
$zip  = "$env:TEMP\clt.zip"

curl.exe -L -s -o $zip $url
$dest = "$env:TEMP\clt_extract"
if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $dest -Force

$target = "$sdk\cmdline-tools\latest"
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item "$dest\cmdline-tools\*" $target -Recurse -Force
```

> Build numbers move; that URL is the stable `cmdline-tools;latest` for Windows. If it 404s, find
> the current one under <https://developer.android.com/studio#command-line-tools-only>.

Register `ANDROID_HOME` and put the CLI on your PATH (User scope, no dialogs):

```powershell
$sdk = 'C:\Users\f\AppData\Local\Android\Sdk'
$clt = "$sdk\cmdline-tools\latest\bin"
[Environment]::SetEnvironmentVariable('ANDROID_HOME', $sdk, 'User')
[Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', $sdk, 'User')
[Environment]::SetEnvironmentVariable(
  'Path',
  [Environment]::GetEnvironmentVariable('Path','User').TrimEnd(';') + ';' + $clt,
  'User'
)
```

> Note: the modern `sdkmanager` no longer needs `flutter doctor --android-licenses` — it reports
> *"The --licenses option is no longer needed"* and manages licenses itself.

### 4b. Pin the JDK that Gradle runs on ← easy to miss

Flutter chooses the JDK for Gradle from **its own config**, not `JAVA_HOME`, and it will happily
pick Android Studio's bundled JBR. Current Android Studio ships **Java 25**, which Gradle 8.14
rejects. Pin JDK 17 once:

```powershell
flutter config --jdk-dir="C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot"
```

### 4c. Install the SDK packages the build actually needs

Use the **new** `android.exe` CLI — the classic `sdkmanager.bat` shim mangles arguments such as
`ndk;28.2.13676358` and answers *"Package not found"*:

```powershell
$android = "$env:LOCALAPPDATA\Android\Sdk\cmdline-tools\latest\bin\android.exe"
& $android sdk install "platforms;android-36"
& $android sdk install "ndk;28.2.13676358"
```

`platforms;android-36` is required because `compileSdk = 36`; the NDK version comes from
`ndkVersion = flutter.ndkVersion`. The first Gradle build also pulls **CMake 3.22.1** itself.

---

## Step 5 — Confirm the toolchain is healthy

```powershell
flutter doctor -v
```

You want green checks on **Flutter**, **Android toolchain**, **Chrome**, **Visual Studio** and
**Connected device**. There is no iOS toolchain on Windows — that is expected, since iOS is built
later on a Mac/Codemagic (see `ios/SETUP_NOTES.md`).

> If Flutter warns *"the flutter binary is not on your path"*, that shell simply started before you
> edited PATH. Close and reopen PowerShell / VS Code.

Re-run the helper any time:

```powershell
powershell -ExecutionPolicy Bypass -File tools\check_env.ps1
```

---

## Step 6 — Platform runners (optional)

`flutter build apk` / `flutter build appbundle` work **without** this step. Flutter downloads and
drives the Gradle distribution named in `android/gradle/wrapper/gradle-wrapper.properties`
itself, so the missing `gradle-wrapper.jar` is not a problem.

Run `flutter create` only if you want the extra boilerplate — `android/gradlew`,
`android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`, `ios/Runner.xcodeproj` and
default launcher icons:

```powershell
cd "c:\Users\f\Desktop\Strategy Tracker"
flutter create --platforms=android,ios --org com.tradeguard .
```

Two caveats:

- It only adds **missing** files, so it will not repair `android/settings.gradle.kts` — one already
  exists, and `flutter create` never overwrites it.
- It may generate `test/widget_test.dart`, which references a `MyApp` class this project does not
  have. Remove it if it appears:
  ```powershell
  Remove-Item test\widget_test.dart -ErrorAction SilentlyContinue
  ```

---

## Step 7 — Fetch dependencies

```powershell
flutter pub get
```

---

## Step 8 — Static analysis (must be zero issues)

```powershell
flutter analyze
```

---

## Step 9 — Run the tests (must be all green)

```powershell
flutter test
```

---

## Step 10 — Turn on a device

> ⚠️ **There is no `web/` folder in this project** — it targets Android + iOS only. `flutter run -d chrome`
> fails with *"This project is not configured for the web."* Use an Android target below (or add web
> support deliberately with `flutter create --platforms web .`).

```powershell
flutter devices
```

**Android emulator:** Android Studio → **Device Manager → Create Device → Pixel 7 → API 34 → Finish**, then:

```powershell
flutter emulators --launch <emulator_id>
flutter devices
flutter run
```

**Physical Android phone:** enable *Developer options → USB debugging*, plug in, accept the
prompt, then `flutter run`.

**Or skip a device entirely** and prove the whole Android build compiles:

```powershell
flutter build apk --debug     # -> build\app\outputs\flutter-apk\app-debug.apk
```

Hot reload = `r`, hot restart = `R`, quit = `q`.

---

## Step 11 — Run against a real backend (optional, later)

```powershell
copy env\dev.example.json env\dev.json
# edit env\dev.json and replace every __PLACEHOLDER__
flutter run --dart-define-from-file=env/dev.json
```

`AppConfig.useMock` stays `true` while `SUPABASE_URL` is empty, so the app keeps running on
demo data until you fill it in. `env\dev.json` is git-ignored — never commit real keys.

In VS Code you can instead use **Run and Debug → “TradeGuard (mock mode)”** (see `.vscode/launch.json`).

---

## Known issues & fixes

| Symptom | Fix |
| --- | --- |
| `flutter` not recognised | Re-open the terminal/VS Code after editing PATH; confirm `C:\Users\f\flutter\bin`. |
| `winget … No package found matching input criteria` | Expected — winget has no Flutter SDK package. Use the git clone in Step 2. |
| `cmdline-tools component is missing` | Android Studio does **not** bundle these on this machine. Install manually — Step 4a. |
| `Android license status unknown` | The modern CLI says `--licenses` is no longer needed and self-manages. Step 4a. |
| `Java version 25 is incompatible with Gradle 8.x` | Flutter picked Android Studio's bundled JBR. `flutter config --jdk-dir=<JDK 17>` — Step 4b. |
| `Gradle version (8.7.0) is lower than Flutter's minimum 8.14.0` | Raise `distributionUrl` in `android/gradle/wrapper/gradle-wrapper.properties` (now `gradle-8.14.3-all.zip`). |
| `AGP version (8.3.2) is lower than … minimum 8.11.1` | Raise `com.android.application` in `android/settings.gradle.kts` (now `8.13.0`). |
| Kotlin "support will soon be dropped" | Raise `org.jetbrains.kotlin.android` to `2.2.20` (already done; `2.3.20` silences the warning). |
| `androidx.browser:browser:1.9.0 requires … version 36 or later` | `url_launcher` pulls it in. Set `compileSdk`/`targetSdk` to `36` and install `platforms;android-36`. |
| `Package ndk not found` / `did not install NDK` | The `sdkmanager.bat` shim mangles `;`. Use `android.exe sdk install "ndk;28.2.13676358"` — Step 4c. |
| `res/…/README.txt: file name must end with .xml or .png` | AAPT2 rejects non-resource files in `res/`. Move notes out (this repo's placeholder was deleted). |
| `Val cannot be reassigned` on `rootProject.name` | Illegal in `build.gradle.kts`; it belongs in `settings.gradle.kts`. |
| `This project is not configured for the web` | No `web/` folder — this app is Android + iOS. Use an Android target. |
| `flutter test` fails on `widget_test.dart` | Delete the generated file (Step 6) — it tests a missing `MyApp`. |
| `The method 'withValues' isn't defined` | Flutter is older than 3.22 → `flutter upgrade`. |
| `Undefined name 'firstOrNull'` | Run `flutter pub get` (the `collection` re-export ships with Flutter). |
| Gradle hangs / `Could not resolve` on first build | The first build downloads Gradle 8.14.3 + all AGP/Kotlin/plugin artifacts (~12 min). Let it finish. |
| Emulator very slow | Enable WHPX/Hyper-V in *Windows Features*, or use a physical device. |

---

## What success looks like

```
✓ Flutter (Channel stable, 3.47.6)
✓ Android toolchain - develop for Android devices
No issues found!          <- flutter analyze
All tests passed!         <- flutter test  (26 tests)
✓ Built build\app\outputs\flutter-apk\app-debug.apk
```

Then `flutter run` shows the **Guard** tab with the FTMO EVAL 100K account, a SAFE meter, and the
5-tab bar (Guard · Journal · Tools · Signals · Settings).

Once this is green you are ready for **Phase 1** (auth → broker connect → live guard).

@echo off
setlocal EnableDelayedExpansion
echo ==========================================
echo TradeGuard: Phase 0 Flutter Setup & Verify
echo ==========================================

:: 1. Check if Flutter is installed
where flutter >nul 2>nul
if %errorlevel% neq 0 (
    echo [!] Flutter not found. Attempting to install via winget...
    winget install Flutter.Flutter --accept-source-agreements --accept-package-agreements
    if %errorlevel% neq 0 (
        echo [X] Winget installation failed. Please install Flutter manually from https://docs.flutter.dev/get-started/install/windows
        pause
        exit /b 1
    )
    echo [+] Flutter installed. Refreshing environment variables...
    refreshenv >nul 2>nul
)

:: 2. Navigate to project directory
cd /d "C:\Users\f\Desktop\Strategy Tracker"

:: 3. Generate native wrappers (Android/iOS) without overwriting lib/
echo [+] Generating native platform wrappers...
flutter create --platforms=android,ios --org com.tradeguard .

:: 4. Fetch dependencies
echo [+] Fetching dependencies...
flutter pub get

:: 5. Run static analysis
echo [+] Running flutter analyze...
flutter analyze

:: 6. Run tests
echo [+] Running flutter test...
flutter test

:: 7. Final status
echo ==========================================
echo Setup & Verification Complete!
echo Check the output above for any errors.
echo If all green, we are ready for Phase 1.
echo ==========================================
pause
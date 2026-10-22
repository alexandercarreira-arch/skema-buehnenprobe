#!/usr/bin/env bash
# Probe S1-H: Bau ohne Signatur und Pruefung des Archivs (Bauzettel 45, § 5.3 Schritte 1 bis 5).
# Laeuft im Pruef-Job und im Upload-Job, braucht keine Secrets. Kompatibel mit bash 3.2 (macOS).
set -euo pipefail

BUNDLE_ID="io.github.alexandercarreira-arch.skema-buehnenprobe"
VERSION="0.1"
XCODEGEN_URL="https://github.com/yonaskolb/XcodeGen/releases/download/2.46.0/xcodegen.zip"
XCODEGEN_SHA256="4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806"

LOGS="build/logs"
ZUSAMMENFASSUNG="${GITHUB_STEP_SUMMARY:-/dev/null}"
FEHLER=0
mkdir -p "$LOGS" build/werkzeug

rot() {
  echo "::error::$1"
  echo "- rot: $1" >> "$ZUSAMMENFASSUNG"
  FEHLER=1
}

gleich() { # Name, Ist, Soll
  if [ "$2" = "$3" ]; then
    echo "ok: $1 = $2"
  else
    rot "$1 ist '$2', erwartet '$3'"
  fi
}

halt_bei_rot() {
  if [ "$FEHLER" != 0 ]; then
    echo "::error::$1"
    exit 1
  fi
}

# 1. Xcode und die Schluessel der Export-Optionen (E9, § 5.4)
echo "::group::1 Xcode"
if [ -n "${DEVELOPER_DIR:-}" ] && [ ! -d "$DEVELOPER_DIR" ]; then
  ls -d /Applications/Xcode* || true
  rot "DEVELOPER_DIR fehlt auf diesem Runner: $DEVELOPER_DIR"
  halt_bei_rot "Xcode-Fassung nicht gefunden"
fi
xcodebuild -version > "$LOGS/xcode-version.txt"
cat "$LOGS/xcode-version.txt"
xcodebuild -help > "$LOGS/xcodebuild-help.txt" 2>&1 || true
for schluessel in app-store-connect testFlightInternalTestingOnly manageAppVersionAndBuildNumber destination; do
  if grep -q -- "$schluessel" "$LOGS/xcodebuild-help.txt"; then
    echo "ok: xcodebuild -help nennt $schluessel"
  else
    rot "xcodebuild -help nennt $schluessel nicht"
  fi
done
halt_bei_rot "Export-Optionen passen nicht zu dieser Xcode-Fassung"
echo "::endgroup::"

# 2. XcodeGen 2.46.0 mit Pruefsumme, Projekt erzeugen, Build-Einstellungen pruefen (E2)
echo "::group::2 XcodeGen"
curl -fsSL --retry 3 -o build/werkzeug/xcodegen.zip "$XCODEGEN_URL"
echo "$XCODEGEN_SHA256  build/werkzeug/xcodegen.zip" | shasum -a 256 -c -
rm -rf build/werkzeug/xcodegen
unzip -q build/werkzeug/xcodegen.zip -d build/werkzeug
build/werkzeug/xcodegen/bin/xcodegen generate --spec project.yml
xcodebuild -project Probe.xcodeproj -scheme Probe -configuration Release \
  -destination 'generic/platform=iOS' -showBuildSettings > "$LOGS/build-settings.txt"
einstellung() {
  awk -v k="$1" '{ sub(/^[ \t]+/, "") } index($0, k " = ") == 1 { print substr($0, length(k) + 4); exit }' \
    "$LOGS/build-settings.txt"
}
gleich PLATFORM_NAME "$(einstellung PLATFORM_NAME)" iphoneos
case "$(einstellung SDKROOT)" in
  *iPhoneOS*.sdk) echo "ok: SDKROOT $(einstellung SDKROOT)" ;;
  *) rot "SDKROOT ist '$(einstellung SDKROOT)', erwartet das iPhoneOS-SDK" ;;
esac
gleich TARGETED_DEVICE_FAMILY "$(einstellung TARGETED_DEVICE_FAMILY)" 2
gleich PRODUCT_BUNDLE_IDENTIFIER "$(einstellung PRODUCT_BUNDLE_IDENTIFIER)" "$BUNDLE_ID"
gleich PRODUCT_MODULE_NAME "$(einstellung PRODUCT_MODULE_NAME)" Probe
gleich IPHONEOS_DEPLOYMENT_TARGET "$(einstellung IPHONEOS_DEPLOYMENT_TARGET)" 26.0
gleich SWIFT_VERSION "$(einstellung SWIFT_VERSION)" 5.0
halt_bei_rot "Build-Einstellungen falsch (hat XcodeGen seine Vorgaben gefunden?)"
echo "::endgroup::"

# 3. Baunummer und Xcode-Fassung
BUILD="${GITHUB_RUN_NUMBER:-0}.${GITHUB_RUN_ATTEMPT:-1}"
PROBE_XCODE="$(sed -n 1p "$LOGS/xcode-version.txt")"
echo "Baunummer $BUILD, $PROBE_XCODE"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "BUILD=$BUILD" >> "$GITHUB_ENV"
  echo "PROBE_XCODE=$PROBE_XCODE" >> "$GITHUB_ENV"
fi

# 4. Archiv ohne Signatur (E10)
echo "::group::4 Archiv"
set +e
xcodebuild -project Probe.xcodeproj -scheme Probe -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Probe.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY= \
  CURRENT_PROJECT_VERSION="$BUILD" PROBE_XCODE="$PROBE_XCODE" \
  archive > "$LOGS/archive.log" 2>&1
STATUS=$?
set -e
grep -E "(error|warning): " "$LOGS/archive.log" | awk '!gesehen[$0]++' | head -n 200 || true
tail -n 5 "$LOGS/archive.log"
echo "::endgroup::"
if [ "$STATUS" != 0 ]; then
  grep -E "error: " "$LOGS/archive.log" | awk '!gesehen[$0]++' | head -n 40 | while IFS= read -r zeile; do
    echo "::error::$zeile"
  done || true
  echo "- rot: Archiv (xcodebuild Status $STATUS), Fehler im Artefakt archive.log" >> "$ZUSAMMENFASSUNG"
  exit 1
fi

# 5. Pruefschritt am Archiv, bevor Apple etwas sieht
echo "::group::5 Pruefung des Archivs"
APP="build/Probe.xcarchive/Products/Applications/Probe.app"
INFO="$APP/Info.plist"
if [ ! -f "$INFO" ]; then
  rot "kein $INFO im Archiv"
  halt_bei_rot "Archiv ohne Programm"
fi
plutil -p "$INFO" > "$LOGS/archiv-info.txt"
ls -la "$APP" > "$LOGS/archiv-inhalt.txt"
wert() {
  local aus
  if aus="$(/usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null)"; then
    echo "$aus"
  else
    echo "<fehlt>"
  fi
}
anzahl() {
  local aus
  if aus="$(/usr/libexec/PlistBuddy -c "Print :$1" "$INFO" 2>/dev/null)"; then
    echo "$aus" | grep -c "UIInterfaceOrientation" || true
  else
    echo 0
  fi
}
MANIFEST="UIApplicationSceneManifest:UISceneConfigurations"
gleich CFBundleIdentifier "$(wert CFBundleIdentifier)" "$BUNDLE_ID"
gleich CFBundleShortVersionString "$(wert CFBundleShortVersionString)" "$VERSION"
gleich CFBundleVersion "$(wert CFBundleVersion)" "$BUILD"
gleich CFBundleDisplayName "$(wert CFBundleDisplayName)" "Bühnenprobe"
gleich ProbeXcode "$(wert ProbeXcode)" "$PROBE_XCODE"
gleich ITSAppUsesNonExemptEncryption "$(wert ITSAppUsesNonExemptEncryption)" false
gleich "UIDeviceFamily:0" "$(wert UIDeviceFamily:0)" 2
gleich "UIDeviceFamily:1" "$(wert UIDeviceFamily:1)" "<fehlt>"
if /usr/libexec/PlistBuddy -c "Print :UILaunchScreen" "$INFO" > /dev/null 2>&1; then
  echo "ok: UILaunchScreen vorhanden"
else
  rot "UILaunchScreen fehlt"
fi
gleich UIApplicationSupportsMultipleScenes "$(wert UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes)" true
gleich "Regie: Name" "$(wert "$MANIFEST:UIWindowSceneSessionRoleApplication:0:UISceneConfigurationName")" Regie
gleich "Regie: Klasse" "$(wert "$MANIFEST:UIWindowSceneSessionRoleApplication:0:UISceneDelegateClassName")" Probe.RegieSzene
gleich "TV: Name" "$(wert "$MANIFEST:UIWindowSceneSessionRoleExternalDisplayNonInteractive:0:UISceneConfigurationName")" TV
gleich "TV: Klasse" "$(wert "$MANIFEST:UIWindowSceneSessionRoleExternalDisplayNonInteractive:0:UISceneDelegateClassName")" Probe.TvSzene
gleich "Ausrichtungen" "$(anzahl UISupportedInterfaceOrientations)" 4
gleich "Ausrichtungen~ipad" "$(anzahl 'UISupportedInterfaceOrientations~ipad')" 4
gleich "CFBundleIcons~ipad: CFBundleIconName" "$(wert 'CFBundleIcons~ipad:CFBundlePrimaryIcon:CFBundleIconName')" AppIcon
if grep -q '\$(' "$LOGS/archiv-info.txt"; then
  rot "nicht eingesetzte Build-Einstellung in der Info.plist: $(grep '\$(' "$LOGS/archiv-info.txt" | head -n 3 | tr '\n' ' ')"
else
  echo "ok: keine Reste von \$( in der Info.plist"
fi
for datei in PrivacyInfo.xcprivacy Assets.car Probe; do
  if [ -f "$APP/$datei" ]; then echo "ok: $datei im Programm"; else rot "$datei fehlt im Programm"; fi
done
plutil -lint "$APP/PrivacyInfo.xcprivacy" || rot "PrivacyInfo.xcprivacy ist kein gueltiges Plist"
if ls build/Probe.xcarchive/dSYMs/*.dSYM > /dev/null 2>&1; then echo "ok: dSYM im Archiv"; else rot "kein dSYM im Archiv"; fi
# Welcher Zweig aus RegieController.registriereTvFuerIPadOS27 im Programm steckt (E6): der Text der
# Registrierung nur mit Swift 6.4 (Xcode 27), sonst der Hinweis „Compiler vor Swift 6.4".
if grep -a -q "TV registriert" "$APP/Probe"; then
  WEG27="im Bau (Swift 6.4 oder neuer)"
elif grep -a -q "Compiler vor Swift 6.4" "$APP/Probe"; then
  WEG27="nicht im Bau (Compiler vor Swift 6.4)"
else
  WEG27="unbekannt"
  rot "Weg fuer iPadOS 27: keiner der beiden Texte im Programm"
fi
echo "Weg fuer iPadOS 27: $WEG27"
echo "::endgroup::"
halt_bei_rot "Pruefung des Archivs rot"

{
  echo "### Archiv geprueft"
  echo ""
  echo "- Baunummer: \`$BUILD\`"
  echo "- Xcode: \`$PROBE_XCODE\`"
  echo "- Bundle-ID: \`$BUNDLE_ID\`"
  echo "- Weg fuer iPadOS 27: $WEG27"
} >> "$ZUSAMMENFASSUNG"
echo "Archiv geprueft: Bau $BUILD, $PROBE_XCODE"

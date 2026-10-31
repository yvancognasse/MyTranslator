#!/bin/bash
# MyTranslator build script
# Settings are managed in the app Setup UI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FINAL_APP_PATH="$SCRIPT_DIR/MyTranslator.app"
mkdir -p "$SCRIPT_DIR/.build"
STAGING_DIR="$(mktemp -d "$SCRIPT_DIR/.build/package.XXXXXX")"
APP_PATH="$STAGING_DIR/MyTranslator.app"
LOGO_PNG="$SCRIPT_DIR/MyTranslator.png"
BUSY_ICON_PNG="$SCRIPT_DIR/IconProposal/Translation-In-Progress-Concept.png"
LOCALIZATIONS_JSON="$SCRIPT_DIR/Resources/InterfaceLocalizations.json"
USER_GUIDE_HTML="$SCRIPT_DIR/Documentation/UserGuide.html"
PREBUILT_ICON="$SCRIPT_DIR/MyTranslator.icns"
PREBUILT_ICON_SOURCE_HASH="$SCRIPT_DIR/MyTranslator.icns.source.sha256"
BACKGROUND_PNG="$SCRIPT_DIR/MyTranslatorBackground.png"
VERSION_FILE="$SCRIPT_DIR/.mytranslator_build"
BUILD_TMP_DIR="${TMPDIR:-/tmp}/mytranslator-build"

RUNNER_PATH="$APP_PATH/Contents/Resources/translator_runner.sh"
LOCAL_TRANSLATOR_PATH="$APP_PATH/Contents/Resources/local_translator"

mkdir -p "$BUILD_TMP_DIR/clang-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_TMP_DIR/clang-cache"

printf '\n'
printf '╔══════════════════════════════════════════════╗\n'
printf '║   Création de MyTranslator.app               ║\n'
printf '╚══════════════════════════════════════════════╝\n'
printf '\n'

command -v swiftc >/dev/null 2>&1 || { echo "❌ swiftc introuvable : installez Xcode Command Line Tools (xcode-select --install)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "❌ python3 introuvable"; exit 1; }
if [ ! -s "$USER_GUIDE_HTML" ] || [ "$SCRIPT_DIR/Sources/MyTranslatorApp.swift" -nt "$USER_GUIDE_HTML" ] || [ "$SCRIPT_DIR/Sources/UILocalization.swift" -nt "$USER_GUIDE_HTML" ] || [ "$SCRIPT_DIR/Sources/LocalTranslator.swift" -nt "$USER_GUIDE_HTML" ] || [ "$SCRIPT_DIR/Sources/TranslationProcess.swift" -nt "$USER_GUIDE_HTML" ] || [ "$LOCALIZATIONS_JSON" -nt "$USER_GUIDE_HTML" ] || [ "$SCRIPT_DIR/create_app.sh" -nt "$USER_GUIDE_HTML" ]; then
    echo "❌ Mettez à jour Documentation/UserGuide.html après chaque modification du code avant de reconstruire l’app." >&2
    exit 1
fi

python3 - "$LOCALIZATIONS_JSON" "$SCRIPT_DIR/Sources/MyTranslatorApp.swift" <<'PY'
import json
import re
import sys

catalog = json.load(open(sys.argv[1], encoding="utf-8"))
source = open(sys.argv[2], encoding="utf-8").read()
languages = catalog["languages"]
strings = catalog["strings"]
supported_languages = {"ar", "da", "de", "en", "es", "fr", "hi", "id", "it", "ja", "ko", "nb", "nl", "pl", "pt", "ru", "sv", "th", "tr", "uk", "vi", "zh-Hans"}
if not supported_languages <= set(languages) | {"en"}:
    sys.exit(f"Missing interface languages: {sorted(supported_languages - set(languages) - {'en'})}")
keys = set(re.findall(r'\bl\("([^"\\]*(?:\\.[^"\\]*)*)"\)', source))
keys.update(re.findall(r'UILocalization\.text\("([^"\\]*(?:\\.[^"\\]*)*)"\)', source))
keys.update(("Translating…", "Improving…"))
missing = sorted(keys - strings.keys())
incomplete = sorted(key for key, values in strings.items() if len(values) != len(languages) or any(not value for value in values))
if missing or incomplete:
    sys.exit(f"Incomplete interface localization: missing={missing}; incomplete={incomplete}")
PY

if [ -f "$VERSION_FILE" ] && awk 'NF && $0 !~ /[^0-9]/ { found=1 } END { exit found ? 0 : 1 }' "$VERSION_FILE"; then
    BUILD_NUMBER="$(cat "$VERSION_FILE")"
else
    BUILD_NUMBER="0"
fi
BUILD_NUMBER="$((BUILD_NUMBER + 1))"
APP_VERSION="1.$BUILD_NUMBER"
LAST_COMPILED="$(date '+%b %e, %Y at %l:%M %p' | sed 's/  / /g')"
BUILD_DATE="$(date '+%Y-%m-%d')"


echo "→ $(swiftc --version 2>&1 | head -1)"
echo "→ Build : $BUILD_NUMBER"
echo "→ Dossier projet : $SCRIPT_DIR"
echo "→ Préparation du nouveau bundle (ancienne application conservée)"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"

if [ ! -f "$BACKGROUND_PNG" ]; then
    /usr/bin/python3 - "$BACKGROUND_PNG" <<'PY'
import math
import random
import struct
import sys
import zlib

path = sys.argv[1]
width, height = 700, 400
random.seed(42)

def pixel(x, y):
    base = [224, 220, 194]
    grain = random.randint(-4, 4)
    r, g, b = [max(0, min(255, c + grain)) for c in base]

    dx, dy = x - 260, y - 165
    if (dx * dx) / (150 * 150) + (dy * dy) / (105 * 105) < 1:
        r, g, b = min(255, r + 16), min(255, g + 15), min(255, b + 13)

    dx, dy = x - 625, y - 285
    ring = abs(math.hypot(dx, dy) - 170)
    if ring < 2 or abs(math.hypot(dx, dy) - 154) < 2 or abs(math.hypot(dx, dy) - 138) < 2:
        r, g, b = r - 34, g - 33, b - 29

    for cx, cy in [(45, 20), (570, 40), (620, 70)]:
        dx, dy = x - cx, y - cy
        dist = math.hypot(dx, dy)
        if 18 < dist < 94 and abs((dist % 10) - 1) < 1.2:
            r, g, b = r - 29, g - 28, b - 24

    return bytes((max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)), 255))

raw = bytearray()
for y in range(height):
    raw.append(0)
    for x in range(width):
        raw.extend(pixel(x, y))

def chunk(kind, data):
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    )

png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    + chunk(b"IEND", b"")
)
with open(path, "wb") as f:
    f.write(png)
PY
fi
cp "$BACKGROUND_PNG" "$APP_PATH/Contents/Resources/MyTranslatorBackground.png"
if [ ! -s "$BUSY_ICON_PNG" ]; then
    echo "❌ Icône de traduction en cours absente : $BUSY_ICON_PNG" >&2
    exit 1
fi
cp "$BUSY_ICON_PNG" "$APP_PATH/Contents/Resources/BusyIcon.png"
for resource in "$LOCALIZATIONS_JSON" "$USER_GUIDE_HTML"; do
    [ -s "$resource" ] || { echo "❌ Ressource manquante ou vide : $resource" >&2; exit 1; }
done
cp "$LOCALIZATIONS_JSON" "$APP_PATH/Contents/Resources/InterfaceLocalizations.json"
sed "s/{{BUILD_NUMBER}}/$BUILD_NUMBER/g" "$USER_GUIDE_HTML" > "$APP_PATH/Contents/Resources/UserGuide.html"

cat > "$RUNNER_PATH" <<'RUNNER'
#!/bin/bash
set -euo pipefail
RES_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$RES_DIR/local_translator" "$@"
RUNNER
chmod 0755 "$RUNNER_PATH"

LOCAL_SWIFT_SRC="$SCRIPT_DIR/Sources/LocalTranslator.swift"
if [ ! -f "$LOCAL_SWIFT_SRC" ]; then
    echo "❌ Source Swift absente : $LOCAL_SWIFT_SRC"
    exit 1
fi

echo "→ Compilation du traducteur local Apple..."
swiftc -module-cache-path "$BUILD_TMP_DIR/clang-cache" -parse-as-library -framework Foundation -framework NaturalLanguage -framework Translation "$LOCAL_SWIFT_SRC" -o "$LOCAL_TRANSLATOR_PATH"
chmod 0755 "$LOCAL_TRANSLATOR_PATH"
echo "   ✓ OK"

ICON_PLIST_KEY=""
if [ -f "$LOGO_PNG" ]; then
    echo "→ Conversion MyTranslator.png -> AppIcon.icns..."
    ICONSET="/tmp/MyTranslator_$$.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16   "$LOGO_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null 2>&1 || true
    sips -z 32 32   "$LOGO_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null 2>&1 || true
    sips -z 32 32   "$LOGO_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null 2>&1 || true
    sips -z 64 64   "$LOGO_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null 2>&1 || true
    sips -z 128 128 "$LOGO_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null 2>&1 || true
    sips -z 256 256 "$LOGO_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null 2>&1 || true
    sips -z 256 256 "$LOGO_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null 2>&1 || true
    sips -z 512 512 "$LOGO_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null 2>&1 || true
    sips -z 512 512 "$LOGO_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null 2>&1 || true
    if ! iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns" >/dev/null 2>&1; then
        expected_hash="$(cat "$PREBUILT_ICON_SOURCE_HASH" 2>/dev/null || true)"
        actual_hash="$(shasum -a 256 "$LOGO_PNG" | awk '{ print $1 }')"
        if [ -s "$PREBUILT_ICON" ] && [ "$expected_hash" = "$actual_hash" ]; then
            cp "$PREBUILT_ICON" "$APP_PATH/Contents/Resources/AppIcon.icns"
            echo "   ↳ Utilisation de l'icône précompilée vérifiée"
        else
            rm -rf "$ICONSET"
            echo "❌ Échec de la conversion de l'icône et aucune version précompilée correspondante" >&2
            exit 1
        fi
    fi
    rm -rf "$ICONSET"
    [ -s "$APP_PATH/Contents/Resources/AppIcon.icns" ] || { echo "❌ Icône manquante ou vide" >&2; exit 1; }
    ICON_PLIST_KEY='<key>CFBundleIconFile</key><string>AppIcon.icns</string>'
    echo "   ✓ OK"
else
    echo "⚠️  MyTranslator.png absent - app sans icône personnalisée"
fi

SWIFT_SRC="$SCRIPT_DIR/Sources/MyTranslatorApp.swift"
if [ ! -f "$SWIFT_SRC" ]; then
    echo "❌ Source Swift absente : $SWIFT_SRC"
    exit 1
fi

echo "→ Compilation Swift..."
swiftc -module-cache-path "$BUILD_TMP_DIR/clang-cache" -framework Cocoa -framework Carbon -framework AVFoundation -framework FoundationModels -O "$SWIFT_SRC" "$SCRIPT_DIR/Sources/UILocalization.swift" "$SCRIPT_DIR/Sources/TranslationProcess.swift" -o "$APP_PATH/Contents/MacOS/MyTranslator"
echo "   ✓ Binaire compilé"

cat > "$APP_PATH/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MyTranslator</string>
    <key>CFBundleIdentifier</key><string>com.user.mytranslator</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
    <key>CFBundleExecutable</key><string>MyTranslator</string>
    <key>MyTranslatorLastCompiled</key><string>${LAST_COMPILED}</string>
    <key>MyTranslatorBuildDate</key><string>${BUILD_DATE}</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    ${ICON_PLIST_KEY}
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_PATH/Contents/PkgInfo"
touch "$APP_PATH/Contents/Resources/AppIcon.icns" "$APP_PATH/Contents/Info.plist" "$APP_PATH"

SIGNING_IDENTITY="${MYTRANSLATOR_SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development:/ { print $2; exit }')"
fi

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "→ Signature stable : $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$LOCAL_TRANSLATOR_PATH"
    codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none "$APP_PATH"
    codesign --verify --deep --strict "$APP_PATH"
    echo "   ✓ Bundle signé et vérifié"
else
    echo "⚠️  Aucun certificat Apple Development trouvé."
    echo "   L'autorisation Accessibilité pourra être redemandée après chaque reconstruction."
    codesign --force --deep --sign - --identifier com.user.mytranslator "$APP_PATH"
fi

echo

if [ -d "$FINAL_APP_PATH" ]; then
    mv "$FINAL_APP_PATH" "$STAGING_DIR/Previous-MyTranslator.app"
fi
if ! mv "$APP_PATH" "$FINAL_APP_PATH"; then
    [ ! -d "$STAGING_DIR/Previous-MyTranslator.app" ] || mv "$STAGING_DIR/Previous-MyTranslator.app" "$FINAL_APP_PATH"
    exit 1
fi
printf '%s\n' "$BUILD_NUMBER" > "$VERSION_FILE"
echo "✅ MyTranslator.app créée dans : $SCRIPT_DIR"
echo "→ Build : $BUILD_NUMBER"
echo "→ Dernière compilation : $LAST_COMPILED"
echo "→ Logo utilisé : $LOGO_PNG"
echo "→ Config UI : menu MyTranslator > Réglages"
echo "→ Stockage des réglages : préférences macOS UserDefaults"
echo

echo "Astuce : ferme l'ancienne app avant de tester la nouvelle."

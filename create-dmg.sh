#!/bin/bash
set -e

APP_NAME="Mélangeur de Son"
DMG_NAME="MenuMixer"
VERSION="${VERSION:-1.0.0}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Build Release ==="
xcodebuild -project "$PROJECT_DIR/MelangeurDeSon.xcodeproj" \
    -scheme MelangeurDeSon \
    -configuration Release \
    clean build \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -5

# Trouver le binaire
BUILD_DIR=$(xcodebuild -project "$PROJECT_DIR/MelangeurDeSon.xcodeproj" \
    -scheme MelangeurDeSon \
    -configuration Release \
    -showBuildSettings 2>/dev/null | grep " BUILT_PRODUCTS_DIR" | awk '{print $3}')

APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERREUR: $APP_PATH introuvable"
    exit 1
fi

echo "=== Signature ad-hoc ==="
codesign --force --sign - "$APP_PATH/Contents/MacOS/$APP_NAME"
codesign --force --sign - "$APP_PATH"
echo "App signée"

echo "=== Création du DMG ==="

DMG_TEMP="$PROJECT_DIR/build/dmg-temp"
DMG_OUTPUT="$PROJECT_DIR/build/${DMG_NAME}-${VERSION}.dmg"

# Nettoyer
rm -rf "$DMG_TEMP"
rm -f "$DMG_OUTPUT"
mkdir -p "$DMG_TEMP"
mkdir -p "$PROJECT_DIR/build"

# Copier l'app et créer le lien vers Applications
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Créer le DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

# Nettoyer
rm -rf "$DMG_TEMP"

echo ""
echo "=== DMG créé ==="
echo "$DMG_OUTPUT"
echo ""
echo "Note: sur l'autre Mac, si Gatekeeper bloque, exécuter :"
echo "  xattr -cr /Applications/Mélangeur\ de\ Son.app"
echo ""

if [ "${CI:-}" != "true" ]; then
    open -R "$DMG_OUTPUT"
fi

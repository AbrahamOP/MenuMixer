#!/bin/bash
set -e

APP_NAME="MenuMixer"
DMG_NAME="MenuMixer"
VERSION="${VERSION:-1.2.0}"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Build Release ==="
xcodebuild -project "$PROJECT_DIR/MenuMixer.xcodeproj" \
    -scheme MenuMixer \
    -configuration Release \
    clean build \
    CODE_SIGNING_ALLOWED=NO \
    2>&1 | tail -5

# Trouver le binaire
BUILD_DIR=$(xcodebuild -project "$PROJECT_DIR/MenuMixer.xcodeproj" \
    -scheme MenuMixer \
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

# Vérifier create-dmg
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "ERREUR: create-dmg n'est pas installé."
    echo "       Lance : brew install create-dmg"
    exit 1
fi

# (Re)générer le background PNG si absent
BACKGROUND="$PROJECT_DIR/Resources/dmg-background.png"
if [ ! -f "$BACKGROUND" ]; then
    echo "=== Génération du background PNG ==="
    swift "$PROJECT_DIR/scripts/generate-dmg-background.swift" "$BACKGROUND"
fi

echo "=== Création du DMG ==="

DMG_STAGING="$PROJECT_DIR/build/dmg-staging"
DMG_OUTPUT="$PROJECT_DIR/build/${DMG_NAME}-${VERSION}.dmg"

# Nettoyer
rm -rf "$DMG_STAGING"
rm -f "$DMG_OUTPUT"
mkdir -p "$DMG_STAGING"
mkdir -p "$PROJECT_DIR/build"

# Staging : uniquement l'app, create-dmg ajoutera le raccourci Applications
cp -R "$APP_PATH" "$DMG_STAGING/"

# Positions : doivent être cohérentes avec Resources/dmg-background.png.
# Origine Finder = haut-gauche ; le script Swift utilise AppKit (bas-gauche)
# et positionne la flèche entre les deux icônes à y_finder ≈ 180.
create-dmg \
    --volname "$APP_NAME" \
    --background "$BACKGROUND" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 120 \
    --text-size 13 \
    --icon "${APP_NAME}.app" 160 180 \
    --hide-extension "${APP_NAME}.app" \
    --app-drop-link 440 180 \
    --no-internet-enable \
    "$DMG_OUTPUT" \
    "$DMG_STAGING/"

# Nettoyer
rm -rf "$DMG_STAGING"

echo ""
echo "=== DMG créé ==="
echo "$DMG_OUTPUT"
echo ""
echo "Installation sur une autre machine :"
echo "  1. Glisser MenuMixer.app dans /Applications depuis le DMG"
echo "  2. Dans Terminal :"
echo "     xattr -cr /Applications/MenuMixer.app && open /Applications/MenuMixer.app"
echo ""

if [ "${CI:-}" != "true" ]; then
    open -R "$DMG_OUTPUT"
fi

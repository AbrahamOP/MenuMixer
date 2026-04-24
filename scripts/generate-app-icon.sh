#!/bin/bash
# Génère Resources/AppIcon.icns à partir de Resources/AppIcon-source.png (1024x1024).
# Crée toutes les tailles requises par macOS.
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$PROJECT_DIR/Resources/AppIcon-source.png"
ICNS="$PROJECT_DIR/Resources/AppIcon.icns"
ICONSET="$PROJECT_DIR/build/AppIcon.iconset"

if [ ! -f "$SRC" ]; then
    echo "ERREUR : $SRC introuvable."
    echo "       Sauve le logo (1024x1024 PNG) à cet emplacement puis relance."
    exit 1
fi

# Vérifier dimensions
DIMS=$(sips -g pixelWidth -g pixelHeight "$SRC" 2>/dev/null | awk '/pixelWidth|pixelHeight/ {print $2}' | tr '\n' 'x' | sed 's/x$//')
echo "Source : $SRC ($DIMS px)"

# Nettoyer / préparer
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# macOS app icon : 10 tailles (1x + 2x de chaque)
echo "=== Génération des tailles ==="
sips -z 16 16     "$SRC" --out "$ICONSET/icon_16x16.png"       >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_16x16@2x.png"    >/dev/null
sips -z 32 32     "$SRC" --out "$ICONSET/icon_32x32.png"       >/dev/null
sips -z 64 64     "$SRC" --out "$ICONSET/icon_32x32@2x.png"    >/dev/null
sips -z 128 128   "$SRC" --out "$ICONSET/icon_128x128.png"     >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_128x128@2x.png"  >/dev/null
sips -z 256 256   "$SRC" --out "$ICONSET/icon_256x256.png"     >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_256x256@2x.png"  >/dev/null
sips -z 512 512   "$SRC" --out "$ICONSET/icon_512x512.png"     >/dev/null
cp                 "$SRC"        "$ICONSET/icon_512x512@2x.png"

echo "=== Conversion en .icns ==="
iconutil -c icns "$ICONSET" -o "$ICNS"
rm -rf "$ICONSET"

echo "Généré : $ICNS"
ls -lh "$ICNS"

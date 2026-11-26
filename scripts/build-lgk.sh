#!/bin/sh
# Builds the LiquidGlassKit core (Swift) as a standalone dylib and stages it into the prefs bundle.
# Needs macOS + Xcode (swiftc). Any failure here is non-fatal for the package.
set -e
OUT="$1"
SRC="$(cd "$(dirname "$0")/.." && pwd)/liquidass12prefs/LGK"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "[LGK] xcrun not found (not macOS?); skipping"
  exit 1
fi

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
DEST="$OUT/LGK"
mkdir -p "$DEST"

xcrun --sdk iphoneos swiftc \
  -target arm64-apple-ios12.2 -sdk "$SDK" \
  -swift-version 5 -O -wmo \
  -emit-library -module-name LGKGlass \
  -Xlinker -install_name -Xlinker "/Library/PreferenceBundles/LiquidAss12Prefs.bundle/LGK/LGKCore.dylib" \
  -Xlinker -rpath -Xlinker /usr/lib/swift \
  -framework UIKit -framework Metal -framework MetalKit \
  -framework MetalPerformanceShaders -framework CoreVideo -framework QuartzCore \
  "$SRC"/*.swift \
  -o "$DEST/LGKCore.dylib"

cp "$SRC"/*.metal "$DEST/"
ldid -S "$DEST/LGKCore.dylib"
echo "[LGK] built $(du -h "$DEST/LGKCore.dylib" | cut -f1) LGKCore.dylib"

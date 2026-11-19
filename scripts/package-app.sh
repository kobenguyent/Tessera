#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="1.0.0"
BUILD_NUMBER="1"
GITHUB_REPO="kobenguyent/Tessera"
ARCH_MODE="native" # native | universal
OUTPUT_DIR="$ROOT_DIR/build"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="${2#v}"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --github-repo)
      GITHUB_REPO="$2"
      shift 2
      ;;
    --arch)
      ARCH_MODE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

APP_NAME="Tessera"
BUNDLE_ID="com.kobenguyent.Tessera"
APP_BUNDLE="$OUTPUT_DIR/${APP_NAME}.app"
DMG_STAGING="$OUTPUT_DIR/dmg-staging"

echo "==> Packaging ${APP_NAME} v${VERSION} (mode: ${ARCH_MODE}, repo: ${GITHUB_REPO})"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# 1. Build Release Binaries (GUI App + Companion CLI)
if [[ "$ARCH_MODE" == "universal" ]]; then
  echo "==> Building universal binaries (arm64 + x86_64)..."
  swift build -c release --arch arm64 --arch x86_64
  BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
  ARCH_LABEL="universal"
else
  HOST_ARCH="$(uname -m)"
  echo "==> Building native release binaries (${HOST_ARCH})..."
  swift build -c release
  BIN_DIR="$(swift build -c release --show-bin-path)"
  ARCH_LABEL="${HOST_ARCH}"
fi

GUI_BIN="${BIN_DIR}/Tessera"
CLI_BIN="${BIN_DIR}/tessera-cli"

if [[ ! -x "$GUI_BIN" ]]; then
  echo "ERROR: Expected GUI binary at ${GUI_BIN}" >&2
  exit 1
fi
if [[ ! -x "$CLI_BIN" ]]; then
  echo "ERROR: Expected CLI binary at ${CLI_BIN}" >&2
  exit 1
fi

echo "==> Binary architecture check:"
lipo -info "$GUI_BIN" || file "$GUI_BIN"
lipo -info "$CLI_BIN" || file "$CLI_BIN"

# 2. Generate App Icon (.icns)
ICON_PATH="$OUTPUT_DIR/Tessera.icns"
echo "==> Generating Tessera.icns..."
swift "$ROOT_DIR/scripts/generate-icon.swift" "$ICON_PATH"

# 3. Assemble Tessera.app Bundle
echo "==> Assembling ${APP_BUNDLE}..."
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Helpers" "$APP_BUNDLE/Contents/Resources"
cp "$GUI_BIN" "$APP_BUNDLE/Contents/MacOS/Tessera"
cp "$CLI_BIN" "$APP_BUNDLE/Contents/Helpers/tessera"
chmod +x "$APP_BUNDLE/Contents/MacOS/Tessera" "$APP_BUNDLE/Contents/Helpers/tessera"
cp "$ICON_PATH" "$APP_BUNDLE/Contents/Resources/Tessera.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>Tessera</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Tessera uses Apple Events to create window layouts, split panes, and run startup commands in terminals such as iTerm2 and Apple Terminal.</string>
    <key>TesseraGitHubRepo</key>
    <string>${GITHUB_REPO}</string>
</dict>
</plist>
EOF

# 4. Codesign (Developer ID if configured in CI, otherwise ad-hoc sign for Apple Silicon compatibility)
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  echo "==> Signing with Developer ID identity: ${CODESIGN_IDENTITY}"
  codesign --force --deep --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$APP_BUNDLE"
else
  echo "==> Applying ad-hoc signature..."
  codesign --force --deep --sign - "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"

# 5. Create ZIP archive
ZIP_NAME="${APP_NAME}-${VERSION}-macOS-${ARCH_LABEL}.zip"
ZIP_PATH="$OUTPUT_DIR/${ZIP_NAME}"
echo "==> Creating ZIP archive: ${ZIP_NAME}"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# 6. Create DMG Disk Image with /Applications drag-and-drop link
DMG_NAME="${APP_NAME}-${VERSION}-macOS-${ARCH_LABEL}.dmg"
DMG_PATH="$OUTPUT_DIR/${DMG_NAME}"
echo "==> Creating DMG disk image: ${DMG_NAME}"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_STAGING" "$ICON_PATH"

# 7. Create standalone CLI tarball
CLI_TAR_NAME="tessera-cli-${VERSION}-macOS-${ARCH_LABEL}.tar.gz"
CLI_TAR_PATH="$OUTPUT_DIR/${CLI_TAR_NAME}"
echo "==> Creating standalone CLI tarball: ${CLI_TAR_NAME}"
tar -C "$APP_BUNDLE/Contents/Helpers" -czf "$CLI_TAR_PATH" tessera

# 8. Generate SHA256SUMS.txt (used by Tessera in-app Auto-Update cryptographic verifier)
echo "==> Generating SHA256SUMS.txt..."
(
  cd "$OUTPUT_DIR"
  shasum -a 256 "$DMG_NAME" "$ZIP_NAME" "$CLI_TAR_NAME" > SHA256SUMS.txt
)

echo "==> Packaging complete! Artifacts in ${OUTPUT_DIR}:"
ls -lh "$OUTPUT_DIR"
cat "$OUTPUT_DIR/SHA256SUMS.txt"

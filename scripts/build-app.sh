#!/usr/bin/env bash
# Builds build/Space Maker.app (release), signed so macOS permission grants survive rebuilds.
# Signing identity: $SPACE_MAKER_SIGN_IDENTITY, else the first "Apple Development" identity in the keychain.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product SpaceMaker
swift build -c release --product space-maker-move-helper
swift build -c release --product space-maker-mcp
bin="$(swift build -c release --show-bin-path)"

app="build/Space Maker.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp App/Info.plist "$app/Contents/Info.plist"
cp "$bin/SpaceMaker" "$bin/space-maker-move-helper" "$bin/space-maker-mcp" "$app/Contents/MacOS/"

identity="${SPACE_MAKER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -1)}"
if [[ -z "$identity" ]]; then
  echo "No Apple Development signing identity found; set SPACE_MAKER_SIGN_IDENTITY." >&2
  exit 1
fi
codesign --force --sign "$identity" --identifier com.mdrum.space-maker.move-helper "$app/Contents/MacOS/space-maker-move-helper"
codesign --force --sign "$identity" --identifier com.mdrum.space-maker.mcp "$app/Contents/MacOS/space-maker-mcp"
codesign --force --sign "$identity" "$app"
codesign --verify --strict "$app"
echo "$app"

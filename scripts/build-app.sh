#!/bin/bash
# Builds build/Switchy.app. Usage: scripts/build-app.sh [--install]
#   --install  also copies it to /Applications and relaunches it.
#
# Signing: uses $SWITCHY_SIGN_IDENTITY, else the first "Apple Development" identity, else ad-hoc.
# A real identity matters: macOS ties the Accessibility permission to the signature, so an
# ad-hoc build loses the permission on every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product Switchy
BIN="$(swift build -c release --show-bin-path)/Switchy"

APP=build/Switchy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Switchy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# App icon: Resources/AppIcon.icon (Icon Composer document). actool turns it into Assets.car for
# macOS 26+ (system-drawn shape) plus AppIcon.icns, already shaped, for older macOS.
ICON_TMP="$(mktemp -d)"
# actool needs absolute paths, and reports problems on stdout, so show its output only on failure.
if ! ACTOOL_LOG="$(xcrun actool "$PWD/Resources/AppIcon.icon" --compile "$ICON_TMP" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon --output-partial-info-plist "$ICON_TMP/partial.plist" \
    --errors --warnings --output-format human-readable-text 2>&1)"; then
    echo "$ACTOOL_LOG" >&2
    exit 1
fi
cp "$ICON_TMP/Assets.car" "$ICON_TMP/AppIcon.icns" "$APP/Contents/Resources/"
rm -rf "$ICON_TMP"

IDENTITY="${SWITCHY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($( [ "$IDENTITY" = "-" ] && echo "ad-hoc signed" || echo "signed with ${IDENTITY:0:10}…"))"

if [ "${1:-}" = "--install" ]; then
    pkill -x Switchy 2>/dev/null || true
    rm -rf /Applications/Switchy.app
    cp -R "$APP" /Applications/Switchy.app
    open /Applications/Switchy.app
    echo "Installed to /Applications/Switchy.app"
fi

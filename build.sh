#!/bin/zsh
# Build Sweeply.app into build.noindex/ (a .noindex folder, so Spotlight and
# Launchpad don't list the build copy as a second app).
#
#   ./build.sh            build a universal (Apple silicon + Intel) app
#   ./build.sh --install  also copy it to /Applications
#   ./build.sh --dmg      also make build.noindex/Sweeply-<version>.dmg for a GitHub release
set -euo pipefail
# The Xcode toolchain is required: the Command Line Tools lack SwiftUI's macro plugins.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")"

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/Sweeply"

APP=build.noindex/Sweeply.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sweeply"
# Debug symbols carry the build folder's full path (user name included); the app doesn't need them.
strip -S "$APP/Contents/MacOS/Sweeply"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
echo "Built $APP"

case "${1:-}" in
--install)
  if [[ -d /Applications/Sweeply.app ]]; then
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' /Applications/Sweeply.app/Contents/Info.plist)" == "com.weijiazhao.sweeply" ]] \
      || { echo "/Applications/Sweeply.app is a different app; not replacing it"; exit 1; }
    rm -rf /Applications/Sweeply.app
  fi
  ditto "$APP" /Applications/Sweeply.app
  "$LSREGISTER" -f /Applications/Sweeply.app
  echo "Installed /Applications/Sweeply.app"
  ;;
--dmg)
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
  STAGE=build.noindex/dmg
  DMG="build.noindex/Sweeply-$VERSION.dmg"
  # Only the newest dmg is kept; older ones are on the GitHub releases.
  rm -rf "$STAGE" build.noindex/Sweeply-*.dmg(N)
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/Sweeply.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Sweeply $VERSION" -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
  rm -rf "$STAGE"
  echo "Made $DMG"
  ;;
esac

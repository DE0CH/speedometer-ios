#!/bin/bash
# Selects the newest released Xcode on the runner (no beta, no release candidate: the xcode-27 image's Xcode_27.2.app
# is the 27.2 RC) and generates the project. Run from ios/ by .github/workflows/ios.yml.
set -eo pipefail
XCODE=$(for x in /Applications/Xcode*.app; do readlink -f "$x"; done | sort -u | grep -viE "beta|candidate" \
  | while read -r x; do echo "$(defaults read "$x/Contents/Info" CFBundleShortVersionString) $x"; done \
  | sort -V | tail -1 | cut -d' ' -f2-)
echo "Using $XCODE"; sudo xcode-select -s "$XCODE"; xcodebuild -version
echo "::notice title=Xcode::$(xcodebuild -version | tr '\n' ' ') $(xcrun --sdk iphonesimulator --show-sdk-version)"
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen
[ -z "${BUILD_NUMBER:-}" ] || sed -i '' "s/BUILD_NUMBER: \"1\"/BUILD_NUMBER: \"$BUILD_NUMBER\"/" project.yml
xcodegen generate --quiet

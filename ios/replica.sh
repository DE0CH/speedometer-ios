#!/bin/bash
# The phone replica on one simulator: $DEVICE (e.g. "iPhone 17") in $APPEARANCE (light/dark), every UI test or only
# those in $TESTS. Writes $RUNNER_TEMP/test.log and $RUNNER_TEMP/screens (screenshots, replica.mp4); exits non-zero
# unless the tests pass. Run from ios/ after xcodegen, by .github/workflows/ios.yml.
set -eo pipefail
trap 'echo "::error title=${DEVICE:-replica}::line $LINENO: $BASH_COMMAND exited $?"' ERR
UDID=$(xcrun simctl list devices available -j | python3 -c "
import json,sys,re
d=json.load(sys.stdin)['devices']
rts=sorted((k for k in d if 'iOS' in k), key=lambda k:[int(x) for x in re.findall(r'\d+',k)])
for rt in reversed(rts):
    for dev in d[rt]:
        if dev['name']==sys.argv[1]: print(dev['udid']); sys.exit()
" "$DEVICE")
[ -n "$UDID" ] || { echo "no $DEVICE simulator"; exit 1; }
# Which tests: all of them, or the ones named in $TESTS (space-separated, e.g. testMatchesReference).
ONLY=(); for t in ${TESTS:-}; do ONLY+=("-only-testing:SpeedometerUITests/SpeedometerUITests/$t"); done
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b > /dev/null
# The displays the simulator has (iPhone Duo: the outer and the inner one), and any pose control simctl offers.
# Annotations carry them (and the results below) to the run page, where they read without a log download.
note() { local t=$1; shift; local m; m=$(head -c 3500 || true); m=${m//'%'/'%25'}; m=${m//$'\n'/'%0A'}; echo "::notice title=$DEVICE $t::$m"; }
{ xcrun simctl io "$UDID" enumerate 2>&1 | grep -E "Default (width|height)" | paste - - || true; } | note "displays"
{ xcrun simctl help 2>&1 | grep -iE "pose|hinge|fold|posture|display" || echo "(no pose, hinge or fold command in simctl help)"
  echo "-- simctl ui options:"; { xcrun simctl ui 2>&1 || true; } | grep -E "^    [a-z_]+$" || true; } | note "simctl pose commands"
xcrun simctl ui "$UDID" appearance "$APPEARANCE" 2>&1 | note "appearance $APPEARANCE" || true
xcrun simctl status_bar "$UDID" override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100 || true
# Location permission up front; the test also answers the prompt if it shows.
xcrun simctl privacy "$UDID" grant location dev.de0ch.speedometer || true
( sleep 1200; echo "watchdog: stopping xcodebuild" >> "$RUNNER_TEMP/test.log"; pkill -INT xcodebuild ) & WATCHDOG=$!
mkdir -p "$RUNNER_TEMP/screens"
COMMON=(-project Speedometer.xcodeproj -scheme Speedometer -configuration Release -destination "id=$UDID"
  -derivedDataPath DerivedData ONLY_ACTIVE_ARCH=YES ARCHS=arm64 CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO)
xcodebuild build-for-testing "${COMMON[@]}" > "$RUNNER_TEMP/build.log" 2>&1 || true
grep -E "error:|\*\* TEST BUILD" "$RUNNER_TEMP/build.log" | head -20 || true
# A video of the whole run: the rotations, frame by frame (the test logs "ROTATE <mode> <epoch>").
python3 -c "import time; print(time.time())" > "$RUNNER_TEMP/screens/video-start.txt"
xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$RUNNER_TEMP/screens/replica.mp4" 2>/dev/null & RECORDER=$!
xcodebuild test-without-building "${COMMON[@]}" "${ONLY[@]}" -resultBundlePath "$RUNNER_TEMP/ui.xcresult" \
  -test-timeouts-enabled YES -maximum-test-execution-time-allowance 600 > "$RUNNER_TEMP/test.log" 2>&1 || true
kill $WATCHDOG 2>/dev/null || true
kill -INT $RECORDER 2>/dev/null || true; wait $RECORDER 2>/dev/null || true
tail -25 "$RUNNER_TEMP/test.log"
grep -E "error:|\*\* TEST|Test Case .*(passed|failed)|XCTAssert" "$RUNNER_TEMP/test.log" | head -40 || true
grep -E "COMPARE |ROTATE " "$RUNNER_TEMP/test.log" || true   # native vs the HTML, per state
xcrun xcresulttool export attachments --path "$RUNNER_TEMP/ui.xcresult" --output-path "$RUNNER_TEMP/att" >/dev/null 2>&1 || true
python3 - "$RUNNER_TEMP/att" "$RUNNER_TEMP/screens" <<'PY' || true
import json, os, shutil, sys
src, dst = sys.argv[1:]
n = 0
for t in json.load(open(os.path.join(src, "manifest.json"))):
    for a in t.get("attachments", []):
        f = a.get("exportedFileName", "")
        if f.endswith(".png"):
            n += 1; shutil.copy(os.path.join(src, f), os.path.join(dst, "%02d-%s.png" % (n, a.get("suggestedHumanReadableName", f).split("_")[0])))
print(f"screenshots: {n}")
PY
{ grep -iE "storyboard|ibtool|LaunchScreen" "$RUNNER_TEMP/build.log" | grep -viE "^\s*(cd|export|builtin-|/Applications)" | head -20
  sb=$(find DerivedData/Build/Products -maxdepth 3 -name "LaunchScreen.storyboardc" | head -1)
  [ -z "$sb" ] || { ls -la "$sb"; plutil -p "$sb/Info.plist"; }; } | note "storyboard build" || true
# Why the app crashed, if it did: the newest crash report's exception and first frames.
{ f=$(ls -t ~/Library/Logs/DiagnosticReports/Speedometer*.ips 2>/dev/null | head -1)
  [ -z "$f" ] || { echo "$f"; tail -n +2 "$f" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(json.dumps(d.get('exception'))); print(json.dumps(d.get('asi') or d.get('lastExceptionBacktrace',[])[:3])[:1500])
t=[x for x in d.get('threads',[]) if x.get('triggered')]
for fr in (t[0]['frames'][:12] if t else []): print(fr.get('symbol'), fr.get('sourceFile',''), fr.get('sourceLine',''))
" 2>&1; }; } | note "crash" || true
grep -E "COMPARE " "$RUNNER_TEMP/test.log" | note "comparisons" || true
grep -E "error:|XCTAssert|Test Case .*(passed|failed)|\*\* TEST" "$RUNNER_TEMP/test.log" | head -40 | note "results" || true
grep -qE "\*\* TEST (EXECUTE )?SUCCEEDED \*\*" "$RUNNER_TEMP/test.log"

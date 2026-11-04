#!/bin/bash
# The real launch screen, as iOS shows it, on the iPhone Duo closed and open: a video of each display from just before
# `simctl launch` until the app is up, plus the Mac's screen (Device Hub). The UI tests' `-launch-screen` flag only
# shows the storyboard as an app screen; this is what a person sees on a cold start. Run from ios/ after replica.sh
# (the app is installed), with Device Hub open (duo-host.sh). Writes $RUNNER_TEMP/launch/.
set -eo pipefail
OUT="$RUNNER_TEMP/launch"; mkdir -p "$OUT"
UDID=$(xcrun simctl list devices booted -j | python3 -c "import json,sys;print([d['udid'] for r in json.load(sys.stdin)['devices'].values() for d in r if d['name']=='iPhone Duo'][0])")
APP=dev.de0ch.speedometer
# Each pose in all four orientations (Device Hub's Rotate turns the device a quarter clockwise; the Duo's safe area
# moves with it), then once more upright for iOS's cached launch snapshot.
capture() {   # name display
  xcrun simctl terminate "$UDID" "$APP" 2>/dev/null || true; sleep 3
  screencapture -v -V 9 -x "$OUT/mac-$1.mov" > /dev/null 2>&1 & local mac=$!
  xcrun simctl io "$UDID" recordVideo --codec=h264 --display="$2" --force "$OUT/$1.mp4" 2>/dev/null & local rec=$!
  sleep 2
  xcrun simctl launch "$UDID" "$APP" > /dev/null
  sleep 5
  kill -INT $rec 2>/dev/null || true; wait $rec 2>/dev/null || true
  wait $mac 2>/dev/null || true
  xcrun simctl io "$UDID" screenshot --display="$2" "$OUT/$1-after.png" > /dev/null 2>&1 || true
}
for pose in closed open; do
  ./duo-host.sh "$pose"; sleep 8
  display=$([ "$pose" = open ] && echo primary-1 || echo primary)
  for turn in 0 90 180 270; do
    capture "$pose-$turn" "$display"
    ./duo-host.sh rotate; sleep 4
  done
  capture "$pose-0-again" "$display"
done
ls -la "$OUT"

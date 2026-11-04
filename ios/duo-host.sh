#!/bin/bash
# Folds and unfolds the iPhone Duo simulator for the UI tests. Neither simctl nor XCUIDevice has a pose control; Device
# Hub does (the Closed, Partially Open and Open buttons under the device), and on a GitHub runner a posted mouse click
# presses them (System Events can't read Device Hub's window there: no accessibility grant).
#   duo-host.sh start     open Device Hub on the booted Duo, then serve the tests' requests until killed: the test
#                         writes "<n> <closed|partial|open|rotate>" to $DUO_DIR/request; this clicks and writes <n> to
#                         $DUO_DIR/ack
#   duo-host.sh <pose>    one click
# The button positions are Device Hub's on the runner's 1024 x 768 screen (Xcode 27.1, its window as it opens).
set -eo pipefail
DUO_DIR=${DUO_DIR:-/tmp/duo-host}
CLICK="${RUNNER_TEMP:-/tmp}/duo-click"
if [ ! -x "$CLICK" ]; then
  cat > "$CLICK.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let x = Double(CommandLine.arguments[1])!, y = Double(CommandLine.arguments[2])!
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: y), mouseButton: .left)!
        .post(tap: .cghidEventTap)
    usleep(80_000)
}
SWIFT
  swiftc -O -o "$CLICK" "$CLICK.swift"
fi
press() {
  case $1 in
    rotate) "$CLICK" 638 679 ;;
    closed) "$CLICK" 675 679 ;;
    partial) "$CLICK" 709 679 ;;
    open) "$CLICK" 743 679 ;;
    *) echo "duo-host: no pose $1" >&2; return 1 ;;
  esac
  echo "duo-host: $1 $(date +%s)"
}
[ "$1" = start ] || { press "$1"; exit; }
open -a "$(xcode-select -p)/../Applications/DeviceHub.app"
sleep 20   # its window and the device canvas
rm -rf "$DUO_DIR"; mkdir -p "$DUO_DIR"; chmod 777 "$DUO_DIR"
echo "duo-host: serving $DUO_DIR"
while true; do
  if [ -s "$DUO_DIR/request" ]; then
    read -r n pose < "$DUO_DIR/request"; rm -f "$DUO_DIR/request"
    press "$pose" || true
    echo "$n" > "$DUO_DIR/ack"
  fi
  sleep 0.2
done

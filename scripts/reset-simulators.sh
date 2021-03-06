#!/bin/bash

set -o pipefail
set -e

export REALM_SWIFT_VERSION=3.0.1
if [[ -z "$DEVELOPER_DIR" ]]; then
    export DEVELOPER_DIR="$(xcode-select -p)"
fi

while pgrep -q Simulator; do
    # Kill all the current simulator processes as they may be from a
    # different Xcode version
    pkill Simulator 2>/dev/null || true
    # CoreSimulatorService doesn't exit when sent SIGTERM
    pkill -9 Simulator 2>/dev/null || true
done

# Run until we get a result since switching simulator versions often causes CoreSimulatorService to throw an exception.
devices=""
until [ "$devices" != "" ]; do
    devices="$(xcrun simctl list devices -j || true)"
done

# Shut down booted simulators
echo "$devices" | ruby -rjson -e 'puts JSON.parse($stdin.read)["devices"].flat_map { |d| d[1] }.select { |d| d["state"] == "Booted" && d["availability"] == "(available)" }.map { |d| d["udid"] }' | while read udid; do
    echo "shutting down simulator with ID: $udid"
    xcrun simctl shutdown $udid
done

# Erase all available simulators
echo "erasing simulators"
echo "$devices" | ruby -rjson -e 'puts JSON.parse($stdin.read)["devices"].flat_map { |d| d[1] }.select { |d| d["availability"] == "(available)" }.map { |d| d["udid"] }' | while read udid; do
    xcrun simctl erase $udid &
done
wait

xcrun simctl boot "iPhone 5" # React Native seems to want to test with this device

if [[ -a "${DEVELOPER_DIR}/Applications/Simulator.app" ]]; then
    open "${DEVELOPER_DIR}/Applications/Simulator.app"
fi

# Wait until the boot completes
echo "waiting for simulator to boot..."
until xcrun simctl list devices -j | ruby -rjson -e 'exit JSON.parse($stdin.read)["devices"].flat_map { |d| d[1] }.any? { |d| d["availability"] == "(available)" && d["state"] == "Booted" }'; do
    sleep 1
done

# Wait until the simulator is fully booted by waiting for it to launch SpringBoard
xcrun simctl launch booted com.apple.springboard >/dev/null 2>&1 || true
echo "simulator booted"
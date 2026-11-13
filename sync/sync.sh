#!/usr/bin/env bash
# Copy Fiido Ride's database off the iPhone and convert it to data/fiido.sqlite.
# Prints "step <n> <total> <label>" before each stage, then the converter's row counts as JSON.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
set -a; source "$repo/.env"; set +a
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

store_dir="Library/Application Support"
pulled="$(mktemp -d)"
trap 'rm -rf "$pulled"' EXIT

pull() {
    xcrun devicectl device copy from --quiet --device "$SYNC_DEVICE" \
        --domain-type appDataContainer --domain-identifier org.mnalavadi.FiidoRide \
        --source "$store_dir/$1" --destination "$pulled/$1" >/dev/null
}

step() { echo "step $1 6 $2"; }

step 1 "Copying database"
pull default.store
# SQLite folds these into the main file now and then, so either can be missing.
step 2 "Copying journal"
pull default.store-wal || true
step 3 "Copying index"
pull default.store-shm || true

step 4 "Building converter"
(cd "$repo/ios-app/FiidoKit" && swift build -c release --product fiido-convert --quiet)
step 5 "Converting"
# Converting first means a copy torn by a write mid-pull fails here and never replaces the last good one.
"$repo/ios-app/FiidoKit/.build/release/fiido-convert" "$pulled/default.store" "$repo/data/fiido.sqlite"

step 6 "Saving"
mkdir -p "$repo/data/raw"
rm -f "$repo/data/raw"/default.store*
cp "$pulled"/default.store* "$repo/data/raw/"

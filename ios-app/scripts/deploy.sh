#!/usr/bin/env bash
# Build and install on the configured iPhone. The script lives in the iOS-App-Deploy project; see --help.
set -euo pipefail
(cd "$(dirname "$0")/.." && xcodegen generate --quiet)
exec "$HOME/code/projects/iOS-App-Deploy/scripts/deploy-ios.sh" fiido "$@"

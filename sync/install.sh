#!/usr/bin/env bash
# Install (or reinstall) the launchd agent that runs server.py at login and keeps it running.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
label="org.mnalavadi.fiido-sync"
plist="$HOME/Library/LaunchAgents/$label.plist"
uv="$(command -v uv)"

cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key>
    <array><string>$uv</string><string>run</string><string>--script</string><string>$repo/sync/server.py</string></array>
    <key>EnvironmentVariables</key>
    <dict><key>PATH</key><string>$(dirname "$uv"):/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/fiido-sync.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/fiido-sync.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "installed $label; log: ~/Library/Logs/fiido-sync.log"

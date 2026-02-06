#!/bin/bash

echo "Stopping ClaudeNotifier..."
launchctl unload ~/Library/LaunchAgents/com.claude-notifier.plist 2>/dev/null || true
pkill -f ClaudeNotifier 2>/dev/null || true

echo "Removing files..."
rm -rf ~/Applications/ClaudeNotifier.app
rm -rf ~/.claude-notifier
rm -f ~/Library/LaunchAgents/com.claude-notifier.plist

echo "Uninstallation complete!"

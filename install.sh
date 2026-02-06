#!/bin/bash
set -e

echo "Building ClaudeNotifier..."
swift build -c release

echo "Creating app bundle..."
mkdir -p ~/Applications/ClaudeNotifier.app/Contents/MacOS
cp .build/arm64-apple-macosx/release/ClaudeNotifier ~/Applications/ClaudeNotifier.app/Contents/MacOS/
cp scripts/Info.plist ~/Applications/ClaudeNotifier.app/Contents/

echo "Signing app..."
codesign -f -s - ~/Applications/ClaudeNotifier.app

echo "Installing scripts..."
mkdir -p ~/.claude-notifier/bin ~/.claude-notifier/queue
cp scripts/claude-permission-prompt ~/.claude-notifier/bin/
chmod +x ~/.claude-notifier/bin/claude-permission-prompt

echo "Installing LaunchAgent..."
cp scripts/com.claude-notifier.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.claude-notifier.plist 2>/dev/null || true

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Grant Accessibility permission to ClaudeNotifier in System Preferences"
echo "2. Add hook to ~/.claude/settings.json (see README.md)"

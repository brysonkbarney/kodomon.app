#!/bin/bash
# Kodomon installer
# Usage: curl -fsSL https://kodomon.app/install.sh | bash

set -e

BOLD="\033[1m"
GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

echo ""
echo "${BOLD}Installing Kodomon...${RESET}"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "${RED}Kodomon is macOS only.${RESET}"
    exit 1
fi

# Check macOS version (need 14+)
MACOS_VERSION=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MACOS_VERSION" -lt 14 ]]; then
    echo "${RED}Kodomon requires macOS 14 (Sonoma) or later.${RESET}"
    echo "You're running macOS $(sw_vers -productVersion)."
    exit 1
fi

# Get latest release from GitHub
echo "Fetching latest release..."
LATEST=$(curl -fsSL https://api.github.com/repos/brysonkbarney/kodomon/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$LATEST" ]]; then
    echo "${RED}Could not fetch latest release.${RESET}"
    exit 1
fi

echo "  Latest version: ${GREEN}${LATEST}${RESET}"

# Download DMG
DMG_URL="https://github.com/brysonkbarney/kodomon/releases/download/${LATEST}/Kodomon.dmg"
DMG_PATH="/tmp/Kodomon.dmg"

echo "Downloading Kodomon ${LATEST}..."
curl -fsSL -o "$DMG_PATH" "$DMG_URL"
echo "  ${GREEN}Downloaded${RESET}"

# Mount DMG
echo "Installing..."
MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse -noautoopen | grep "/Volumes" | awk '{print $3}')

# Copy to Applications
if [[ -d "/Applications/Kodomon.app" ]]; then
    rm -rf "/Applications/Kodomon.app"
fi
cp -R "${MOUNT_POINT}/Kodomon.app" /Applications/

# Unmount
hdiutil detach "$MOUNT_POINT" -quiet
rm -f "$DMG_PATH"
echo "  ${GREEN}Installed to /Applications${RESET}"

# Install hooks
echo "Setting up Claude Code hooks..."
KODOMON_DIR="$HOME/.kodomon"
HOOKS_DIR="$KODOMON_DIR/hooks"
mkdir -p "$HOOKS_DIR"

# Extract hook scripts from the app bundle
BUNDLE_HOOKS="/Applications/Kodomon.app/Contents/Resources/Hooks"
if [[ -d "$BUNDLE_HOOKS" ]]; then
    cp "$BUNDLE_HOOKS"/*.sh "$HOOKS_DIR/"
    chmod +x "$HOOKS_DIR"/*.sh
fi

touch "$KODOMON_DIR/events.jsonl"

# Merge Claude Code hooks into settings
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
    if grep -q "kodomon" "$CLAUDE_SETTINGS" 2>/dev/null; then
        echo "  ${GREEN}Claude Code hooks already configured${RESET}"
    else
        echo "  Adding hooks to existing Claude Code settings..."
        # Use jq if available, otherwise warn
        if command -v jq &>/dev/null; then
            TMP=$(mktemp)
            jq '.hooks.SessionStart += [{"hooks": [{"type": "command", "command": "~/.kodomon/hooks/session-start.sh"}]}] | .hooks.PostToolUse += [{"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "~/.kodomon/hooks/file-event.sh"}]}, {"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.kodomon/hooks/bash-event.sh"}]}] | .hooks.Stop += [{"hooks": [{"type": "command", "command": "~/.kodomon/hooks/session-stop.sh"}]}]' "$CLAUDE_SETTINGS" > "$TMP" && mv "$TMP" "$CLAUDE_SETTINGS"
            echo "  ${GREEN}Claude Code hooks added${RESET}"
        else
            echo "  Please add Kodomon hooks to ~/.claude/settings.json manually."
            echo "  See: https://github.com/brysonkbarney/kodomon#setup"
        fi
    fi
else
    mkdir -p "$HOME/.claude"
    cat > "$CLAUDE_SETTINGS" << 'SETTINGS'
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "~/.kodomon/hooks/session-start.sh"}]}],
    "PostToolUse": [
      {"matcher": "Write|Edit|MultiEdit", "hooks": [{"type": "command", "command": "~/.kodomon/hooks/file-event.sh"}]},
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "~/.kodomon/hooks/bash-event.sh"}]}
    ],
    "Stop": [{"hooks": [{"type": "command", "command": "~/.kodomon/hooks/session-stop.sh"}]}]
  }
}
SETTINGS
    echo "  ${GREEN}Claude Code hooks configured${RESET}"
fi

# Launch
echo ""
echo "Launching Kodomon..."
open /Applications/Kodomon.app

echo ""
echo "${GREEN}${BOLD}Kodomon is ready!${RESET}"
echo "Open Claude Code to start feeding your pet."
echo ""

#!/usr/bin/env bash
# Install script for spectre - Quick project switching for Claude Code

set -e

SPECTRE_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/spectre"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRE_SCRIPT="$SCRIPT_DIR/spectre.zsh"

echo "Installing spectre..."

# Create config directory if needed
if [[ ! -d "$SPECTRE_CONFIG_DIR" ]]; then
  echo "Creating config directory: $SPECTRE_CONFIG_DIR"
  mkdir -p "$SPECTRE_CONFIG_DIR"
fi

# Detect shell
SHELL_NAME="$(basename "$SHELL")"
case "$SHELL_NAME" in
  zsh)
    RC_FILE="$HOME/.zshrc"
    ;;
  bash)
    if [[ -f "$HOME/.bashrc" ]]; then
      RC_FILE="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]]; then
      RC_FILE="$HOME/.bash_profile"
    else
      RC_FILE="$HOME/.bashrc"
    fi
    ;;
  *)
    echo "Warning: Unsupported shell: $SHELL_NAME" >&2
    echo "Please manually source $SPECTRE_SCRIPT in your shell rc file" >&2
    exit 1
    ;;
esac

echo "Detected shell: $SHELL_NAME"
echo "RC file: $RC_FILE"

# Check if already sourced
SOURCE_LINE="source \"$SPECTRE_SCRIPT\""
if grep -Fxq "$SOURCE_LINE" "$RC_FILE" 2>/dev/null; then
  echo "✓ spectre already configured in $RC_FILE"
else
  echo "Adding source line to $RC_FILE"
  echo "" >> "$RC_FILE"
  echo "# spectre - Quick project switching for Claude Code" >> "$RC_FILE"
  echo "$SOURCE_LINE" >> "$RC_FILE"
  echo "✓ Added source line to $RC_FILE"
fi

echo ""
echo "Installation complete!"
echo ""
echo "To start using spectre, either:"
echo "  1. Restart your shell, or"
echo "  2. Run: source $RC_FILE"
echo ""
echo "Usage:"
echo "  spectre                  - Launch Claude in current directory"
echo "  spectre <project>        - Switch to project and launch Claude"
echo "  spectre add <name> [path] - Add project to registry"
echo "  spectre list             - List registered projects"
echo "  spectre remove <name>    - Remove project"
echo "  spectre path <name>      - Print project path"
echo ""
echo "Configuration:"
echo "  Set SPECTRE_CMD to customize the launch command (default: 'claude')"
echo "  Example: export SPECTRE_CMD=\"claude --dangerously-skip-permissions\""

#!/usr/bin/env bash
# Install ODrive into the running Omarchy shell.
#
#   ./install.sh          copy this checkout into ~/.config/omarchy/plugins
#   ./install.sh --link   symlink it instead (for active development)
#   ./install.sh --uninstall
#
# Copy is the default because the shell's file watcher reloads plugin code
# it can see change on disk. Re-run this script after editing and changes
# take effect immediately.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="ttt.odrive"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"
MODE="copy"
ENABLE_BAR=true

for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    --link) MODE="link" ;;
    --enable) ENABLE_BAR=true ;;
    --no-enable) ENABLE_BAR=false ;;
    --uninstall) MODE="uninstall" ;;
    -h|--help)
      cat <<EOF
Usage: ./install.sh [OPTIONS]

Install ODrive into the Omarchy shell.

Options:
  --copy         Copy plugin files into ~/.config/omarchy/plugins (default)
  --link         Symlink checkout into ~/.config/omarchy/plugins (for development)
  --no-enable    Do not automatically enable the widget in the Omarchy bar
  --uninstall    Remove ODrive plugin and CLI from Omarchy
  -h, --help     Show this help message
EOF
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

reload_shell() {
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
}

if [[ "$MODE" == "uninstall" ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  fi
  rm -rf "$PLUGIN_DIR"
  rm -f "$BIN_DIR/odrive"
  rm -f "$HOME/.local/share/applications/odrive.desktop"
  reload_shell
  echo "ODrive removed. Cloud credentials and config in ~/.config/odrive were left alone."
  exit 0
fi

# Check core dependencies
if ! command -v rclone >/dev/null 2>&1; then
  echo "Note: 'rclone' is not installed yet. Install it with: sudo pacman -S rclone"
fi
if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then
  echo "Note: 'fuse3' is not installed yet. Install it with: sudo pacman -S fuse3"
fi

# Pre-validate before installing
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$SRC" >/dev/null 2>&1 || {
    echo "Error: omarchy-plugin-validate failed." >&2
    exit 1
  }
fi

mkdir -p "$(dirname "$PLUGIN_DIR")" "$BIN_DIR"
rm -rf "$PLUGIN_DIR"

if [[ "$MODE" == "link" ]]; then
  ln -sfn "$SRC" "$PLUGIN_DIR"
  echo "Linked $SRC -> $PLUGIN_DIR"
else
  mkdir -p "$PLUGIN_DIR"
  cp -r "$SRC/manifest.json" "$SRC/ui" "$SRC/bin" "$SRC/lib" "$SRC/assets" "$PLUGIN_DIR/"
  chmod +x "$PLUGIN_DIR/bin/odrive"
  echo "Copied ODrive into $PLUGIN_DIR"
fi

ln -sfn "$PLUGIN_DIR/bin/odrive" "$BIN_DIR/odrive"
chmod +x "$BIN_DIR/odrive"
echo "Linked CLI engine to $BIN_DIR/odrive"

# Clean up any legacy standalone desktop entry
rm -f "$HOME/.local/share/applications/odrive.desktop"

reload_shell

if [[ "$ENABLE_BAR" == true ]] && command -v omarchy >/dev/null 2>&1; then
  if omarchy plugin list --json 2>/dev/null | python3 -c '
import json, sys
plugins = json.load(sys.stdin)
sys.exit(0 if any(p.get("id") == sys.argv[1] and p.get("enabled") for p in plugins) else 1)
' "$PLUGIN_ID" 2>/dev/null; then
    echo "ODrive is already enabled in the bar."
  else
    omarchy plugin enable "$PLUGIN_ID" right >/dev/null 2>&1 \
      && echo "Added ODrive to the bar (right section)." \
      || echo "Could not add widget automatically. Run: omarchy plugin enable $PLUGIN_ID right"
  fi
fi

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "Note: $BIN_DIR is not on your PATH; add it to run 'odrive' from a terminal." ;;
esac

echo
echo "🎉 ODrive ready!"
echo "  • Open bar widget: Click the Cloud icon in your Omarchy bar"
echo "  • Setup drive:     odrive setup"
echo "  • Status:          odrive status"
echo "  • Mount all:       odrive mount-all"

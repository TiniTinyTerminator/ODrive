#!/usr/bin/env bash
# Install ODrive into the Omarchy shell.
#
#   ./install.sh           Copy this checkout into ~/.config/omarchy/plugins
#   ./install.sh --enable  Install and enable on the right side of the bar
#   ./install.sh --link    Symlink it instead (for active development)
#   ./install.sh --uninstall Remove plugin from Omarchy
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="ttt.odrive"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
MODE="copy"
ENABLE_PLUGIN=false

for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    --link) MODE="link" ;;
    --enable) ENABLE_PLUGIN=true ;;
    --uninstall) MODE="uninstall" ;;
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
  rm -f "$DESKTOP_DIR/odrive.desktop"
  reload_shell
  echo "✓ ODrive removed. Cloud mounts and configs in ~/.config/odrive were preserved."
  exit 0
fi

# Pre-validate before installing
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  omarchy-plugin-validate "$SRC" || {
    echo "Error: Validation failed." >&2
    exit 1
  }
fi

mkdir -p "$(dirname "$PLUGIN_DIR")" "$BIN_DIR" "$DESKTOP_DIR"
rm -rf "$PLUGIN_DIR"

if [[ "$MODE" == "link" ]]; then
  ln -sfn "$SRC" "$PLUGIN_DIR"
  echo "✓ Linked $SRC -> $PLUGIN_DIR"
else
  mkdir -p "$PLUGIN_DIR"
  cp -r "$SRC/manifest.json" "$SRC/ui" "$SRC/bin" "$SRC/lib" "$SRC/assets" "$PLUGIN_DIR/"
  chmod +x "$PLUGIN_DIR/bin/odrive"
  echo "✓ Copied ODrive into $PLUGIN_DIR"
fi

# Link CLI executable to ~/.local/bin/odrive
ln -sf "$PLUGIN_DIR/bin/odrive" "$BIN_DIR/odrive"
chmod +x "$BIN_DIR/odrive"
echo "✓ Installed CLI to $BIN_DIR/odrive"

# Clean up any legacy desktop entry
rm -f "$DESKTOP_DIR/odrive.desktop"

reload_shell

if [[ "$ENABLE_PLUGIN" == true ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin enable "$PLUGIN_ID" right || true
    echo "✓ Enabled $PLUGIN_ID on the Omarchy bar (right section)"
  fi
fi

echo
echo "🎉 ODrive installation complete!"
echo "  • Bar widget: Click the Cloud icon in your Omarchy bar"
echo "  • CLI:        odrive status | odrive setup | odrive mount-all"

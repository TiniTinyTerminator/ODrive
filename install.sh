#!/usr/bin/env bash
# ==============================================================================
# ODrive Installer for Omarchy Linux
# Unified Cloud Drive Manager
# ==============================================================================
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="ttt.odrive"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="odrive-automount.service"

MODE="copy"
ENABLE_PLUGIN=false
BAR_SECTION="right"
SETUP_SYSTEMD=false

show_help() {
  cat <<EOF
ODrive Installer — Unified Cloud Drive Manager for Omarchy Linux

Usage:
  ./install.sh [OPTIONS]

Options:
  --copy              Install by copying plugin files (default)
  --link              Install by symlinking (recommended for active development)
  --enable            Enable the widget in the Omarchy bar immediately
  --section <pos>     Bar section to place the widget: left, center, right (default: right)
  --systemd           Install and enable the systemd user auto-mount service
  --uninstall         Remove the plugin and CLI from Omarchy
  -h, --help          Show this help message and exit

Examples:
  ./install.sh --enable             # Standard install & add to bar
  ./install.sh --link --enable      # Development mode with live linking
  ./install.sh --enable --systemd   # Install, enable on bar, and set up login auto-mount
  ./install.sh --uninstall          # Completely remove ODrive
EOF
}

# Parse command-line flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    --copy)
      MODE="copy"
      shift
      ;;
    --link)
      MODE="link"
      shift
      ;;
    --enable)
      ENABLE_PLUGIN=true
      shift
      ;;
    --section)
      BAR_SECTION="${2:-right}"
      shift 2
      ;;
    --systemd)
      SETUP_SYSTEMD=true
      shift
      ;;
    --uninstall)
      MODE="uninstall"
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run './install.sh --help' for usage." >&2
      exit 1
      ;;
  esac
done

reload_shell() {
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  fi
}

# ------------------------------------------------------------------------------
# Uninstall Mode
# ------------------------------------------------------------------------------
if [[ "$MODE" == "uninstall" ]]; then
  echo "Removing ODrive from Omarchy..."

  # Disable bar widget if enabled
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  fi

  # Stop and disable systemd service if present
  if systemctl --user is-enabled "$SERVICE_NAME" >/dev/null 2>&1; then
    systemctl --user stop "$SERVICE_NAME" >/dev/null 2>&1 || true
    systemctl --user disable "$SERVICE_NAME" >/dev/null 2>&1 || true
  fi
  rm -f "$SYSTEMD_USER_DIR/$SERVICE_NAME"

  # Remove plugin directory and CLI symlink
  rm -rf "$PLUGIN_DIR"
  rm -f "$BIN_DIR/odrive"
  rm -f "$DESKTOP_DIR/odrive.desktop"

  reload_shell

  echo "✓ ODrive has been uninstalled."
  echo "  Note: Cloud credentials and configuration in ~/.config/odrive were preserved."
  exit 0
fi

# ------------------------------------------------------------------------------
# Dependency Verification
# ------------------------------------------------------------------------------
echo "Checking system prerequisites..."

MISSING_DEPS=()
if ! command -v rclone >/dev/null 2>&1; then
  MISSING_DEPS+=("rclone (install via: sudo pacman -S rclone)")
fi

if ! command -v fusermount3 >/dev/null 2>&1 && ! command -v fusermount >/dev/null 2>&1; then
  MISSING_DEPS+=("fuse3 (install via: sudo pacman -S fuse3)")
fi

if ! command -v python3 >/dev/null 2>&1; then
  MISSING_DEPS+=("python3 (install via: sudo pacman -S python)")
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  echo "⚠️  Missing required dependencies:"
  for dep in "${MISSING_DEPS[@]}"; do
    echo "   • $dep"
  done
  echo "ODrive may not function properly until these are installed."
  echo
else
  echo "✓ All core dependencies found (rclone, fuse3, python3)."
fi

# ------------------------------------------------------------------------------
# Plugin Manifest Validation
# ------------------------------------------------------------------------------
if command -v omarchy-plugin-validate >/dev/null 2>&1; then
  echo "Validating plugin manifest..."
  omarchy-plugin-validate "$SRC" || {
    echo "Error: Plugin validation failed." >&2
    exit 1
  }
  echo "✓ Plugin manifest validated."
fi

# ------------------------------------------------------------------------------
# Installation
# ------------------------------------------------------------------------------
mkdir -p "$(dirname "$PLUGIN_DIR")" "$BIN_DIR"
rm -rf "$PLUGIN_DIR"

if [[ "$MODE" == "link" ]]; then
  ln -sfn "$SRC" "$PLUGIN_DIR"
  echo "✓ Linked $SRC -> $PLUGIN_DIR (dev mode)"
else
  mkdir -p "$PLUGIN_DIR"
  cp -r "$SRC/manifest.json" "$SRC/ui" "$SRC/bin" "$SRC/lib" "$SRC/assets" "$SRC/systemd" "$SRC/README.md" "$SRC/LICENSE" "$PLUGIN_DIR/"
  chmod +x "$PLUGIN_DIR/bin/odrive"
  echo "✓ Copied ODrive into $PLUGIN_DIR"
fi

# Link CLI executable to ~/.local/bin/odrive
ln -sf "$PLUGIN_DIR/bin/odrive" "$BIN_DIR/odrive"
chmod +x "$BIN_DIR/odrive"
echo "✓ Installed CLI executable to $BIN_DIR/odrive"

# Clean up any legacy desktop entry
rm -f "$DESKTOP_DIR/odrive.desktop"

# Ensure ~/.local/bin is in PATH notice
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "⚠️  Notice: $BIN_DIR is not in your current PATH."
  echo "   Add 'export PATH=\"\$HOME/.local/bin:\$PATH\"' to your ~/.bashrc or ~/.zshrc."
fi

# ------------------------------------------------------------------------------
# Optional Systemd User Service Setup
# ------------------------------------------------------------------------------
if [[ "$SETUP_SYSTEMD" == true ]]; then
  mkdir -p "$SYSTEMD_USER_DIR"
  cp "$SRC/systemd/$SERVICE_NAME" "$SYSTEMD_USER_DIR/"
  systemctl --user daemon-reload
  systemctl --user enable --now "$SERVICE_NAME"
  echo "✓ Configured and started systemd user auto-mount service ($SERVICE_NAME)"
fi

# ------------------------------------------------------------------------------
# Omarchy Shell Registration & Bar Enable
# ------------------------------------------------------------------------------
reload_shell

if [[ "$ENABLE_PLUGIN" == true ]]; then
  if command -v omarchy >/dev/null 2>&1; then
    # Disable and re-enable to cleanly refresh the widget in running bar
    omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
    omarchy plugin enable "$PLUGIN_ID" "$BAR_SECTION" || true
    echo "✓ Enabled $PLUGIN_ID on the Omarchy bar ($BAR_SECTION section)"
  fi
fi

# ------------------------------------------------------------------------------
# Completion Banner
# ------------------------------------------------------------------------------
echo
echo "🎉 ODrive installation complete!"
echo "  • Bar widget:  Click the Cloud icon in your Omarchy bar"
echo "  • CLI status:  odrive status"
echo "  • Mount all:   odrive mount-all"
echo "  • Setup drive: odrive setup"
echo

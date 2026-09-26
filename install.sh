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
#
# Nothing is removed or replaced unless it provably belongs to ODrive: the
# plugin directory must be a copy this script made (or an older version of
# it made) or a symlink to an ODrive checkout, and ~/.local/bin/odrive must
# be a symlink to ODrive's launcher. Anything else at those paths, such as a
# git checkout or another program, is left alone and reported.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="ttt.odrive"
PLUGIN_PARENT="$HOME/.config/omarchy/plugins"
PLUGIN_DIR="$PLUGIN_PARENT/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"
CLI_LINK="$BIN_DIR/odrive"
DESKTOP_FILE="$HOME/.local/share/applications/odrive.desktop"
# Written into copies this script makes, so later runs can prove ownership
MARKER=".odrive-install"
# Everything a copy made by this script contains at its top level
COPIED_ENTRIES=(manifest.json ui bin lib assets)
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

Only files and links that belong to ODrive are ever removed or replaced.
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

# Prints the plugin id declared in <dir>/manifest.json, or nothing.
manifest_id() {
  [[ -f "$1/manifest.json" ]] || return 0
  python3 -c '
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    print(data.get("id", "") if isinstance(data, dict) else "")
except Exception:
    pass
' "$1/manifest.json" 2>/dev/null || true
}

is_odrive_dir() {
  [[ -d "$1" && "$(manifest_id "$1")" == "$PLUGIN_ID" ]]
}

# A plain copy with exactly the files a copy install produces. Accepts copies
# made before the marker existed, but never a git checkout or anything with
# extra top-level content that could be someone's work.
is_legacy_copy() {
  local dir="$1" entry name allowed
  [[ -d "$dir" && ! -L "$dir" && ! -e "$dir/.git" ]] || return 1
  is_odrive_dir "$dir" || return 1
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name="$(basename "$entry")"
    allowed=false
    for ok in "${COPIED_ENTRIES[@]}" "$MARKER"; do
      [[ "$name" == "$ok" ]] && allowed=true
    done
    [[ "$allowed" == true ]] || return 1
  done
  return 0
}

# Classifies what is at the plugin destination:
#   absent       nothing there
#   source       it is this checkout itself (install.sh run from inside it)
#   own-copy     a copy made by this script
#   odrive-link  a symlink to an ODrive checkout
#   foreign      anything else: never touched
classify_plugin_dir() {
  if [[ ! -e "$PLUGIN_DIR" && ! -L "$PLUGIN_DIR" ]]; then
    echo absent
  elif [[ "$(realpath -m "$PLUGIN_DIR")" == "$(realpath -m "$SRC")" && ! -L "$PLUGIN_DIR" ]]; then
    echo source
  elif [[ -L "$PLUGIN_DIR" ]]; then
    if is_odrive_dir "$PLUGIN_DIR"; then echo odrive-link; else echo foreign; fi
  elif [[ -f "$PLUGIN_DIR/$MARKER" && ! -e "$PLUGIN_DIR/.git" ]] && is_odrive_dir "$PLUGIN_DIR"; then
    echo own-copy
  elif is_legacy_copy "$PLUGIN_DIR"; then
    echo own-copy
  else
    echo foreign
  fi
}

# True if the CLI link is absent or a symlink to an ODrive launcher
# (including a dangling link left by an earlier ODrive install).
cli_link_is_ours() {
  [[ -L "$CLI_LINK" ]] || return 1
  local target resolved
  target="$(readlink "$CLI_LINK")"
  resolved="$(realpath -m "$CLI_LINK")"
  if [[ -e "$resolved" ]]; then
    [[ "$(basename "$resolved")" == "odrive" ]] && is_odrive_dir "$(dirname "$(dirname "$resolved")")"
  else
    [[ "$target" == */"$PLUGIN_ID"/bin/odrive ]]
  fi
}

desktop_file_is_ours() {
  [[ -f "$DESKTOP_FILE" && ! -L "$DESKTOP_FILE" ]] && grep -qiE '^Exec=.*odrive' "$DESKTOP_FILE"
}

explain_foreign_plugin_dir() {
  echo "Error: $PLUGIN_DIR already exists and was not created by this script." >&2
  if [[ -e "$PLUGIN_DIR/.git" ]]; then
    echo "It is a git checkout (for example from 'omarchy plugin add'); update it with" >&2
    echo "'omarchy plugin update $PLUGIN_ID' or git, or remove it yourself if you no longer need it." >&2
  else
    echo "Move or remove it yourself if you are sure it is not needed, then run this again." >&2
  fi
}

if [[ "$MODE" == "uninstall" ]]; then
  status=0
  kind="$(classify_plugin_dir)"
  case "$kind" in
    absent)
      echo "ODrive plugin is not installed at $PLUGIN_DIR." ;;
    own-copy)
      command -v omarchy >/dev/null 2>&1 && { omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true; }
      rm -rf -- "$PLUGIN_DIR"
      echo "Removed $PLUGIN_DIR" ;;
    odrive-link)
      command -v omarchy >/dev/null 2>&1 && { omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true; }
      rm -f -- "$PLUGIN_DIR"   # the link only; the checkout it points to is kept
      echo "Removed the link $PLUGIN_DIR (the checkout it pointed to is untouched)" ;;
    source|foreign)
      echo "Left $PLUGIN_DIR alone: it was not installed by this script." >&2
      if [[ -e "$PLUGIN_DIR/.git" ]]; then
        echo "It is a git checkout; remove it with 'omarchy plugin remove $PLUGIN_ID' if that is what you want." >&2
      fi
      status=1 ;;
  esac

  if [[ -e "$CLI_LINK" || -L "$CLI_LINK" ]]; then
    if cli_link_is_ours; then
      rm -f -- "$CLI_LINK"
      echo "Removed $CLI_LINK"
    else
      echo "Left $CLI_LINK alone: it is not ODrive's launcher." >&2
    fi
  fi
  if desktop_file_is_ours; then
    rm -f -- "$DESKTOP_FILE"
  fi

  reload_shell
  echo "Cloud credentials and config in ~/.config/odrive were left alone."
  exit "$status"
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

kind="$(classify_plugin_dir)"
if [[ "$kind" == foreign ]]; then
  explain_foreign_plugin_dir
  exit 1
fi

mkdir -p "$PLUGIN_PARENT" "$BIN_DIR"

if [[ "$kind" == source ]]; then
  # Running from the plugin directory itself: the files are already in place,
  # and replacing the directory would delete this checkout.
  echo "ODrive is already in place at $PLUGIN_DIR; nothing to copy."
elif [[ "$MODE" == "link" ]]; then
  [[ "$kind" == own-copy ]] && rm -rf -- "$PLUGIN_DIR"
  # odrive-link: -n replaces the existing link itself, not the directory it points to
  ln -sfn "$SRC" "$PLUGIN_DIR"
  echo "Linked $SRC -> $PLUGIN_DIR"
else
  # Stage the new copy beside the destination (hidden, so the shell ignores it),
  # then swap it in, so a failed copy never leaves a half-installed plugin.
  staging="$(mktemp -d "$PLUGIN_PARENT/.$PLUGIN_ID.new.XXXXXX")"
  trap 'rm -rf -- "$staging"' EXIT
  for entry in "${COPIED_ENTRIES[@]}"; do
    cp -r -- "$SRC/$entry" "$staging/"
  done
  chmod +x "$staging/bin/odrive"
  printf 'Installed by ODrive install.sh from %s\n' "$SRC" > "$staging/$MARKER"
  chmod 755 "$staging"
  case "$kind" in
    own-copy) old="$(mktemp -d "$PLUGIN_PARENT/.$PLUGIN_ID.old.XXXXXX")"
              mv -T -- "$PLUGIN_DIR" "$old/plugin" ;;
    odrive-link) rm -f -- "$PLUGIN_DIR" ;;   # the link only
  esac
  mv -T -- "$staging" "$PLUGIN_DIR"
  trap - EXIT
  [[ -n "${old:-}" ]] && rm -rf -- "$old"
  echo "Copied ODrive into $PLUGIN_DIR"
fi

if [[ ! -e "$CLI_LINK" && ! -L "$CLI_LINK" ]] || cli_link_is_ours; then
  ln -sfn "$PLUGIN_DIR/bin/odrive" "$CLI_LINK"
  echo "Linked CLI engine to $CLI_LINK"
else
  echo "Note: $CLI_LINK already exists and is not ODrive's; left it alone."
  echo "      The widget does not need it. Run the CLI as $PLUGIN_DIR/bin/odrive instead."
fi

# Clean up a legacy standalone desktop entry, if it is ODrive's
if desktop_file_is_ours; then
  rm -f -- "$DESKTOP_FILE"
fi

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

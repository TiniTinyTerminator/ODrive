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
# plugin directory must be a copy this script made whose files are all still
# exactly as installed (or a symlink to an ODrive checkout, where only the
# link is removed), and ~/.local/bin/odrive must be a symlink to ODrive's
# launcher. Anything else at those paths, such as a git checkout, a copy with
# files added or edited since install, or another program, is left alone and
# reported.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="ttt.odrive"
PLUGIN_PARENT="$HOME/.config/omarchy/plugins"
PLUGIN_DIR="$PLUGIN_PARENT/$PLUGIN_ID"
BIN_DIR="$HOME/.local/bin"
CLI_LINK="$BIN_DIR/odrive"
DESKTOP_FILE="$HOME/.local/share/applications/odrive.desktop"
# SHA-256 of the one odrive.desktop ODrive ever shipped (assets/odrive.desktop in
# 0e4b0f4, removed in 090d0af with the `odrive gui` command it launched). Early
# installers copied it verbatim, so only a byte-identical file is ODrive's.
LEGACY_DESKTOP_SHA256="bc5c235dbf53b2a998dd25ab9fdc3eb182ebf233a5964088c57bbe5f6267099d"
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

# Top-level layout check for copies made by installers older than the marker.
is_legacy_layout() {
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

# Lists files in an installed copy that were added or changed since install,
# one "added: <path>" / "changed: <path>" per line. Exit status:
#   0  unchanged: every file is exactly as installed
#   1  files were added or changed (listed)
#   2  cannot verify (an older install recorded no file list, and this
#      checkout has no git history to check it against)
# The marker written at install time records every file's SHA-256. Copies
# from older installers are checked against ODrive's git history instead:
# each file's exact content must have been shipped at that path. Python
# bytecode caches, regenerated at runtime, are ignored; missing files are
# not user data and are ignored too.
copy_changes() {
  python3 - "$1" "$SRC" "$MARKER" <<'PY'
import hashlib, os, re, subprocess, sys

root, src, marker = sys.argv[1:4]

def installed_entries():
    for dirpath, dirnames, filenames in os.walk(root):
        for d in list(dirnames):
            if d == "__pycache__":
                dirnames.remove(d)
            elif os.path.islink(os.path.join(dirpath, d)):
                dirnames.remove(d)  # a symlinked directory is user content
                yield os.path.relpath(os.path.join(dirpath, d), root)
        for f in filenames:
            rel = os.path.relpath(os.path.join(dirpath, f), root)
            if rel != marker and not f.endswith(".pyc"):
                yield rel

def read(rel):
    with open(os.path.join(root, rel), "rb") as fh:
        return fh.read()

recorded = {}
try:
    with open(os.path.join(root, marker), encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.match(r"^([0-9a-f]{64})  (.+)$", line.rstrip("\n"))
            if m:
                recorded[m.group(2)] = m.group(1)
except OSError:
    pass

changes = []
if recorded:
    for rel in sorted(installed_entries()):
        path = os.path.join(root, rel)
        if rel not in recorded:
            changes.append("added: " + rel)
        elif os.path.islink(path) or hashlib.sha256(read(rel)).hexdigest() != recorded[rel]:
            changes.append("changed: " + rel)
else:
    try:
        top = subprocess.run(["git", "-C", src, "rev-parse", "--show-toplevel"],
                             capture_output=True, text=True, check=True).stdout.strip()
        log = subprocess.run(["git", "-C", src, "log", "--all", "--raw", "--no-renames",
                              "--no-abbrev", "--format="],
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        sys.exit(2)
    if os.path.realpath(top) != os.path.realpath(src):
        sys.exit(2)
    shipped, known_paths = set(), set()
    for line in log.splitlines():
        m = re.match(r"^:\d+ \d+ [0-9a-f]+ ([0-9a-f]+) \w+\t(.+)$", line)
        if m:
            shipped.add((m.group(2), m.group(1)))
            known_paths.add(m.group(2))
    if not shipped:
        sys.exit(2)
    for rel in sorted(installed_entries()):
        path = os.path.join(root, rel)
        if os.path.islink(path):
            changes.append(("changed: " if rel in known_paths else "added: ") + rel)
            continue
        data = read(rel)
        blob = hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
        if (rel, blob) not in shipped:
            changes.append(("changed: " if rel in known_paths else "added: ") + rel)

print("\n".join(changes))
sys.exit(1 if changes else 0)
PY
}

# Classifies what is at the plugin destination:
#   absent       nothing there
#   source       it is this checkout itself (install.sh run from inside it)
#   own-copy     a copy made by this script, with every file exactly as installed
#   modified     a copy made by this script, but with files added or changed since
#   unverified   a copy from an older installer that cannot be checked here
#   odrive-link  a symlink to an ODrive checkout
#   foreign      anything else
# Only own-copy and odrive-link are ever replaced or removed.
classify_plugin_dir() {
  local rc
  if [[ ! -e "$PLUGIN_DIR" && ! -L "$PLUGIN_DIR" ]]; then
    echo absent
  elif [[ "$(realpath -m "$PLUGIN_DIR")" == "$(realpath -m "$SRC")" && ! -L "$PLUGIN_DIR" ]]; then
    echo source
  elif [[ -L "$PLUGIN_DIR" ]]; then
    if is_odrive_dir "$PLUGIN_DIR"; then echo odrive-link; else echo foreign; fi
  elif [[ ! -e "$PLUGIN_DIR/.git" ]] && is_odrive_dir "$PLUGIN_DIR" \
       && { [[ -f "$PLUGIN_DIR/$MARKER" ]] || is_legacy_layout "$PLUGIN_DIR"; }; then
    rc=0
    copy_changes "$PLUGIN_DIR" >/dev/null || rc=$?
    case "$rc" in
      0) echo own-copy ;;
      1) echo modified ;;
      *) echo unverified ;;
    esac
  else
    echo foreign
  fi
}

# Explains why a copy is kept, listing what was added or changed.
explain_kept_copy() {
  local kind="$1" changes
  if [[ "$kind" == modified ]]; then
    changes="$(copy_changes "$PLUGIN_DIR" || true)"
    echo "$PLUGIN_DIR has files added or changed since ODrive installed it:" >&2
    printf '%s\n' "$changes" | head -n 20 | sed 's/^/  /' >&2
    [[ "$(printf '%s\n' "$changes" | wc -l)" -gt 20 ]] && echo "  …" >&2
    echo "Move anything you want to keep out of it, delete the folder, then run this again." >&2
  else
    echo "$PLUGIN_DIR was installed by an older version of this script that did not record" >&2
    echo "its files, and this checkout has no git history to check them against." >&2
    echo "If it holds nothing of yours, delete the folder yourself, then run this again." >&2
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

# Only the exact file an early ODrive installer copied counts as ODrive's; any
# other odrive.desktop, even one that runs odrive, is the user's and is kept.
desktop_file_is_ours() {
  [[ -f "$DESKTOP_FILE" && ! -L "$DESKTOP_FILE" ]] || return 1
  [[ "$(sha256sum < "$DESKTOP_FILE" | cut -d' ' -f1)" == "$LEGACY_DESKTOP_SHA256" ]]
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
    modified|unverified)
      echo "Left $PLUGIN_DIR alone." >&2
      explain_kept_copy "$kind"
      status=1 ;;
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
case "$kind" in
  foreign) explain_foreign_plugin_dir; exit 1 ;;
  modified|unverified) echo "Error: not replacing $PLUGIN_DIR." >&2; explain_kept_copy "$kind"; exit 1 ;;
esac

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
  find "$staging" -name __pycache__ -type d -prune -exec rm -rf -- {} +
  chmod +x "$staging/bin/odrive"
  {
    printf '# Installed by ODrive install.sh from %s\n' "$SRC"
    printf '# SHA-256 of every installed file: reinstall and uninstall only remove this\n'
    printf '# folder while it still matches, so files added or edited later are never lost.\n'
    # The marker is being written by this redirect, so leave it out of its own list
    (cd "$staging" && find . -type f ! -path "./$MARKER" -printf '%P\0' | sort -z | xargs -0 -r sha256sum --)
  } > "$staging/$MARKER"
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

# Clean up the desktop entry an early ODrive installer left, if unmodified
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

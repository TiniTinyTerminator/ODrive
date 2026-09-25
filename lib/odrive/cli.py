"""Command Line Interface and Interactive Setup for ODrive."""

import argparse
import getpass
import json
import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

from .config import get_mount_path_for_remote, get_mount_root, load_config, save_config
from .manager import DriveManager
from .preview import PreviewManager, is_preview_requested
from .providers import PROVIDERS


def format_bytes(b: int) -> str:
    """Format bytes into human readable string."""
    if b <= 0:
        return "0 B"
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    n = float(b)
    idx = 0
    while n >= 1024.0 and idx < len(units) - 1:
        n /= 1024.0
        idx += 1
    return f"{n:.1f} {units[idx]}"


def print_banner():
    print("\033[1;36m")
    print("  ╭───────────────────────────────────────────────────╮")
    print("  │            ODrive — Cloud Drive Setup             │")
    print("  │         Unified Cloud Storage for Omarchy         │")
    print("  ╰───────────────────────────────────────────────────╯")
    print("\033[0m")


def interactive_setup(remote_name: str = "", provider_id: str = ""):
    """Interactive wizard to configure a new cloud drive."""
    print_banner()

    manager = DriveManager()
    if not manager.is_installed():
        print("\033[1;31mError: rclone is not installed on this system.\033[0m")
        print("Please install rclone using: sudo pacman -S rclone")
        sys.exit(1)

    # Step 1: Select Provider if not provided
    selected_provider = None
    if provider_id and provider_id in PROVIDERS:
        selected_provider = PROVIDERS[provider_id]
    else:
        print("\033[1;33mSelect a Cloud Storage Provider:\033[0m\n")
        provider_options = [
            ("drive", "Google Drive", "Personal or Google Workspace"),
            ("onedrive", "Microsoft OneDrive", "Personal, Business, SharePoint"),
            ("dropbox", "Dropbox", "Personal or Business storage"),
            ("nextcloud", "Nextcloud", "Self-hosted cloud storage (WebDAV)"),
            ("box", "Box", "Box Enterprise & Personal storage"),
            ("pcloud", "pCloud", "Secure cloud storage"),
            ("protondrive", "Proton Drive", "End-to-end encrypted storage"),
            ("webdav", "WebDAV", "Generic WebDAV server"),
            ("s3", "Amazon S3", "S3, MinIO, Cloudflare R2, Backblaze B2"),
            ("custom", "Other rclone remote", "Full rclone configuration wizard"),
        ]

        for i, (pid, name, desc) in enumerate(provider_options, 1):
            glyph = PROVIDERS.get(pid, {}).get("glyph", "󰅟")
            print(f"  \033[1;32m{i:2d})\033[0m {glyph}  \033[1m{name:<22}\033[0m \033[2m{desc}\033[0m")

        print()
        choice = input("\033[1mEnter choice [1-10]: \033[0m").strip()
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(provider_options):
                chosen_id = provider_options[idx][0]
                if chosen_id == "custom":
                    # Directly launch rclone config
                    subprocess.run([manager.rclone_bin, "config"])
                    return
                selected_provider = PROVIDERS.get(chosen_id)
        except ValueError:
            pass

    if not selected_provider:
        print("\033[1;31mInvalid choice. Exiting.\033[0m")
        return

    # Step 2: Choose Remote Name
    if not remote_name:
        default_name = selected_provider["name"].replace(" ", "")
        print(f"\n\033[1;33mChoose a name for this remote [default: {default_name}]:\033[0m")
        remote_name = input(f"Remote name: ").strip() or default_name

    # Sanitize remote name
    remote_name = "".join(c for c in remote_name if c.isalnum() or c in ("-", "_"))
    if not remote_name:
        remote_name = "CloudDrive"

    print(f"\n\033[1;34mConfiguring {selected_provider['name']} as '{remote_name}'...\033[0m\n")

    # Step 3: Run Setup
    rclone_type = selected_provider.get("rclone_type", "drive")

    if rclone_type == "webdav" and selected_provider["id"] == "nextcloud":
        print("\033[1;37mNextcloud Setup:\033[0m")
        url = input("Nextcloud server URL (e.g. https://cloud.example.com): ").strip()
        user = input("Username: ").strip()
        # Nextcloud WebDAV URL format is: <url>/remote.php/dav/files/<user>/
        if url and not url.endswith("/remote.php/dav/files/" + user) and not url.endswith("/remote.php/webdav"):
            url = url.rstrip("/") + f"/remote.php/dav/files/{user}"

        subprocess.run([
            manager.rclone_bin, "config", "create", remote_name, "webdav",
            "url", url,
            "vendor", "nextcloud",
            "user", user
        ])
    else:
        # Standard interactive rclone config for this remote type
        # E.g. rclone config create <name> <type>
        # This will open the browser for OAuth authentication (Google Drive, OneDrive, Dropbox, etc.)
        cmd = [manager.rclone_bin, "config", "create", remote_name, rclone_type]
        subprocess.run(cmd)

    # Verify creation
    remotes = manager.list_remotes()
    if remote_name in remotes:
        print(f"\n\033[1;32m✓ Successfully configured '{remote_name}'!\033[0m")
        mount_path = get_mount_path_for_remote(remote_name)
        print(f"Mount location: \033[1m{mount_path}\033[0m")

        # Ask to mount now
        mount_now = input("\nWould you like to mount this drive now? [Y/n]: ").strip().lower()
        if mount_now in ("", "y", "yes"):
            ok, msg = manager.mount(remote_name)
            if ok:
                print(f"\033[1;32m✓ {msg}\033[0m")
            else:
                print(f"\033[1;31m✗ {msg}\033[0m")
    else:
        print(f"\n\033[1;33mRemote configuration exited or was cancelled.\033[0m")

    # Trigger shell rescan if omarchy-shell is running
    try:
        subprocess.run(["omarchy-shell", "shell", "rescanPlugins"], capture_output=True, timeout=2)
    except (subprocess.SubprocessError, OSError):
        pass


def print_status_table(status: dict):
    print("\033[1;36mODrive — Cloud Drive Status\033[0m")
    print(f"Mount Root: \033[1m{status.get('mountRoot')}\033[0m")
    print(f"Engine:     \033[2m{status.get('version')}\033[0m")
    print()

    drives = status.get("drives", [])
    if not drives:
        print("  \033[2mNo cloud drives configured. Run 'odrive setup' to add one.\033[0m\n")
        return

    col_name = "Drive"
    col_prov = "Provider"
    col_stat = "Status"
    col_path = "Mount Path"
    col_quota = "Storage Quota"

    print(f"  {col_name:<16} {col_prov:<20} {col_stat:<14} {col_quota:<24} {col_path}")
    print("  " + "─" * 90)

    for d in drives:
        name = d["name"]
        glyph = d.get("glyph", "󰅟")
        prov = f"{glyph} {d['provider']}"
        mounted = d["mounted"]

        if mounted:
            stat_str = "\033[1;32m󰄬 Mounted\033[0m"
        else:
            stat_str = "\033[2m󰅛 Unmounted\033[0m"

        if d.get("quotaKnown"):
            used = format_bytes(d.get("quotaUsed", 0))
            total = format_bytes(d.get("quotaTotal", 0))
            pct = d.get("quotaPercent", 0)
            quota_str = f"{used} / {total} ({pct}%)"
        else:
            quota_str = "\033[2mQuota n/a\033[0m"

        path_str = f"\033[2m{d['mountPath']}\033[0m" if mounted else ""
        print(f"  {name:<16} {prov:<29} {stat_str:<23} {quota_str:<24} {path_str}")

    print()


def open_drive_folder(remote_name: str = ""):
    """Open drive directory in system file manager."""
    if remote_name:
        path = str(get_mount_path_for_remote(remote_name))
    else:
        path = str(get_mount_root())

    os.makedirs(path, exist_ok=True)

    opener = shutil.which("xdg-open") or shutil.which("gio")
    if opener:
        subprocess.Popen([opener, path])
    else:
        print(f"Directory: {path}")



def read_client_secret() -> str:
    """Read an OAuth client secret from stdin, or prompt without echo on a terminal."""
    if sys.stdin.isatty():
        return getpass.getpass("OAuth client secret: ").strip()
    return sys.stdin.readline().strip()


def claim_session_marker(name: str = "odrive-automounted") -> bool:
    """Return True for the first caller this login session; the runtime dir is cleared on logout."""
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        return True
    marker = Path(runtime_dir) / name
    try:
        fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    except FileExistsError:
        return False
    except OSError:
        return True
    os.close(fd)
    return True


def _exit_on_sigterm(signum, _frame):
    # Raise SystemExit so context managers (the private rclone rc server, its temp dir) clean up
    sys.exit(128 + signum)


def main():
    signal.signal(signal.SIGTERM, _exit_on_sigterm)
    parser = argparse.ArgumentParser(
        prog="odrive",
        description="Unified Cloud Drive Manager for Omarchy Linux.",
    )
    parser.add_argument(
        "--preview",
        action="store_true",
        help="Use sample data instead of rclone: nothing is mounted or changed (also ODRIVE_PREVIEW=1)",
    )
    subparsers = parser.add_subparsers(dest="command", help="Available subcommands")

    # preview-reset
    subparsers.add_parser("preview-reset", help="Restore the preview-mode sample data")

    # status
    p_status = subparsers.add_parser("status", help="Show status of cloud drives")
    p_status.add_argument("--json", action="store_true", help="Output raw JSON")

    # list
    subparsers.add_parser("list", help="List configured cloud remotes")

    # mount
    p_mount = subparsers.add_parser("mount", help="Mount a cloud drive")
    p_mount.add_argument("remote", help="Remote name to mount")

    # unmount
    p_unmount = subparsers.add_parser("unmount", help="Unmount a cloud drive")
    p_unmount.add_argument("remote", help="Remote name to unmount")

    # mount-all
    subparsers.add_parser("mount-all", help="Mount all configured cloud drives")

    # unmount-all
    subparsers.add_parser("unmount-all", help="Unmount all active cloud drives")

    # setup / add
    p_setup = subparsers.add_parser("setup", help="Interactive cloud drive setup wizard")
    p_setup.add_argument("remote", nargs="?", default="", help="Remote name")
    p_setup.add_argument("provider", nargs="?", default="", help="Provider ID (drive, onedrive, dropbox, nextcloud, etc.)")

    # remove
    p_remove = subparsers.add_parser("remove", help="Remove a cloud drive remote")
    p_remove.add_argument("remote", help="Remote name to delete")
    p_remove.add_argument("-y", "--yes", action="store_true", help="Skip the confirmation prompt")

    # open
    p_open = subparsers.add_parser("open", help="Open cloud mount directory in file manager")
    p_open.add_argument("remote", nargs="?", default="", help="Remote name (opens root if omitted)")

    # auto-mount
    p_auto = subparsers.add_parser("auto-mount", help="Mount all drives configured for auto-mount")
    p_auto.add_argument("--once", action="store_true", help="Only run once per login session")

    # files
    p_files = subparsers.add_parser("files", help="List files in a cloud drive")
    p_files.add_argument("remote", help="Remote name")
    p_files.add_argument("path", nargs="?", default="", help="Subfolder path")

    # log
    p_log = subparsers.add_parser("log", help="View mount logs for a remote")
    p_log.add_argument("remote", help="Remote name")

    # config
    p_cfg = subparsers.add_parser("config", help="Get or set configuration")
    p_cfg.add_argument("key", nargs="?", default="", help="Config key")
    p_cfg.add_argument("value", nargs="?", default="", help="New value")

    # add-oauth
    p_oauth = subparsers.add_parser("add-oauth", help="Authenticate and create an OAuth remote")
    p_oauth.add_argument("remote", help="Remote name")
    p_oauth.add_argument("provider", help="Provider ID (drive, onedrive, dropbox, box, pcloud)")
    p_oauth.add_argument("--client-id", default="", help="Custom OAuth Client ID")
    # Secrets are never accepted as arguments: argv is visible to every local user
    p_oauth.add_argument(
        "--client-secret-stdin",
        action="store_true",
        help="Read a custom OAuth client secret from stdin (prompts when stdin is a terminal)",
    )
    p_oauth.add_argument("--mount-path", default="", help="Custom mount directory path")
    p_oauth.add_argument("--mount", action="store_true", help="Mount immediately after configuration")

    # add-credentials
    p_cred = subparsers.add_parser(
        "add-credentials",
        help="Create a credentials-based remote (Nextcloud, WebDAV, S3, etc.)",
        description="Reads the options (url, user, pass, etc.) as a JSON object from stdin, "
        "so credentials never appear in the process list.",
    )
    p_cred.add_argument("remote", help="Remote name")
    p_cred.add_argument("provider", help="Provider ID (nextcloud, webdav, s3, protondrive)")
    p_cred.add_argument("--mount-path", default="", help="Custom mount directory path")
    p_cred.add_argument("--no-test", action="store_true", help="Skip connection testing")
    p_cred.add_argument("--mount", action="store_true", help="Mount immediately after configuration")

    # rename
    p_rename = subparsers.add_parser("rename", help="Rename a cloud drive remote")
    p_rename.add_argument("remote", help="Current remote name")
    p_rename.add_argument("new_name", help="New remote name")
    p_rename.add_argument("--mount-path", default=None, help="Also set a custom mount directory (empty string resets to the default)")

    # set-path
    p_set_path = subparsers.add_parser("set-path", help="Change mount directory for a remote")
    p_set_path.add_argument("remote", help="Remote name")
    p_set_path.add_argument("path", help="New mount directory path (e.g. ~/Cloud/MyFolder)")

    # set-root
    p_set_root = subparsers.add_parser("set-root", help="Change default mount root for all remotes")
    p_set_root.add_argument("path", help="New default mount root directory (e.g. ~/Cloud)")

    # test-remote
    p_test = subparsers.add_parser("test-remote", help="Test connection to a remote")
    p_test.add_argument("remote", help="Remote name")


    args = parser.parse_args()
    preview = is_preview_requested(args.preview)
    manager = PreviewManager() if preview else DriveManager()
    # Preview state lives in its own file, so config reads and writes go through the manager
    read_config = manager.load_config if preview else load_config
    write_config = manager.save_config if preview else save_config

    if args.command == "preview-reset":
        PreviewManager().reset()
        print("Preview sample data restored.")
        return

    if preview and args.command in ("setup", "add"):
        print("The interactive setup wizard isn't available in preview mode; "
              "use the widget, add-oauth or add-credentials.", file=sys.stderr)
        sys.exit(1)

    if args.command == "status" or args.command is None:
        status = manager.get_status(include_recent=getattr(args, "json", False))
        if getattr(args, "json", False):
            print(json.dumps(status, indent=2))
        else:
            print_status_table(status)

    elif args.command == "list":
        status = manager.get_status(include_recent=False)
        print_status_table(status)

    elif args.command == "mount":
        ok, msg = manager.mount(args.remote)
        if ok:
            print(f"\033[1;32m✓ {msg}\033[0m")
        else:
            print(f"\033[1;31m✗ {msg}\033[0m", file=sys.stderr)
            sys.exit(1)

    elif args.command == "unmount":
        ok, msg = manager.unmount(args.remote)
        if ok:
            print(f"\033[1;32m✓ {msg}\033[0m")
        else:
            print(f"\033[1;31m✗ {msg}\033[0m", file=sys.stderr)
            sys.exit(1)

    elif args.command == "mount-all":
        results = manager.mount_all()
        for name, ok in results.items():
            if ok:
                print(f"\033[1;32m✓ Mounted {name}\033[0m")
            else:
                print(f"\033[1;31m✗ Failed to mount {name}\033[0m", file=sys.stderr)
        if not all(results.values()):
            sys.exit(1)

    elif args.command == "unmount-all":
        results = manager.unmount_all()
        for name, ok in results.items():
            if ok:
                print(f"\033[1;32m✓ Unmounted {name}\033[0m")
            else:
                print(f"\033[1;31m✗ Failed to unmount {name}\033[0m", file=sys.stderr)
        if not all(results.values()):
            sys.exit(1)

    elif args.command in ("setup", "add"):
        interactive_setup(args.remote, args.provider)

    elif args.command == "remove":
        if args.yes:
            confirm = "y"
        else:
            try:
                confirm = input(f"Are you sure you want to remove '{args.remote}'? [y/N]: ").strip().lower()
            except EOFError:
                print("\nNo terminal to confirm on; pass --yes to remove without prompting.", file=sys.stderr)
                sys.exit(1)
        if confirm in ("y", "yes"):
            ok, msg = manager.remove_remote(args.remote)
            if ok:
                print(f"\033[1;32m✓ {msg}\033[0m")
            else:
                print(f"\033[1;31m✗ {msg}\033[0m", file=sys.stderr)
                sys.exit(1)

    elif args.command == "open":
        if preview:
            print("Preview mode: nothing to open, no drives are mounted.")
        else:
            open_drive_folder(args.remote)

    elif args.command == "auto-mount":
        if args.once and not claim_session_marker("odrive-preview-automounted" if preview else "odrive-automounted"):
            print("Auto-mount already ran this session.")
            return
        results = manager.auto_mount()
        mounted = [k for k, v in results.items() if v]
        print(f"Auto-mounted {len(mounted)} drives.")

    elif args.command == "files":
        items = manager.list_dir(args.remote, getattr(args, "path", ""))
        print(json.dumps(items, indent=2))

    elif args.command == "log":
        log_text = manager.get_log(args.remote)
        print(log_text)

    elif args.command == "config":
        cfg = read_config()
        if args.key:
            if args.value:
                # Set key
                val = args.value
                if val.lower() == "true":
                    val = True
                elif val.lower() == "false":
                    val = False
                elif val.isdigit():
                    val = int(val)
                cfg[args.key] = val
                write_config(cfg)
                print(f"Set {args.key} = {val}")
            else:
                print(f"{args.key} = {cfg.get(args.key)}")
        else:
            print(json.dumps(cfg, indent=2))

    elif args.command == "add-oauth":
        ok, res = manager.add_remote_oauth(
            args.remote,
            args.provider,
            client_id=args.client_id,
            client_secret=read_client_secret() if args.client_secret_stdin else "",
            mount_path=getattr(args, "mount_path", ""),
        )
        if ok:
            remote_name = res
            mounted = False
            mount_err = ""
            if args.mount:
                m_ok, m_msg = manager.mount(remote_name)
                mounted = m_ok
                if not m_ok:
                    mount_err = m_msg
            print(json.dumps({
                "ok": True,
                "remote": remote_name,
                "mounted": mounted,
                "mountError": mount_err,
                "message": f"Successfully connected {remote_name}",
            }))
        else:
            print(json.dumps({
                "ok": False,
                "error": res,
            }))
            sys.exit(1)

    elif args.command == "add-credentials":
        if sys.stdin.isatty():
            print("Paste the options as JSON, then press Ctrl-D:", file=sys.stderr)
        raw_options = sys.stdin.read().strip()
        try:
            options = json.loads(raw_options) if raw_options else {}
        except json.JSONDecodeError as e:
            # The decoder message only holds a position, never the input itself
            print(json.dumps({"ok": False, "error": f"Invalid options JSON on stdin: {e.msg} (char {e.pos})"}))
            sys.exit(1)
        if not isinstance(options, dict):
            print(json.dumps({"ok": False, "error": "Options on stdin must be a JSON object"}))
            sys.exit(1)
        ok, res = manager.add_remote_credentials(
            args.remote,
            args.provider,
            options=options,
            mount_path=getattr(args, "mount_path", ""),
            test_connection=not args.no_test,
        )
        if ok:
            remote_name = res
            mounted = False
            mount_err = ""
            if args.mount:
                m_ok, m_msg = manager.mount(remote_name)
                mounted = m_ok
                if not m_ok:
                    mount_err = m_msg
            print(json.dumps({
                "ok": True,
                "remote": remote_name,
                "mounted": mounted,
                "mountError": mount_err,
                "message": f"Successfully connected {remote_name}",
            }))
        else:
            print(json.dumps({
                "ok": False,
                "error": res,
            }))
            sys.exit(1)

    elif args.command == "rename":
        ok, msg = manager.rename_remote(args.remote, args.new_name, mount_path=getattr(args, "mount_path", None))
        print(json.dumps({"ok": ok, "message": msg, "remote": args.new_name}))
        if not ok:
            sys.exit(1)

    elif args.command == "set-path":
        ok, msg = manager.set_remote_mount_path(args.remote, args.path)
        print(json.dumps({"ok": ok, "message": msg, "remote": args.remote}))
        if not ok:
            sys.exit(1)

    elif args.command == "set-root":
        ok, msg = manager.set_mount_root(args.path)
        print(json.dumps({"ok": ok, "message": msg}))
        if not ok:
            sys.exit(1)

    elif args.command == "test-remote":
        ok, msg = manager.test_remote(args.remote)
        print(json.dumps({"ok": ok, "message": msg}))



if __name__ == "__main__":
    main()

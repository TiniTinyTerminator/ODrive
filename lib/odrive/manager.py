"""Core Drive Manager interfacing with rclone, system mounts, and storage quotas."""

import heapq
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import urllib.error
import urllib.request

from .config import (
    ensure_private_dir,
    get_config_dir,
    get_mount_path_for_remote,
    get_mount_root,
    get_state_dir,
    load_config,
    open_private,
    save_config,
)
from .providers import PROVIDERS, detect_provider
from .rclone_rc import config_create, die_with_parent, is_secret_key, redact

# rclone reports this total/free size through statfs when a backend can't report its quota
UNKNOWN_QUOTA_BYTES = 1 << 50


def _unescape_mount_field(field: str) -> str:
    """Decode the octal escapes /proc/mounts uses for spaces, tabs and backslashes."""
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), field)


# C0 controls (bar tab/newline), DEL and C1 controls: what a terminal would act on
_CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]")


def neutralize_controls(text: str) -> str:
    """Render control characters visibly, as rclone does for names (ESC -> U+241B).

    Mount logs contain cloud file names, which on Drive, Dropbox, WebDAV, S3 and Proton can
    hold raw escape sequences; printed as-is they would drive the user's terminal.
    """
    def picture(m: "re.Match") -> str:
        code = ord(m.group(0))
        if code < 0x20:
            return chr(0x2400 + code)
        return "\u2421" if code == 0x7F else f"\\x{code:02x}"
    return _CONTROL_CHARS_RE.sub(picture, text)


def _is_plausible_quota(data: dict) -> bool:
    return 0 < int(data.get("total", 0) or 0) < UNKNOWN_QUOTA_BYTES


def resolve_onedrive_drive(token_str: str) -> Tuple[Optional[str], Optional[str]]:
    """Query Microsoft Graph API with the OAuth access token to resolve drive_id and drive_type."""
    try:
        tok_data = json.loads(token_str) if isinstance(token_str, str) else token_str
        acc_token = tok_data.get("access_token")
        if not acc_token:
            return None, None
        req = urllib.request.Request(
            "https://graph.microsoft.com/v1.0/me/drive",
            headers={"Authorization": f"Bearer {acc_token}"}
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            d_id = data.get("id")
            d_type = data.get("driveType", "personal")
            return d_id, d_type
    except Exception:
        return None, None


class DriveManager:
    def __init__(self):
        self.rclone_bin = shutil.which("rclone")
        self.fusermount_bin = shutil.which("fusermount3") or shutil.which("fusermount")
        self.state_dir = get_state_dir()
        # Mount logs list cloud file names, so keep the state directory private
        ensure_private_dir(self.state_dir)
        self.cache_file = self.state_dir / "quota_cache.json"
        self._tighten_existing_files()

    def _tighten_existing_files(self) -> None:
        """Make files written by older versions private too, not only files written from now on."""
        config_dir = get_config_dir()
        if config_dir.is_dir():
            ensure_private_dir(config_dir)
        paths = list(self.state_dir.glob("mount_*.log")) + [config_dir / "config.json", self.cache_file]
        for path in paths:
            try:
                if path.is_file() and path.stat().st_mode & 0o077:
                    os.chmod(path, 0o600)
            except OSError:
                pass

    def is_installed(self) -> bool:
        return self.rclone_bin is not None

    def get_rclone_version(self) -> str:
        if not self.rclone_bin:
            return ""
        try:
            res = subprocess.run(
                [self.rclone_bin, "version"],
                capture_output=True,
                text=True,
                timeout=3,
                check=False,
            )
            first_line = res.stdout.splitlines()[0] if res.stdout else ""
            return first_line.strip()
        except (subprocess.SubprocessError, OSError):
            return ""

    def _ensure_onedrive_drive(self, remote_name: str) -> None:
        """If a OneDrive remote is missing drive_id / drive_type, resolve them and persist via rclone."""
        if not self.rclone_bin:
            return
        info = self.list_remotes().get(remote_name, {})
        if info.get("type") != "onedrive" or info.get("drive_id") or not info.get("token"):
            return
        d_id, d_type = resolve_onedrive_drive(info["token"])
        if not d_id:
            return
        # Let rclone write its own config (honours RCLONE_CONFIG, encryption, concurrent token refresh).
        # --non-interactive stops the OneDrive config flow from waiting on stdin; the values are saved regardless.
        try:
            subprocess.run(
                [
                    self.rclone_bin, "config", "update", remote_name,
                    "drive_id", d_id,
                    "drive_type", d_type or "personal",
                    "config_refresh_token=false",
                    "--non-interactive",
                ],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                timeout=15,
                check=False,
            )
        except (subprocess.SubprocessError, OSError):
            pass

    def list_remotes(self) -> Dict[str, dict]:
        """Fetch all remotes configured in rclone."""
        if not self.rclone_bin:
            return {}
        try:
            res = subprocess.run(
                [self.rclone_bin, "config", "dump"],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            if res.returncode == 0 and res.stdout.strip():
                data = json.loads(res.stdout)
                if isinstance(data, dict):
                    return data
        except (subprocess.SubprocessError, OSError, json.JSONDecodeError):
            pass
        return {}

    def get_active_mounts(self) -> Dict[str, dict]:
        """Parse /proc/mounts to find active rclone mount points."""
        mounts = {}
        mount_root = str(get_mount_root())
        try:
            with open("/proc/mounts", "r", encoding="utf-8") as f:
                for line in f:
                    parts = line.split()
                    if len(parts) >= 2:
                        device = _unescape_mount_field(parts[0])
                        mount_point = _unescape_mount_field(parts[1])
                        fstype = parts[2] if len(parts) > 2 else ""
                        # rclone mounts usually show device as '<remote>:' or fstype 'fuse.rclone'
                        if "rclone" in fstype or ":" in device:
                            remote_name = device.rstrip(":")
                            # Also check if it's within our mount_root
                            in_root = mount_point == mount_root or mount_point.startswith(
                                mount_root.rstrip(os.sep) + os.sep
                            )
                            if in_root or "rclone" in fstype:
                                mounts[mount_point] = {
                                    "remote": remote_name,
                                    "mount_point": mount_point,
                                    "fstype": fstype,
                                }
        except OSError:
            pass
        return mounts

    @staticmethod
    def _is_responsive(path: str) -> bool:
        """A FUSE mount whose rclone process died stays in /proc/mounts but fails statfs (ENOTCONN).

        statfs always reaches the daemon; stat can be answered from the kernel's attribute cache.
        """
        try:
            os.statvfs(path)
            return True
        except OSError:
            return False

    def is_remote_mounted(self, remote_name: str) -> Tuple[bool, str]:
        """Check if remote is currently mounted and return (is_mounted, mount_path)."""
        expected_path = str(get_mount_path_for_remote(remote_name))
        active_mounts = self.get_active_mounts()

        # Check by expected mount path; a stale entry counts as unmounted so it can be cleaned up and remounted
        if expected_path in active_mounts:
            return self._is_responsive(expected_path), expected_path

        # Check by remote name in active mounts
        for mp, info in active_mounts.items():
            if info.get("remote") == remote_name:
                return self._is_responsive(mp), mp

        # Fallback check: os.path.ismount (and ensure it is responding)
        try:
            if os.path.exists(expected_path) and os.path.ismount(expected_path):
                try:
                    os.listdir(expected_path)
                    return True, expected_path
                except OSError:
                    # Broken / disconnected FUSE mount
                    return False, expected_path
        except OSError:
            return False, expected_path

        return False, expected_path

    def _load_quota_cache(self) -> dict:
        if not self.cache_file.exists():
            return {}
        try:
            with open(self.cache_file, "r", encoding="utf-8") as f:
                cache = json.load(f)
        except (OSError, json.JSONDecodeError):
            return {}
        if not isinstance(cache, dict):
            return {}
        # Drop quotas cached from rclone's "unknown" placeholder size
        return {
            name: entry for name, entry in cache.items()
            if not entry.get("data", {}).get("known") or _is_plausible_quota(entry["data"])
        }

    def _save_quota_cache(self, cache: dict) -> None:
        try:
            with open_private(self.cache_file) as f:
                json.dump(cache, f, indent=2)
        except OSError:
            pass

    def get_quota(self, remote_name: str, force_refresh: bool = False) -> dict:
        """Fetch quota for a remote using statvfs when mounted or 'rclone about' with caching."""
        now = time.time()

        # 1. If remote is mounted, statvfs provides instant, accurate, non-blocking quota metrics
        is_mounted, mount_path = self.is_remote_mounted(remote_name)
        if is_mounted and os.path.exists(mount_path):
            try:
                st = os.statvfs(mount_path)
                total = st.f_blocks * st.f_frsize
                free = st.f_bavail * st.f_frsize
                used = max(0, total - free)
                if total > 0 and total < UNKNOWN_QUOTA_BYTES:
                    percent = round(used / total * 100.0, 1)
                    quota_data = {
                        "total": total,
                        "used": used,
                        "free": free,
                        "trashed": 0,
                        "percent": percent,
                        "known": True,
                    }
                    cache = self._load_quota_cache()
                    cache[remote_name] = {"timestamp": now, "data": quota_data}
                    self._save_quota_cache(cache)
                    return quota_data
            except OSError:
                pass

        # 2. Check existing cache
        cache = self._load_quota_cache()
        cached = cache.get(remote_name)
        if cached and cached.get("data", {}).get("known"):
            # If we have known cached data and not force refresh, use it for up to 15 minutes
            if not force_refresh and (now - cached.get("timestamp", 0) < 900):
                return cached.get("data", {})

        if not self.rclone_bin:
            return {}

        quota_data = {
            "total": 0,
            "used": 0,
            "free": 0,
            "trashed": 0,
            "percent": 0.0,
            "known": False,
        }

        # 3. Query rclone about for unmounted remotes
        try:
            res = subprocess.run(
                [self.rclone_bin, "about", f"{remote_name}:", "--json"],
                capture_output=True,
                text=True,
                timeout=12,
                check=False,
            )
            if res.returncode == 0 and res.stdout.strip():
                about = json.loads(res.stdout)
                total = int(about.get("total", 0) or 0)
                used = int(about.get("used", 0) or 0)
                free = int(about.get("free", 0) or 0)
                trashed = int(about.get("trashed", 0) or 0)
                percent = (used / total * 100.0) if total > 0 else 0.0

                if total > 0 and total < UNKNOWN_QUOTA_BYTES:
                    quota_data = {
                        "total": total,
                        "used": used,
                        "free": free,
                        "trashed": trashed,
                        "percent": round(percent, 1),
                        "known": True,
                    }
                    cache[remote_name] = {"timestamp": now, "data": quota_data}
                    self._save_quota_cache(cache)
                    return quota_data
        except (subprocess.SubprocessError, OSError, json.JSONDecodeError):
            pass

        # If rclone about failed but we have a previous known quota, retain it
        if cached and cached.get("data", {}).get("known"):
            return cached.get("data", {})

        # Cache transient failure for only 30 seconds
        cache[remote_name] = {"timestamp": now - 570, "data": quota_data}
        self._save_quota_cache(cache)
        return quota_data

    def scan_recent_files(self, remote_name: str, limit: int = 8, max_depth: int = 2) -> List[dict]:
        """Scan recently modified files in a mounted drive directory with depth bounding."""
        is_mounted, mount_path = self.is_remote_mounted(remote_name)
        if not is_mounted or not os.path.exists(mount_path):
            return []

        recent = []
        counter = 0
        mount_depth = mount_path.rstrip(os.sep).count(os.sep)
        max_files_to_check = 250
        checked = 0

        try:
            for root, dirs, files in os.walk(mount_path):
                # Every directory listed over FUSE costs a remote API call, so stop walking once the budget is spent
                if checked >= max_files_to_check:
                    break

                # Depth limiter prevents slow deep directory crawling over FUSE
                current_depth = root.rstrip(os.sep).count(os.sep) - mount_depth
                if current_depth >= max_depth:
                    dirs.clear()

                # Don't follow symlinks
                dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
                # Ignore hidden directories like .cache, .tmp, and OneDrive Personal Vault
                dirs[:] = [d for d in dirs if not d.startswith(".") and d.lower() != "personal vault"]

                for name in files:
                    if checked >= max_files_to_check:
                        break
                    checked += 1
                    if name.startswith("."):
                        continue
                    file_path = os.path.join(root, name)
                    if os.path.islink(file_path):
                        continue
                    try:
                        st = os.stat(file_path)
                    except OSError:
                        continue

                    rel_path = os.path.relpath(file_path, mount_path)
                    folder = os.path.dirname(rel_path)
                    entry = {
                        "name": name,
                        "path": file_path,
                        "relPath": rel_path,
                        "folder": "/" if folder in ("", ".") else folder,
                        "remote": remote_name,
                        "modifiedTs": int(st.st_mtime),
                        "sizeBytes": st.st_size,
                    }
                    counter += 1
                    item = (entry["modifiedTs"], counter, entry)
                    if len(recent) < limit:
                        heapq.heappush(recent, item)
                    else:
                        heapq.heappushpop(recent, item)
        except OSError:
            return []

        return [item[2] for item in sorted(recent, reverse=True)]

    def mount(self, remote_name: str) -> Tuple[bool, str]:
        """Mount a remote using rclone mount in daemon mode."""
        if not self.rclone_bin:
            return False, "rclone is not installed"

        # Ensure OneDrive remote has required drive_id / drive_type
        self._ensure_onedrive_drive(remote_name)

        is_mounted, mount_path = self.is_remote_mounted(remote_name)
        if is_mounted:
            return True, f"{remote_name} is already mounted at {mount_path}"

        mount_dir = get_mount_path_for_remote(remote_name)

        # Clear any stale or broken mount on the directory before mounting
        try:
            active = self.get_active_mounts()
            if str(mount_dir) in active:
                if self.fusermount_bin:
                    subprocess.run([self.fusermount_bin, "-u", "-z", str(mount_dir)], capture_output=True, check=False)
            elif os.path.exists(str(mount_dir)):
                try:
                    if os.path.ismount(str(mount_dir)):
                        if self.fusermount_bin:
                            subprocess.run([self.fusermount_bin, "-u", "-z", str(mount_dir)], capture_output=True, check=False)
                except OSError:
                    # Stale FUSE mount
                    if self.fusermount_bin:
                        subprocess.run([self.fusermount_bin, "-u", "-z", str(mount_dir)], capture_output=True, check=False)
        except Exception:
            pass

        # Only after clearing stale mounts: mkdir on a dead FUSE mount point raises
        try:
            mount_dir.mkdir(parents=True, exist_ok=True)
        except OSError as e:
            return False, f"Cannot create mount directory {mount_dir}: {e}"

        cfg = load_config()
        vfs_mode = cfg.get("vfs_cache_mode", "full")
        cache_max_gb = cfg.get("cache_max_size_gb", 10)
        cache_age = cfg.get("cache_max_age", "24h")

        log_file = self.state_dir / f"mount_{remote_name}.log"
        # rclone would create the log with the umask's permissions; create it private first
        try:
            open_private(log_file, "a").close()
        except OSError:
            pass

        cmd = [
            self.rclone_bin,
            "mount",
            f"{remote_name}:",
            str(mount_dir),
            f"--vfs-cache-mode={vfs_mode}",
            f"--vfs-cache-max-size={cache_max_gb}G",
            f"--vfs-cache-max-age={cache_age}",
            "--daemon",
            "--daemon-timeout=20s",
            f"--log-file={log_file}",
            "--log-level=INFO",
        ]

        try:
            # Note: Do NOT use capture_output=True. rclone --daemon forks a background daemon
            # which inherits stdout/stderr pipes. capture_output=True causes Python to wait for
            # EOF on the pipes until timeout expires and kills the daemon.
            subprocess.run(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
                check=False,
            )
            # Give it a moment to attach
            time.sleep(1.0)
            mounted, actual_path = self.is_remote_mounted(remote_name)
            if mounted:
                return True, f"Mounted {remote_name} at {actual_path}"

            # If not mounted, read error from the log file
            err_msg = ""
            if log_file.exists():
                try:
                    with open(log_file, "r", encoding="utf-8", errors="replace") as f:
                        lines = [l.strip() for l in f if l.strip()]
                        for line in reversed(lines[-15:]):
                            if "ERROR" in line or "CRITICAL" in line or "failed" in line:
                                err_msg = line
                                break
                        if not err_msg and lines:
                            err_msg = lines[-1]
                        err_msg = neutralize_controls(err_msg)
                except Exception:
                    pass

            return False, f"Failed to mount {remote_name}: {err_msg or 'Mount verification failed'}"
        except subprocess.TimeoutExpired:
            return False, f"Mount command timed out for {remote_name}"
        except OSError as e:
            return False, f"Failed to start mount process: {e}"

    def unmount(self, remote_name: str) -> Tuple[bool, str]:
        """Unmount a remote cleanly using fusermount."""
        is_mounted, mount_path = self.is_remote_mounted(remote_name)
        active_mounts = self.get_active_mounts()
        needs_unmount = is_mounted or (mount_path in active_mounts)
        if not needs_unmount:
            try:
                if os.path.ismount(mount_path):
                    needs_unmount = True
            except OSError:
                needs_unmount = True

        if not needs_unmount:
            return True, f"{remote_name} is not mounted"

        # Try fusermount3 / fusermount first
        if self.fusermount_bin:
            res = subprocess.run(
                [self.fusermount_bin, "-u", mount_path],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            if res.returncode == 0:
                return True, f"Unmounted {remote_name}"

        # Try standard umount
        res = subprocess.run(
            ["umount", mount_path],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if res.returncode == 0:
            return True, f"Unmounted {remote_name}"

        # Check if process is still holding it and try lazy unmount if needed
        if self.fusermount_bin:
            subprocess.run(
                [self.fusermount_bin, "-u", "-z", mount_path],
                capture_output=True,
                check=False,
            )

        mounted, _ = self.is_remote_mounted(remote_name)
        if not mounted:
            return True, f"Unmounted {remote_name}"

        return False, f"Could not unmount {mount_path}"

    def mount_all(self) -> Dict[str, bool]:
        """Mount all configured remotes."""
        remotes = self.list_remotes()
        results = {}
        for name in remotes.keys():
            ok, _ = self.mount(name)
            results[name] = ok
        return results

    def auto_mount(self) -> Dict[str, bool]:
        """Mount remotes flagged for auto-mount; a per-remote auto_mount overrides auto_mount_all."""
        cfg = load_config()
        default = cfg.get("auto_mount_all", True)
        remotes_cfg = cfg.get("remotes", {})
        results = {}
        for name in self.list_remotes().keys():
            if remotes_cfg.get(name, {}).get("auto_mount", default):
                ok, _ = self.mount(name)
                results[name] = ok
        return results

    def unmount_all(self) -> Dict[str, bool]:
        """Unmount all currently mounted remotes."""
        remotes = self.list_remotes()
        results = {}
        for name in remotes.keys():
            is_mounted, _ = self.is_remote_mounted(name)
            if is_mounted:
                ok, _ = self.unmount(name)
                results[name] = ok
        return results

    def remove_remote(self, remote_name: str) -> Tuple[bool, str]:
        """Unmount and delete remote from rclone."""
        self.unmount(remote_name)
        if not self.rclone_bin:
            return False, "rclone is not installed"
        try:
            res = subprocess.run(
                [self.rclone_bin, "config", "delete", remote_name],
                capture_output=True,
                text=True,
                timeout=5,
                check=False,
            )
            if res.returncode == 0:
                # Remove from custom settings if any
                cfg = load_config()
                if "remotes" in cfg and remote_name in cfg["remotes"]:
                    del cfg["remotes"][remote_name]
                    save_config(cfg)
                return True, f"Deleted remote {remote_name}"
            return False, res.stderr.strip() or "Failed to delete remote"
        except OSError as e:
            return False, str(e)

    def test_remote(self, remote_name: str, timeout_sec: int = 10) -> Tuple[bool, str]:
        """Verify that remote is reachable and credentials are valid."""
        if not self.rclone_bin:
            return False, "rclone is not installed"

        self._ensure_onedrive_drive(remote_name)

        try:
            res = subprocess.run(
                [self.rclone_bin, "lsf", f"{remote_name}:", "--max-depth", "1"],
                capture_output=True,
                text=True,
                timeout=timeout_sec,
                check=False,
            )
            if res.returncode == 0:
                return True, "Connection verified successfully"
            err = (res.stderr or res.stdout or "Connection test failed").strip()
            lines = [
                re.sub(r"^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} (ERROR|CRITICAL|NOTICE): ", "", l)
                for l in err.splitlines()
            ]
            clean_err = "\n".join(l for l in lines if l.strip())
            return False, clean_err or "Authentication or connection failed"
        except subprocess.TimeoutExpired:
            return False, "Connection test timed out. Verify server address and network."
        except OSError as e:
            return False, str(e)

    def rename_remote(self, remote_name: str, new_name: str, mount_path: Optional[str] = None) -> Tuple[bool, str]:
        """Rename an rclone remote, carrying its ODrive settings, quota cache and mount log across."""
        if not self.rclone_bin:
            return False, "rclone is not installed"

        clean_name = new_name.strip()
        if not clean_name:
            return False, "New name cannot be empty"
        if clean_name != "".join(c for c in clean_name if c.isalnum() or c in ("-", "_")):
            return False, "Names may only contain letters, digits, '-' and '_'"
        # rclone rejects names starting with '-' (they would read as command-line flags)
        if clean_name.startswith("-"):
            return False, "Names cannot start with '-'"
        # rclone's rename prompt reads a menu selection, so a digits-only name would pick the wrong remote
        if remote_name.isdigit() or clean_name.isdigit():
            return False, "Names cannot consist of digits only"

        remotes = self.list_remotes()
        if remote_name not in remotes:
            return False, f"No remote named '{remote_name}'"
        if clean_name == remote_name:
            if mount_path is not None:
                return self.set_remote_mount_path(remote_name, mount_path)
            return True, f"{remote_name} is unchanged"
        if clean_name in remotes:
            return False, f"A remote named '{clean_name}' already exists"

        was_mounted, _ = self.is_remote_mounted(remote_name)
        if was_mounted:
            ok, msg = self.unmount(remote_name)
            if not ok:
                return False, f"Cannot rename while mounted: {msg}"

        old_mount_dir = get_mount_path_for_remote(remote_name)

        # rclone has no 'config rename' subcommand, so drive its interactive menu:
        # r) Rename remote -> existing name -> new name. Input deliberately ends there: if rclone
        # re-prompts for any reason it hits EOF and changes nothing, rather than consuming further
        # lines as answers (a trailing "q" used to become the new name). A successful rename is
        # saved before rclone returns to the menu, so the EOF exit status is expected and ignored.
        try:
            subprocess.run(
                [self.rclone_bin, "config"],
                input=f"r\n{remote_name}\n{clean_name}\n",
                capture_output=True,
                text=True,
                timeout=20,
                check=False,
            )
        except (subprocess.SubprocessError, OSError) as e:
            return False, f"Failed to rename remote: {e}"

        # rclone reports menu problems by asking again rather than failing, so confirm the result
        remotes = self.list_remotes()
        if clean_name not in remotes or remote_name in remotes:
            if was_mounted:
                self.mount(remote_name)
            return False, f"rclone did not rename '{remote_name}'"

        cfg = load_config()
        remotes_cfg = cfg.setdefault("remotes", {})
        remote_cfg = remotes_cfg.pop(remote_name, {})
        if mount_path is not None:
            clean_path = mount_path.strip()
            if clean_path:
                remote_cfg["mount_path"] = clean_path
                remote_cfg["custom_mount_path"] = clean_path
            else:
                remote_cfg.pop("mount_path", None)
                remote_cfg.pop("custom_mount_path", None)
        if remote_cfg:
            remotes_cfg[clean_name] = remote_cfg
        save_config(cfg)

        cache = self._load_quota_cache()
        if remote_name in cache:
            cache[clean_name] = cache.pop(remote_name)
            self._save_quota_cache(cache)

        old_log = self.state_dir / f"mount_{remote_name}.log"
        if old_log.exists():
            try:
                old_log.replace(self.state_dir / f"mount_{clean_name}.log")
            except OSError:
                pass

        # Clean up the old default mount directory, but never one that still holds files
        try:
            if old_mount_dir != get_mount_path_for_remote(clean_name):
                old_mount_dir.rmdir()
        except OSError:
            pass

        target_path = str(get_mount_path_for_remote(clean_name))
        if was_mounted:
            ok, msg = self.mount(clean_name)
            if not ok:
                return False, f"Renamed to {clean_name} but remount failed: {msg}"
            return True, f"Renamed to {clean_name}, mounted at {target_path}"
        return True, f"Renamed {remote_name} to {clean_name}"

    def set_remote_mount_path(self, remote_name: str, new_path: str) -> Tuple[bool, str]:
        """Change the mount location of a specific remote and remount if needed."""
        is_mounted, old_path = self.is_remote_mounted(remote_name)
        if is_mounted:
            self.unmount(remote_name)

        cfg = load_config()
        if "remotes" not in cfg:
            cfg["remotes"] = {}
        if remote_name not in cfg["remotes"]:
            cfg["remotes"][remote_name] = {}

        clean_path = new_path.strip()
        if clean_path:
            cfg["remotes"][remote_name]["mount_path"] = clean_path
            cfg["remotes"][remote_name]["custom_mount_path"] = clean_path
        else:
            cfg["remotes"][remote_name].pop("mount_path", None)
            cfg["remotes"][remote_name].pop("custom_mount_path", None)

        save_config(cfg)

        target_path = str(get_mount_path_for_remote(remote_name))
        if is_mounted:
            ok, msg = self.mount(remote_name)
            if ok:
                return True, f"Remounted {remote_name} at {target_path}"
            return False, f"Updated location but remount failed: {msg}"
        return True, f"Updated mount location to {target_path}"

    def set_mount_root(self, new_root: str) -> Tuple[bool, str]:
        """Change default mount root for all remotes."""
        clean_root = new_root.strip()
        if not clean_root:
            return False, "Mount root cannot be empty"
        cfg = load_config()
        cfg["mount_root"] = clean_root
        save_config(cfg)
        return True, f"Default mount root set to {clean_root}"

    def add_remote_oauth(
        self,
        remote_name: str,
        provider_id: str,
        client_id: str = "",
        client_secret: str = "",
        mount_path: str = "",
        timeout_sec: int = 180,
    ) -> Tuple[bool, str]:
        """Run non-interactive browser OAuth flow for a cloud provider."""
        if not self.rclone_bin:
            return False, "rclone is not installed on this system"

        provider = PROVIDERS.get(provider_id, {})
        rclone_type = provider.get("rclone_type", provider_id)

        # Sanitize remote name
        clean_name = "".join(c for c in remote_name if c.isalnum() or c in ("-", "_")).strip()
        if not clean_name:
            clean_name = provider.get("name", "Cloud").replace(" ", "")

        existing = self.list_remotes()
        if clean_name in existing:
            return False, f"A remote named '{clean_name}' already exists. Please choose a different name."

        # A custom OAuth client goes to rclone through its RCLONE_<TYPE>_CLIENT_* variables:
        # the environment is readable only by this user, unlike argv, which every user can see.
        env = os.environ.copy()
        if client_id:
            env[f"RCLONE_{rclone_type.upper()}_CLIENT_ID"] = client_id
        if client_secret:
            env[f"RCLONE_{rclone_type.upper()}_CLIENT_SECRET"] = client_secret
        secrets = [client_secret]

        try:
            proc = subprocess.Popen(
                [self.rclone_bin, "authorize", rclone_type],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=env,
                # Cancelling kills odrive; authorize must not linger on the OAuth callback port
                preexec_fn=die_with_parent(),
            )
            try:
                stdout, stderr = proc.communicate(timeout=timeout_sec)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()
                return False, "Authorization timed out. Please try again."

            if proc.returncode != 0:
                # stdout is where rclone prints the token, so only stderr may be shown
                err = redact(stderr.strip(), secrets) or "Authorization process failed"
                return False, f"OAuth authorization failed: {err}"

            # Extract JSON token from stdout
            token_match = re.search(r"\{[\s\S]*\"access_token\"[\s\S]*\}", stdout)
            if not token_match:
                return False, "Did not receive a valid authentication token from browser authorization"

            token_str = token_match.group(0).strip()
            secrets.append(token_str)

            parameters = {"token": token_str, "config_is_local": "false"}
            if client_id:
                parameters["client_id"] = client_id
            if client_secret:
                parameters["client_secret"] = client_secret

            # OneDrive requires drive_id and drive_type to function
            if rclone_type == "onedrive":
                drive_id, drive_type = resolve_onedrive_drive(token_str)
                if drive_id:
                    parameters["drive_id"] = drive_id
                    parameters["drive_type"] = drive_type or "personal"

            ok, err = config_create(self.rclone_bin, clean_name, rclone_type, parameters)
            if not ok:
                return False, f"Failed to save remote configuration: {redact(err, secrets)}"

            if mount_path:
                cfg = load_config()
                if "remotes" not in cfg:
                    cfg["remotes"] = {}
                if clean_name not in cfg["remotes"]:
                    cfg["remotes"][clean_name] = {}
                cfg["remotes"][clean_name]["mount_path"] = mount_path.strip()
                save_config(cfg)

            # Trigger omarchy shell plugin rescan
            try:
                subprocess.run(["omarchy-shell", "shell", "rescanPlugins"], capture_output=True, timeout=2)
            except (subprocess.SubprocessError, OSError):
                pass

            return True, clean_name
        except OSError as e:
            return False, f"Error running authorization: {e}"

    def add_remote_credentials(
        self,
        remote_name: str,
        provider_id: str,
        options: dict,
        mount_path: str = "",
        test_connection: bool = True,
    ) -> Tuple[bool, str]:
        """Configure credentials-based remote (Nextcloud, WebDAV, S3, Proton Drive) without terminal."""
        if not self.rclone_bin:
            return False, "rclone is not installed on this system"

        provider = PROVIDERS.get(provider_id, {})
        rclone_type = provider.get("rclone_type", provider_id)

        # Sanitize remote name
        clean_name = "".join(c for c in remote_name if c.isalnum() or c in ("-", "_")).strip()
        if not clean_name:
            clean_name = provider.get("name", "Cloud").replace(" ", "")

        existing = self.list_remotes()
        if clean_name in existing:
            return False, f"A remote named '{clean_name}' already exists. Please choose a different name."

        # Everything goes to rclone over the private rc channel, never argv; rclone obscures passwords itself
        parameters: Dict[str, str] = {}

        if provider_id == "nextcloud" or (rclone_type == "webdav" and options.get("vendor") == "nextcloud"):
            url = options.get("url", "").strip()
            user = options.get("user", "").strip()
            password = options.get("pass", "").strip()

            if not url:
                return False, "Server URL is required"
            if not user:
                return False, "Username is required"
            if not password:
                return False, "Password or App Token is required"

            if not url.startswith("http://") and not url.startswith("https://"):
                url = "https://" + url

            if not ("/remote.php/dav/files/" in url or url.endswith("/remote.php/webdav")):
                url = url.rstrip("/") + f"/remote.php/dav/files/{user}"

            parameters.update({"url": url, "vendor": "nextcloud", "user": user, "pass": password})

        elif rclone_type == "webdav":
            url = options.get("url", "").strip()
            if not url:
                return False, "Server URL is required"
            if not url.startswith("http://") and not url.startswith("https://"):
                url = "https://" + url

            parameters["url"] = url
            for key in ("vendor", "user", "pass"):
                if options.get(key):
                    parameters[key] = str(options[key])

        elif rclone_type == "s3":
            parameters["provider"] = options.get("provider", "Other")
            for key in ("endpoint", "access_key_id", "secret_access_key", "region"):
                if options.get(key):
                    parameters[key] = str(options[key]).strip()

        elif rclone_type == "protondrive":
            username = options.get("username", "").strip()
            password = options.get("password", "").strip()
            if not username or not password:
                return False, "Username and password are required"
            parameters.update({"username": username, "password": password})
            if options.get("2fa"):
                parameters["2fa"] = str(options["2fa"]).strip()

        else:
            for k, v in options.items():
                if v is not None and str(v) != "":
                    parameters[k] = str(v)

        # Keep credential values out of any message shown to the user
        secrets = [v for k, v in parameters.items() if is_secret_key(k)]

        try:
            ok, err = config_create(self.rclone_bin, clean_name, rclone_type, parameters)
            if not ok:
                return False, f"Failed to configure remote: {redact(err, secrets)}"

            if test_connection:
                ok, test_err = self.test_remote(clean_name, timeout_sec=10)
                if not ok:
                    # Clean up failed remote
                    self.remove_remote(clean_name)
                    return False, f"Connection failed: {redact(test_err, secrets)}"

            if mount_path:
                cfg = load_config()
                if "remotes" not in cfg:
                    cfg["remotes"] = {}
                if clean_name not in cfg["remotes"]:
                    cfg["remotes"][clean_name] = {}
                cfg["remotes"][clean_name]["mount_path"] = mount_path.strip()
                save_config(cfg)

            try:
                subprocess.run(["omarchy-shell", "shell", "rescanPlugins"], capture_output=True, timeout=2)
            except (subprocess.SubprocessError, OSError):
                pass

            return True, clean_name
        except OSError as e:
            return False, f"Failed to execute configuration command: {e}"


    def get_status(self, include_recent: bool = True) -> dict:
        """Produce full status report for QML or CLI display."""
        installed = self.is_installed()
        version = self.get_rclone_version() if installed else ""
        mount_root = str(get_mount_root())
        remotes = self.list_remotes() if installed else {}
        cfg = load_config()
        remotes_cfg = cfg.get("remotes", {})

        drives = []
        all_recent = []
        mounted_count = 0

        for name, info in remotes.items():
            provider = detect_provider(info)
            mounted, mount_path = self.is_remote_mounted(name)
            if mounted:
                mounted_count += 1

            r_cfg = remotes_cfg.get(name, {})
            auto_mount = r_cfg.get("auto_mount", cfg.get("auto_mount_all", True))
            custom_label = r_cfg.get("label", name)

            # Quota info
            quota = self.get_quota(name)

            # Recent files if mounted
            files = []
            if mounted and include_recent:
                files = self.scan_recent_files(name, limit=5)
                all_recent.extend(files)

            drive_entry = {
                "name": name,
                "label": custom_label,
                "type": info.get("type", "other"),
                "provider": provider["name"],
                "providerId": provider["id"],
                "glyph": provider["glyph"],
                "color": provider["color"],
                "mounted": mounted,
                "mountPath": mount_path,
                "autoMount": auto_mount,
                "quotaTotal": quota.get("total", 0),
                "quotaUsed": quota.get("used", 0),
                "quotaFree": quota.get("free", 0),
                "quotaPercent": quota.get("percent", 0.0),
                "quotaKnown": quota.get("known", False),
                "files": files,
            }
            drives.append(drive_entry)

        # Sort drives: mounted first, then by name
        drives.sort(key=lambda d: (not d["mounted"], d["name"].lower()))
        all_recent.sort(key=lambda f: f.get("modifiedTs", 0), reverse=True)

        return {
            "ok": True,
            "installed": installed,
            "version": version,
            "mountRoot": mount_root,
            "totalDrives": len(drives),
            "mountedDrives": mounted_count,
            "allMounted": len(drives) > 0 and mounted_count == len(drives),
            "drives": drives,
            "recentFiles": all_recent[:10],
            "vfsCacheMode": cfg.get("vfs_cache_mode", "full"),
            "cacheMaxSizeGb": cfg.get("cache_max_size_gb", 10),
            "cacheMaxAge": cfg.get("cache_max_age", "24h"),
            "autoMountAll": cfg.get("auto_mount_all", True),
            "pollIntervalSec": cfg.get("poll_interval_sec", 30),
        }

    def list_dir(self, remote_name: str, subpath: str = "") -> List[dict]:
        """List files and folders in a remote, either locally if mounted or via rclone."""
        is_mounted, mount_path = self.is_remote_mounted(remote_name)
        subpath = subpath.strip("/")
        items = []

        if is_mounted and os.path.exists(mount_path):
            target_dir = Path(mount_path) / subpath if subpath else Path(mount_path)
            if target_dir.exists() and target_dir.is_dir():
                try:
                    with os.scandir(target_dir) as it:
                        for entry in it:
                            if entry.name.startswith("."):
                                continue
                            try:
                                is_dir = entry.is_dir()
                                st = entry.stat()
                                items.append({
                                    "name": entry.name,
                                    "isDir": is_dir,
                                    "size": 0 if is_dir else st.st_size,
                                    "modifiedTs": int(st.st_mtime),
                                    "path": entry.path,
                                    "relPath": f"{subpath}/{entry.name}".strip("/"),
                                })
                            except OSError:
                                continue
                except OSError:
                    pass
        elif self.rclone_bin:
            # Not mounted: query via rclone lsjson
            remote_target = f"{remote_name}:{subpath}" if subpath else f"{remote_name}:"
            try:
                res = subprocess.run(
                    [self.rclone_bin, "lsjson", remote_target, "--max-depth", "1"],
                    capture_output=True,
                    text=True,
                    timeout=8,
                    check=False,
                )
                if res.returncode == 0 and res.stdout.strip():
                    raw_items = json.loads(res.stdout)
                    for item in raw_items:
                        name = item.get("Name", "")
                        if name.startswith("."):
                            continue
                        is_dir = item.get("IsDir", False)
                        items.append({
                            "name": name,
                            "isDir": is_dir,
                            "size": 0 if is_dir else int(item.get("Size", 0) or 0),
                            "modifiedTs": 0,
                            "path": "",
                            "relPath": f"{subpath}/{name}".strip("/"),
                        })
            except (subprocess.SubprocessError, OSError, json.JSONDecodeError):
                pass

        # Sort: directories first, then alphabetical
        items.sort(key=lambda x: (not x["isDir"], x["name"].lower()))
        return items

    def get_log(self, remote_name: str, max_lines: int = 50) -> str:
        """Read recent mount logs for a remote."""
        log_file = self.state_dir / f"mount_{remote_name}.log"
        if not log_file.exists():
            return "No log file found."
        try:
            with open(log_file, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
                return neutralize_controls("".join(lines[-max_lines:]))
        except OSError as e:
            return f"Error reading log: {e}"


"""Preview mode: a stand-in for DriveManager that serves realistic sample data.

Lets anyone review or demo the plugin without rclone, cloud accounts or side
effects. Every command the widget sends behaves as it would for real (mounting,
renaming, removing, adding drives, errors), but only a small state file in the
runtime directory changes. Nothing is mounted, nothing touches rclone, the
ODrive config or the filesystem, and no credentials are stored.

Enable with `odrive --preview ...`, ODRIVE_PREVIEW=1, or the widget's
"Preview mode" setting.
"""

import contextlib
import fcntl
import json
import os
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .providers import PROVIDERS, detect_provider

# Simulated latency, so busy spinners and optimistic states are visible
_MOUNT_DELAY_SEC = 0.8
_AUTH_DELAY_SEC = 2.0
_CONNECT_DELAY_SEC = 1.0

# A drive that always fails to mount, so the error state can be reviewed too
FAILING_DRIVE = "Archive-S3"

_GB = 1024 ** 3
_TB = 1024 ** 4


def is_preview_requested(flag: bool = False) -> bool:
    return flag or os.environ.get("ODRIVE_PREVIEW", "").strip().lower() in ("1", "true", "yes", "on")


def _state_path() -> Path:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    base = Path(runtime_dir) if runtime_dir else Path(tempfile.gettempdir())
    return base / f"odrive-preview-{os.getuid()}.json"


def _seed_state() -> dict:
    """Sample drives covering every state the widget can show."""

    def drive(name, provider, mounted, total, used, vendor=""):
        return {"name": name, "type": PROVIDERS[provider]["rclone_type"], "vendor": vendor,
                "mounted": mounted, "quotaTotal": total, "quotaUsed": used, "mountPath": ""}

    return {
        "mountRoot": str(Path.home() / "Cloud"),
        "config": {"auto_mount_all": True, "vfs_cache_mode": "full", "cache_max_size_gb": 10,
                   "cache_max_age": "24h", "poll_interval_sec": 30},
        "drives": [
            drive("GoogleDrive", "drive", True, 5 * _TB, int(312 * _GB)),
            drive("OneDrive", "onedrive", True, 5 * _GB, int(4.7 * _GB)),  # >90%: urgent quota bar
            drive("Nextcloud", "nextcloud", True, 100 * _GB, int(37 * _GB), vendor="nextcloud"),
            drive("Dropbox", "dropbox", False, 2 * _GB, int(1.1 * _GB)),
            drive(FAILING_DRIVE, "s3", False, 0, 0),  # no quota support, always fails to mount
        ],
        # Ages in seconds; turned into timestamps at read time so they always look recent
        "recentFiles": [
            ("GoogleDrive", "Projects", "roadmap-2026.pdf", 240, 2_400_000),
            ("Nextcloud", "Photos/2026", "IMG_4521.jpg", 3_600, 4_100_000),
            ("OneDrive", "Documents", "Budget Q3.xlsx", 9_000, 86_000),
            ("GoogleDrive", "/", "meeting-notes.md", 20_000, 5_300),
            ("Nextcloud", "Shared", "team-offsite.pptx", 50_000, 12_000_000),
            ("OneDrive", "Documents", "Contract (signed).pdf", 90_000, 640_000),
            ("GoogleDrive", "Design", "logo-final-v3.svg", 200_000, 48_000),
            ("Nextcloud", "Backups", "dotfiles.tar.gz", 400_000, 9_800_000),
            ("GoogleDrive", "Projects", "thesis-draft.docx", 900_000, 1_200_000),
            ("OneDrive", "Pictures", "passport-scan.png", 2_000_000, 3_400_000),
        ],
    }


class PreviewManager:
    """Same interface as DriveManager, backed by sample data in a private state file."""

    preview = True
    rclone_bin = "rclone (preview)"

    def __init__(self):
        self.state_file = _state_path()

    # --- state -------------------------------------------------------------

    @contextlib.contextmanager
    def _state(self, write: bool = False):
        """Load state under an exclusive lock, so concurrent widget calls can't lose updates."""
        fd = os.open(self.state_file, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            with os.fdopen(os.dup(fd), "r", encoding="utf-8") as f:
                raw = f.read()
            try:
                state = json.loads(raw) if raw.strip() else None
            except json.JSONDecodeError:
                state = None
            if not isinstance(state, dict) or "drives" not in state:
                state = _seed_state()
                write = True
            yield state
            if write:
                data = json.dumps(state, indent=2).encode("utf-8")
                os.lseek(fd, 0, os.SEEK_SET)
                os.ftruncate(fd, 0)
                os.write(fd, data)
        finally:
            os.close(fd)

    def reset(self) -> None:
        with self._state(write=True) as state:
            state.clear()
            state.update(_seed_state())

    @staticmethod
    def _find(state: dict, name: str) -> Optional[dict]:
        return next((d for d in state["drives"] if d["name"] == name), None)

    @staticmethod
    def _mount_path(state: dict, drive: dict) -> str:
        return drive.get("mountPath") or os.path.join(state["mountRoot"], drive["name"])

    # --- status ------------------------------------------------------------

    def is_installed(self) -> bool:
        return True

    def get_rclone_version(self) -> str:
        return "rclone (preview mode: sample data)"

    def list_remotes(self) -> Dict[str, dict]:
        with self._state() as state:
            return {d["name"]: {"type": d["type"], "vendor": d.get("vendor", "")} for d in state["drives"]}

    def get_status(self, include_recent: bool = True) -> dict:
        now = int(time.time())
        with self._state() as state:
            cfg = state["config"]
            drives = []
            for d in state["drives"]:
                provider = detect_provider({"type": d["type"], "vendor": d.get("vendor", "")})
                total, used = d["quotaTotal"], d["quotaUsed"]
                known = total > 0
                drives.append({
                    "name": d["name"],
                    "label": d["name"],
                    "type": d["type"],
                    "provider": provider["name"],
                    "providerId": provider["id"],
                    "glyph": provider["glyph"],
                    "color": provider["color"],
                    "mounted": d["mounted"],
                    "mountPath": self._mount_path(state, d),
                    "autoMount": cfg.get("auto_mount_all", True),
                    "quotaTotal": total,
                    "quotaUsed": used,
                    "quotaFree": max(0, total - used),
                    "quotaPercent": round(used / total * 100.0, 1) if known else 0.0,
                    "quotaKnown": known,
                    "files": [],
                })
            recent = []
            if include_recent:
                mounted = {d["name"]: d for d in state["drives"] if d["mounted"]}
                for remote, folder, name, age, size in state["recentFiles"]:
                    if remote not in mounted:
                        continue
                    base = self._mount_path(state, mounted[remote])
                    rel = name if folder == "/" else f"{folder}/{name}"
                    recent.append({
                        "name": name,
                        "path": os.path.join(base, rel),
                        "relPath": rel,
                        "folder": folder,
                        "remote": remote,
                        "modifiedTs": now - age,
                        "sizeBytes": size,
                    })
            drives.sort(key=lambda d: (not d["mounted"], d["name"].lower()))
            mounted_count = sum(1 for d in drives if d["mounted"])
            return {
                "ok": True,
                "preview": True,
                "installed": True,
                "version": self.get_rclone_version(),
                "mountRoot": state["mountRoot"],
                "totalDrives": len(drives),
                "mountedDrives": mounted_count,
                "allMounted": len(drives) > 0 and mounted_count == len(drives),
                "drives": drives,
                "recentFiles": recent[:10],
                "vfsCacheMode": cfg.get("vfs_cache_mode", "full"),
                "cacheMaxSizeGb": cfg.get("cache_max_size_gb", 10),
                "cacheMaxAge": cfg.get("cache_max_age", "24h"),
                "autoMountAll": cfg.get("auto_mount_all", True),
                "pollIntervalSec": cfg.get("poll_interval_sec", 30),
            }

    # --- mounting ----------------------------------------------------------

    def mount(self, remote_name: str) -> Tuple[bool, str]:
        time.sleep(_MOUNT_DELAY_SEC)
        with self._state(write=True) as state:
            d = self._find(state, remote_name)
            if d is None:
                return False, f"Failed to mount {remote_name}: no remote named '{remote_name}'"
            if d["mounted"]:
                return True, f"{remote_name} is already mounted at {self._mount_path(state, d)}"
            if remote_name == FAILING_DRIVE:
                return False, (f"Failed to mount {remote_name}: this preview drive always fails, "
                               "to show how mount errors look")
            d["mounted"] = True
            return True, f"Mounted {remote_name} at {self._mount_path(state, d)}"

    def unmount(self, remote_name: str) -> Tuple[bool, str]:
        time.sleep(_MOUNT_DELAY_SEC / 2)
        with self._state(write=True) as state:
            d = self._find(state, remote_name)
            if d is None or not d["mounted"]:
                return True, f"{remote_name} is not mounted"
            d["mounted"] = False
            return True, f"Unmounted {remote_name}"

    def mount_all(self) -> Dict[str, bool]:
        return {name: self.mount(name)[0] for name in self.list_remotes()}

    def unmount_all(self) -> Dict[str, bool]:
        with self._state() as state:
            names = [d["name"] for d in state["drives"] if d["mounted"]]
        return {name: self.unmount(name)[0] for name in names}

    def auto_mount(self) -> Dict[str, bool]:
        with self._state() as state:
            enabled = state["config"].get("auto_mount_all", True)
            names = [d["name"] for d in state["drives"] if not d["mounted"] and d["name"] != FAILING_DRIVE]
        return {name: self.mount(name)[0] for name in names} if enabled else {}

    # --- editing -----------------------------------------------------------

    @staticmethod
    def _validate_name(name: str) -> Optional[str]:
        # Same rules as the real rename, so reviewers see the same messages
        if not name:
            return "New name cannot be empty"
        if name != "".join(c for c in name if c.isalnum() or c in ("-", "_")):
            return "Names may only contain letters, digits, '-' and '_'"
        if name.startswith("-"):
            return "Names cannot start with '-'"
        if name.isdigit():
            return "Names cannot consist of digits only"
        return None

    def rename_remote(self, remote_name: str, new_name: str, mount_path: Optional[str] = None) -> Tuple[bool, str]:
        clean = new_name.strip()
        err = self._validate_name(clean)
        if err:
            return False, err
        with self._state(write=True) as state:
            d = self._find(state, remote_name)
            if d is None:
                return False, f"No remote named '{remote_name}'"
            if clean != remote_name and self._find(state, clean) is not None:
                return False, f"A remote named '{clean}' already exists"
            if mount_path is not None:
                d["mountPath"] = os.path.expanduser(mount_path.strip()) if mount_path.strip() else ""
            if clean == remote_name:
                if mount_path is not None:
                    return True, f"Updated mount location to {self._mount_path(state, d)}"
                return True, f"{remote_name} is unchanged"
            d["name"] = clean
            state["recentFiles"] = [
                [clean if r == remote_name else r, *rest] for r, *rest in state["recentFiles"]
            ]
            return True, f"Renamed {remote_name} to {clean}"

    def set_remote_mount_path(self, remote_name: str, new_path: str) -> Tuple[bool, str]:
        with self._state(write=True) as state:
            d = self._find(state, remote_name)
            if d is None:
                return False, f"No remote named '{remote_name}'"
            d["mountPath"] = os.path.expanduser(new_path.strip()) if new_path.strip() else ""
            return True, f"Updated mount location to {self._mount_path(state, d)}"

    def set_mount_root(self, new_root: str) -> Tuple[bool, str]:
        clean = new_root.strip()
        if not clean:
            return False, "Mount root cannot be empty"
        with self._state(write=True) as state:
            state["mountRoot"] = os.path.expanduser(clean)
        return True, f"Default mount root set to {clean}"

    def remove_remote(self, remote_name: str) -> Tuple[bool, str]:
        with self._state(write=True) as state:
            d = self._find(state, remote_name)
            if d is None:
                return False, f"No remote named '{remote_name}'"
            state["drives"].remove(d)
            state["recentFiles"] = [f for f in state["recentFiles"] if f[0] != remote_name]
            return True, f"Deleted remote {remote_name}"

    def test_remote(self, remote_name: str, timeout_sec: int = 10) -> Tuple[bool, str]:
        time.sleep(_CONNECT_DELAY_SEC / 2)
        if remote_name == FAILING_DRIVE:
            return False, "Preview drive: connection always fails, to show how errors look"
        if remote_name not in self.list_remotes():
            return False, f"No remote named '{remote_name}'"
        return True, "Connection verified successfully (preview)"

    # --- adding ------------------------------------------------------------

    def _add(self, remote_name: str, provider_id: str, mount_path: str) -> Tuple[bool, str]:
        provider = PROVIDERS.get(provider_id)
        if provider is None:
            return False, f"Failed to configure remote: couldn't find backend for type \"{provider_id}\""
        clean = "".join(c for c in remote_name if c.isalnum() or c in ("-", "_")).strip()
        if not clean:
            clean = provider["name"].replace(" ", "")
        err = self._validate_name(clean)
        if err:
            return False, err
        with self._state(write=True) as state:
            if self._find(state, clean) is not None:
                return False, f"A remote named '{clean}' already exists. Please choose a different name."
            total = 15 * _GB if provider.get("supports_quota") else 0
            state["drives"].append({
                "name": clean,
                "type": provider["rclone_type"],
                "vendor": provider.get("vendor", ""),
                "mounted": False,
                "quotaTotal": total,
                "quotaUsed": int(total * 0.02),
                "mountPath": os.path.expanduser(mount_path.strip()) if mount_path.strip() else "",
            })
        return True, clean

    def add_remote_oauth(self, remote_name: str, provider_id: str, client_id: str = "",
                         client_secret: str = "", mount_path: str = "", timeout_sec: int = 180) -> Tuple[bool, str]:
        # Stands in for the browser sign-in; no browser opens and nothing is authorised
        time.sleep(_AUTH_DELAY_SEC)
        return self._add(remote_name, provider_id, mount_path)

    def add_remote_credentials(self, remote_name: str, provider_id: str, options: dict,
                               mount_path: str = "", test_connection: bool = True) -> Tuple[bool, str]:
        # Same required fields as the real flow; the values themselves are never stored
        required = {
            "nextcloud": [("url", "Server URL is required"), ("user", "Username is required"),
                          ("pass", "Password or App Token is required")],
            "webdav": [("url", "Server URL is required")],
            "protondrive": [("username", "Username and password are required"),
                            ("password", "Username and password are required")],
        }
        for key, message in required.get(provider_id, []):
            if not str(options.get(key, "")).strip():
                return False, message
        time.sleep(_CONNECT_DELAY_SEC)
        return self._add(remote_name, provider_id, mount_path)

    # --- browsing ----------------------------------------------------------

    def list_dir(self, remote_name: str, subpath: str = "") -> List[dict]:
        with self._state() as state:
            d = self._find(state, remote_name)
            if d is None:
                return []
            base = self._mount_path(state, d)
            now = int(time.time())
            folders = sorted({f[1].split("/")[0] for f in state["recentFiles"] if f[0] == remote_name and f[1] != "/"})
            items = [{"name": n, "isDir": True, "size": 0, "modifiedTs": now - 86_400,
                      "path": os.path.join(base, n), "relPath": n} for n in folders]
            items += [{"name": f[2], "isDir": False, "size": f[4], "modifiedTs": now - f[3],
                       "path": os.path.join(base, f[2]), "relPath": f[2]}
                      for f in state["recentFiles"] if f[0] == remote_name and f[1] == "/"]
            return items if not subpath else []

    def get_log(self, remote_name: str, max_lines: int = 50) -> str:
        stamp = time.strftime("%Y/%m/%d %H:%M:%S")
        if remote_name == FAILING_DRIVE:
            return f"{stamp} ERROR : {remote_name}: preview drive, mounting always fails\n"
        return (f"{stamp} INFO  : {remote_name}: preview mode, no real mount\n"
                f"{stamp} INFO  : {remote_name}: vfs cache: sample data only\n")

    # --- config ------------------------------------------------------------

    def load_config(self) -> dict:
        with self._state() as state:
            return dict(state["config"], mount_root=state["mountRoot"])

    def save_config(self, cfg: dict) -> None:
        with self._state(write=True) as state:
            state["mountRoot"] = cfg.pop("mount_root", state["mountRoot"])
            state["config"] = cfg

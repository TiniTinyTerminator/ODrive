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

from .config import (
    get_config_dir,
    get_mount_path_for_remote,
    get_mount_root,
    get_state_dir,
    load_config,
    save_config,
)
from .providers import PROVIDERS, detect_provider


class DriveManager:
    def __init__(self):
        self.rclone_bin = shutil.which("rclone")
        self.fusermount_bin = shutil.which("fusermount3") or shutil.which("fusermount")
        self.state_dir = get_state_dir()
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.cache_file = self.state_dir / "quota_cache.json"

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
                        device = parts[0]
                        mount_point = parts[1]
                        fstype = parts[2] if len(parts) > 2 else ""
                        # rclone mounts usually show device as '<remote>:' or fstype 'fuse.rclone'
                        if "rclone" in fstype or ":" in device:
                            remote_name = device.rstrip(":")
                            # Also check if it's within our mount_root
                            if mount_point.startswith(mount_root) or "rclone" in fstype:
                                mounts[mount_point] = {
                                    "remote": remote_name,
                                    "mount_point": mount_point,
                                    "fstype": fstype,
                                }
        except OSError:
            pass
        return mounts

    def is_remote_mounted(self, remote_name: str) -> Tuple[bool, str]:
        """Check if remote is currently mounted and return (is_mounted, mount_path)."""
        expected_path = str(get_mount_path_for_remote(remote_name))
        active_mounts = self.get_active_mounts()

        # Check by expected mount path
        if expected_path in active_mounts:
            return True, expected_path

        # Check by remote name in active mounts
        for mp, info in active_mounts.items():
            if info.get("remote") == remote_name:
                return True, mp

        # Fallback check: os.path.ismount
        if os.path.exists(expected_path) and os.path.ismount(expected_path):
            return True, expected_path

        return False, expected_path

    def _load_quota_cache(self) -> dict:
        if not self.cache_file.exists():
            return {}
        try:
            with open(self.cache_file, "r", encoding="utf-8") as f:
                return json.load(f)
        except (OSError, json.JSONDecodeError):
            return {}

    def _save_quota_cache(self, cache: dict) -> None:
        try:
            with open(self.cache_file, "w", encoding="utf-8") as f:
                json.dump(cache, f, indent=2)
        except OSError:
            pass

    def get_quota(self, remote_name: str, force_refresh: bool = False) -> dict:
        """Fetch quota for a remote using 'rclone about <remote>: --json' with caching."""
        cache = self._load_quota_cache()
        now = time.time()
        cached = cache.get(remote_name)

        # 10 minute cache unless force_refresh
        if not force_refresh and cached and (now - cached.get("timestamp", 0) < 600):
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

        try:
            res = subprocess.run(
                [self.rclone_bin, "about", f"{remote_name}:", "--json"],
                capture_output=True,
                text=True,
                timeout=6,
                check=False,
            )
            if res.returncode == 0 and res.stdout.strip():
                about = json.loads(res.stdout)
                total = int(about.get("total", 0) or 0)
                used = int(about.get("used", 0) or 0)
                free = int(about.get("free", 0) or 0)
                trashed = int(about.get("trashed", 0) or 0)
                percent = (used / total * 100.0) if total > 0 else 0.0

                quota_data = {
                    "total": total,
                    "used": used,
                    "free": free,
                    "trashed": trashed,
                    "percent": round(percent, 1),
                    "known": total > 0,
                }
        except (subprocess.SubprocessError, OSError, json.JSONDecodeError):
            pass

        # Save to cache
        cache[remote_name] = {"timestamp": now, "data": quota_data}
        self._save_quota_cache(cache)
        return quota_data

    def scan_recent_files(self, remote_name: str, limit: int = 8) -> List[dict]:
        """Scan recently modified files in a mounted drive directory."""
        is_mounted, mount_path = self.is_remote_mounted(remote_name)
        if not is_mounted or not os.path.exists(mount_path):
            return []

        recent = []
        counter = 0
        try:
            for root, dirs, files in os.walk(mount_path):
                # Don't follow symlinks
                dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(root, d))]
                # Ignore hidden directories like .cache, .tmp
                dirs[:] = [d for d in dirs if not d.startswith(".")]

                for name in files:
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

        is_mounted, mount_path = self.is_remote_mounted(remote_name)
        if is_mounted:
            return True, f"{remote_name} is already mounted at {mount_path}"

        mount_dir = get_mount_path_for_remote(remote_name)
        mount_dir.mkdir(parents=True, exist_ok=True)

        cfg = load_config()
        vfs_mode = cfg.get("vfs_cache_mode", "full")
        cache_max_gb = cfg.get("cache_max_size_gb", 10)
        cache_age = cfg.get("cache_max_age", "24h")

        log_file = self.state_dir / f"mount_{remote_name}.log"

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
        ]

        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=25, check=False)
            # Give it a moment to attach
            time.sleep(0.5)
            mounted, actual_path = self.is_remote_mounted(remote_name)
            if mounted:
                return True, f"Mounted {remote_name} at {actual_path}"
            err = (res.stderr or res.stdout or "Mount verification timed out").strip()
            return False, f"Failed to mount {remote_name}: {err}"
        except subprocess.TimeoutExpired:
            return False, f"Mount command timed out for {remote_name}"
        except OSError as e:
            return False, f"Failed to start mount process: {e}"

    def unmount(self, remote_name: str) -> Tuple[bool, str]:
        """Unmount a remote cleanly using fusermount."""
        is_mounted, mount_path = self.is_remote_mounted(remote_name)
        if not is_mounted:
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

    def add_remote_oauth(
        self,
        remote_name: str,
        provider_id: str,
        client_id: str = "",
        client_secret: str = "",
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

        cmd = [self.rclone_bin, "authorize", rclone_type]
        if client_id and client_secret:
            cmd.extend([client_id, client_secret])

        try:
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                stdout, stderr = proc.communicate(timeout=timeout_sec)
            except subprocess.TimeoutExpired:
                proc.kill()
                return False, "Authorization timed out. Please try again."

            if proc.returncode != 0:
                err = stderr.strip() or stdout.strip() or "Authorization process failed"
                return False, f"OAuth authorization failed: {err}"

            # Extract JSON token from stdout
            token_match = re.search(r"\{[\s\S]*\"access_token\"[\s\S]*\}", stdout)
            if not token_match:
                token_match = re.search(r"\{[\s\S]*\"[a-zA-Z0-9_-]+\":\s*\"[\s\S]+\"[\s\S]*\}", stdout)

            if not token_match:
                return False, f"Did not receive a valid authentication token from browser authorization"

            token_str = token_match.group(0).strip()

            # Create remote via rclone config create
            create_cmd = [
                self.rclone_bin,
                "config",
                "create",
                clean_name,
                rclone_type,
                "token",
                token_str,
                "config_is_local",
                "false",
            ]
            if client_id:
                create_cmd.extend(["client_id", client_id])
            if client_secret:
                create_cmd.extend(["client_secret", client_secret])

            create_res = subprocess.run(
                create_cmd,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )
            if create_res.returncode != 0:
                err = create_res.stderr.strip() or create_res.stdout.strip()
                return False, f"Failed to save remote configuration: {err}"

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

        create_args = [self.rclone_bin, "config", "create", clean_name, rclone_type]

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

            create_args.extend([
                "url", url,
                "vendor", "nextcloud",
                "user", user,
                "pass", password,
            ])

        elif rclone_type == "webdav":
            url = options.get("url", "").strip()
            if not url:
                return False, "Server URL is required"
            if not url.startswith("http://") and not url.startswith("https://"):
                url = "https://" + url

            create_args.extend(["url", url])
            if options.get("vendor"):
                create_args.extend(["vendor", options["vendor"]])
            if options.get("user"):
                create_args.extend(["user", options["user"]])
            if options.get("pass"):
                create_args.extend(["pass", options["pass"]])

        elif rclone_type == "s3":
            prov = options.get("provider", "Other")
            create_args.extend(["provider", prov])
            if options.get("endpoint"):
                create_args.extend(["endpoint", options["endpoint"].strip()])
            if options.get("access_key_id"):
                create_args.extend(["access_key_id", options["access_key_id"].strip()])
            if options.get("secret_access_key"):
                create_args.extend(["secret_access_key", options["secret_access_key"].strip()])
            if options.get("region"):
                create_args.extend(["region", options["region"].strip()])

        elif rclone_type == "protondrive":
            username = options.get("username", "").strip()
            password = options.get("password", "").strip()
            if not username or not password:
                return False, "Username and password are required"
            create_args.extend(["username", username, "password", password])
            if options.get("2fa"):
                create_args.extend(["2fa", options["2fa"].strip()])

        else:
            for k, v in options.items():
                if v is not None and str(v) != "":
                    create_args.extend([k, str(v)])

        try:
            res = subprocess.run(
                create_args,
                capture_output=True,
                text=True,
                timeout=12,
                check=False,
            )
            if res.returncode != 0:
                err = res.stderr.strip() or res.stdout.strip()
                return False, f"Failed to configure remote: {err}"

            if test_connection:
                ok, test_err = self.test_remote(clean_name, timeout_sec=10)
                if not ok:
                    # Clean up failed remote
                    self.remove_remote(clean_name)
                    return False, f"Connection failed: {test_err}"

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
                return "".join(lines[-max_lines:])
        except OSError as e:
            return f"Error reading log: {e}"


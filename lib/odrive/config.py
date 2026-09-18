"""Configuration manager for ODrive."""

import json
import os
from pathlib import Path

DEFAULT_CONFIG = {
    "mount_root": "~/Cloud",
    "vfs_cache_mode": "full",
    "cache_max_size_gb": 10,
    "cache_max_age": "24h",
    "auto_mount_all": True,
    "poll_interval_sec": 30,
    "remotes": {}
}


def get_config_dir() -> Path:
    config_home = os.environ.get("XDG_CONFIG_HOME")
    if config_home:
        base = Path(config_home)
    else:
        base = Path.home() / ".config"
    return base / "odrive"


def get_state_dir() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    if state_home:
        base = Path(state_home)
    else:
        base = Path.home() / ".local" / "state"
    return base / "odrive"


def _migrate_legacy_settings() -> dict:
    """Read legacy settings from ~/.config/omarchy-cloud/settings.conf if present."""
    legacy_file = Path.home() / ".config" / "omarchy-cloud" / "settings.conf"
    migrated = {}
    if legacy_file.exists():
        try:
            with open(legacy_file, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip().strip('"').strip("'")
                    if k == "MOUNT_ROOT":
                        # Unescape backslash if any
                        migrated["mount_root"] = v.replace("\\~", "~")
                    elif k == "VFS_CACHE_MODE":
                        migrated["vfs_cache_mode"] = v
                    elif k == "CACHE_MAX_SIZE_GB":
                        try:
                            migrated["cache_max_size_gb"] = int(v)
                        except ValueError:
                            pass
        except OSError:
            pass
    return migrated


def load_config() -> dict:
    config_dir = get_config_dir()
    config_file = config_dir / "config.json"
    cfg = dict(DEFAULT_CONFIG)

    # Check for legacy settings
    legacy = _migrate_legacy_settings()
    cfg.update(legacy)

    if config_file.exists():
        try:
            with open(config_file, "r", encoding="utf-8") as f:
                saved = json.load(f)
                if isinstance(saved, dict):
                    cfg.update(saved)
        except (OSError, json.JSONDecodeError):
            pass

    return cfg


def save_config(cfg: dict) -> None:
    config_dir = get_config_dir()
    config_dir.mkdir(parents=True, exist_ok=True)
    config_file = config_dir / "config.json"
    temp_file = config_dir / "config.json.tmp"
    with open(temp_file, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    os.replace(temp_file, config_file)


def get_mount_root() -> Path:
    cfg = load_config()
    raw = cfg.get("mount_root", "~/Cloud")
    expanded = os.path.expanduser(raw)
    return Path(expanded).resolve()


def get_mount_path_for_remote(remote_name: str) -> Path:
    cfg = load_config()
    remotes = cfg.get("remotes", {})
    remote_cfg = remotes.get(remote_name, {})
    custom = remote_cfg.get("custom_mount_path")
    if custom:
        return Path(os.path.expanduser(custom)).resolve()
    return get_mount_root() / remote_name

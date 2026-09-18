"""Cloud provider metadata and definitions for ODrive."""

PROVIDERS = {
    "drive": {
        "id": "drive",
        "name": "Google Drive",
        "rclone_type": "drive",
        "glyph": "󰊭",
        "color": "#4285F4",
        "category": "Cloud",
        "description": "Google Drive (Personal, Workspace, Shared Drives)",
        "supports_quota": True,
        "default_scopes": "drive",
        "quick_setup": True,
    },
    "onedrive": {
        "id": "onedrive",
        "name": "Microsoft OneDrive",
        "rclone_type": "onedrive",
        "glyph": "󰏲",
        "color": "#0078D4",
        "category": "Cloud",
        "description": "OneDrive Personal, Business, SharePoint",
        "supports_quota": True,
        "quick_setup": True,
    },
    "dropbox": {
        "id": "dropbox",
        "name": "Dropbox",
        "rclone_type": "dropbox",
        "glyph": "",
        "color": "#0061FF",
        "category": "Cloud",
        "description": "Dropbox Personal & Business",
        "supports_quota": True,
        "quick_setup": True,
    },
    "nextcloud": {
        "id": "nextcloud",
        "name": "Nextcloud",
        "rclone_type": "webdav",
        "vendor": "nextcloud",
        "glyph": "󰒋",
        "color": "#0082C9",
        "category": "Self-hosted",
        "description": "Nextcloud / ownCloud self-hosted cloud storage",
        "supports_quota": True,
        "quick_setup": False,
    },
    "box": {
        "id": "box",
        "name": "Box",
        "rclone_type": "box",
        "glyph": "󰉉",
        "color": "#0061D5",
        "category": "Cloud",
        "description": "Box Enterprise & Personal storage",
        "supports_quota": True,
        "quick_setup": True,
    },
    "pcloud": {
        "id": "pcloud",
        "name": "pCloud",
        "rclone_type": "pcloud",
        "glyph": "󰅟",
        "color": "#14BF96",
        "category": "Cloud",
        "description": "pCloud secure encrypted cloud storage",
        "supports_quota": True,
        "quick_setup": True,
    },
    "protondrive": {
        "id": "protondrive",
        "name": "Proton Drive",
        "rclone_type": "protondrive",
        "glyph": "󰅟",
        "color": "#6D4AFF",
        "category": "Encrypted",
        "description": "Proton Drive end-to-end encrypted storage",
        "supports_quota": True,
        "quick_setup": True,
    },
    "webdav": {
        "id": "webdav",
        "name": "WebDAV",
        "rclone_type": "webdav",
        "glyph": "󰒋",
        "color": "#7E57C2",
        "category": "Protocol",
        "description": "Generic WebDAV server",
        "supports_quota": False,
        "quick_setup": False,
    },
    "s3": {
        "id": "s3",
        "name": "Amazon S3",
        "rclone_type": "s3",
        "glyph": "󰋊",
        "color": "#FF9900",
        "category": "Object Storage",
        "description": "Amazon S3, MinIO, Cloudflare R2, Wasabi, Backblaze B2",
        "supports_quota": False,
        "quick_setup": False,
    },
    "generic": {
        "id": "generic",
        "name": "Cloud Remote",
        "rclone_type": "other",
        "glyph": "󰅟",
        "color": "#A0A0A0",
        "category": "Other",
        "description": "Custom rclone configured remote",
        "supports_quota": False,
        "quick_setup": False,
    }
}


def detect_provider(remote_info: dict) -> dict:
    """Determine provider metadata from rclone remote config."""
    remote_type = remote_info.get("type", "").lower()
    vendor = remote_info.get("vendor", "").lower()

    if remote_type == "webdav" and vendor in ("nextcloud", "owncloud"):
        return PROVIDERS["nextcloud"]
    if remote_type in PROVIDERS:
        return PROVIDERS[remote_type]

    # Fallback to generic provider
    p = dict(PROVIDERS["generic"])
    p["name"] = remote_type.capitalize() if remote_type else "Cloud Remote"
    p["rclone_type"] = remote_type
    return p

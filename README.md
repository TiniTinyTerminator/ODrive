# ODrive — Unified Cloud Drive Manager for Omarchy

<p align="center">
  <b>Seamlessly mount, monitor, and manage Google Drive, OneDrive, Dropbox, Nextcloud, and more on Omarchy Linux.</b>
</p>

ODrive is a native Omarchy desktop plugin and CLI tool that brings all your cloud storage accounts together under one unified interface. Powered by `rclone` and the Omarchy Quickshell desktop environment, ODrive gives you one-click mounting, storage quota tracking, recent file access, and seamless file manager integration.

---

## ✨ Features

- **Multi-Cloud Integration**: Native support for **Google Drive**, **Microsoft OneDrive**, **Dropbox**, **Nextcloud / ownCloud**, **Box**, **pCloud**, **Proton Drive**, **WebDAV**, **Amazon S3 / MinIO / R2**, and any custom rclone remote.
- **Full Desktop Application (`FloatingWindow`)**:
  - Wayland floating application window tiled or managed seamlessly by Hyprland.
  - **Drives View**: High-level storage metrics, drive health, quota gauges, and one-click mount switches.
  - **Built-in Cloud File Browser**: Browse and navigate cloud folders directly inside the app with breadcrumb path navigation.
  - **Account Connection Wizard**: Visual provider cards for Google Drive, OneDrive, Dropbox, Nextcloud, Box, pCloud, Proton Drive, S3, and WebDAV.
  - **Activity & Diagnostics**: Real-time mount process tracker and live log viewer.
  - **Preferences & Settings**: Configurable mount point root (`~/Cloud`), VFS cache modes (`full`, `writes`), cache quotas, and login auto-mounts.
- **Omarchy Bar Widget**:
  - Lightweight cloud status glyph in the Omarchy bar with mounted count badge.
  - Color-coded activity indicators (idle, active mount, syncing, error).
  - Rich tooltip with mount status and drive names.
  - Left-click to open the quick popout panel with an instant "Open App" button.
  - Right-click to quick toggle Mount/Unmount All, middle-click to refresh.
- **Robust CLI & Automation**:
  - Full-featured `odrive` command line utility (`odrive status`, `odrive files`, `odrive mount`, `odrive app`).
  - Systemd user service for auto-mounting drives on login.
  - Seamless IPC summoning via `omarchy-shell shell summon ttt.odrive`.

---

## 🚀 Quick Start

### 1. Requirements
- Omarchy Linux (v4.0+ Quattro)
- `rclone` (`sudo pacman -S rclone`)
- `fusermount3` (installed by default)

### 2. Installation

Clone or download to your machine and run the installer:

```bash
cd ~/Projects/ODrive
./install.sh --enable
```

This will:
1. Validate the plugin against the Omarchy manifest schema.
2. Install the plugin into `~/.config/omarchy/plugins/ttt.odrive`.
3. Symlink the CLI tool to `~/.local/bin/odrive`.
4. Register the desktop application launcher.
5. Enable the widget in the right section of your Omarchy bar.

For active development, use symlink mode:
```bash
./install.sh --link --enable
```

To remove:
```bash
./install.sh --uninstall
```

---

## ☁️ Adding Cloud Accounts

### Via the Desktop Panel
1. Click the **Cloud icon** in the Omarchy bar (or press your shortcut).
2. Click **"+ Add Drive"** (or press `a`).
3. A floating terminal will open with the guided provider wizard.
4. Select your provider (**Google Drive**, **OneDrive**, **Dropbox**, etc.).
5. Complete the browser authentication prompt.
6. The drive will immediately appear in your panel and can be mounted with one click!

### Via the Command Line
```bash
# Interactive setup wizard
odrive setup

# Direct provider setup
odrive setup MyDrive drive       # Google Drive
odrive setup WorkOneDrive onedrive # Microsoft OneDrive
odrive setup PersonalDropbox dropbox # Dropbox
odrive setup HomeCloud nextcloud # Nextcloud
```

---

## 🖥️ Desktop Panel Shortcuts

When the ODrive panel is focused:

| Key | Action |
|-----|--------|
| `m` / `M` | Toggle Mount All / Unmount All |
| `r` / `R` | Refresh drive status and quotas |
| `a` / `A` | Add new cloud drive (opens setup wizard) |
| `o` / `O` | Open root cloud directory (`~/Cloud`) |
| `Tab` | Switch to adjacent bar panel |
| `Escape` | Close panel |

---

## 💻 CLI Reference

ODrive includes a command line interface accessible from any terminal:

```bash
# Show status of all configured drives
odrive status
odrive status --json

# List drives in table format
odrive list

# Mount or unmount a specific drive
odrive mount MyDrive
odrive unmount MyDrive

# Mount or unmount all configured drives
odrive mount-all
odrive unmount-all

# Open drive directory in file manager
odrive open MyDrive
odrive open              # opens ~/Cloud

# Summon the desktop panel
odrive gui

# Remove a cloud drive configuration
odrive remove MyDrive
```

---

## ⚙️ Configuration

Settings are saved in `~/.config/odrive/config.json`:

```json
{
  "mount_root": "~/Cloud",
  "vfs_cache_mode": "full",
  "cache_max_size_gb": 10,
  "cache_max_age": "24h",
  "auto_mount_all": true,
  "poll_interval_sec": 30,
  "remotes": {
    "GoogleDrive": {
      "auto_mount": true,
      "custom_mount_path": null
    }
  }
}
```

- **`mount_root`**: Root directory where drives are mounted (default: `~/Cloud`).
- **`vfs_cache_mode`**: rclone VFS cache mode (`off`, `minimal`, `writes`, `full`). Default: `full`.
- **`cache_max_size_gb`**: Maximum local disk space allocated to caching files. Default: `10` GB.
- **`auto_mount_all`**: Automatically mount enabled drives when `odrive auto-mount` runs.

### Auto-Mount on Login (systemd)

To automatically mount your cloud drives upon user login, enable the included systemd service:

```bash
mkdir -p ~/.config/systemd/user
cp systemd/odrive-automount.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now odrive-automount.service
```

---

## 📂 Project Structure

```
ODrive/
├── manifest.json            # Omarchy plugin manifest (schemaVersion 1)
├── install.sh               # Installation & lifecycle manager
├── README.md                # Documentation
├── LICENSE                  # MIT License
├── bin/
│   └── odrive               # CLI executable entry point
├── lib/
│   └── odrive/
│       ├── __init__.py
│       ├── cli.py           # CLI commands & interactive setup wizard
│       ├── config.py        # Settings management & legacy migration
│       ├── manager.py       # Core rclone, mount, unmount & quota engine
│       └── providers.py     # Supported cloud providers & metadata
├── ui/
│   ├── Panel.qml            # Main bar widget and popout panel
│   ├── Service.qml          # Background coordinator & Quickshell process runner
│   ├── DriveRow.qml         # Individual drive row with quota progress bar
│   ├── EmptyState.qml       # Onboarding screen with quick-connect buttons
│   ├── RecentFiles.qml      # Recent cloud files list
│   ├── CloudIcon.qml        # Dynamic cloud glyph component
│   ├── Model.js             # Utility functions & formatting helpers
│   └── qmldir               # QML component registrations
├── assets/
│   ├── icon.svg             # Application vector icon
│   └── odrive.desktop       # Desktop application entry
└── systemd/
    └── odrive-automount.service # User systemd service template
```

---

## 📜 License

MIT License — Copyright (c) 2026 TiniTinyTerminator.

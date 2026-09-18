# ODrive — Unified Cloud Drive Manager for Omarchy

<p align="center">
  <b>Seamlessly mount, monitor, and manage Google Drive, OneDrive, Dropbox, Nextcloud, and more on Omarchy Linux.</b>
</p>

ODrive is a native Omarchy desktop plugin and CLI tool that brings all your cloud storage accounts together under one unified interface. Powered by `rclone` and the Omarchy Quickshell desktop environment, ODrive gives you one-click mounting, storage quota tracking, recent file access, and seamless file manager integration.

---

## ✨ Features

- **Multi-Cloud Integration**: Native support for **Google Drive**, **Microsoft OneDrive**, **Dropbox**, **Nextcloud / ownCloud**, **Box**, **pCloud**, **Proton Drive**, **WebDAV**, **Amazon S3 / MinIO / R2**, and any custom rclone remote.
- **Pure Omarchy Bar Widget**:
  - Compact cloud glyph in the Omarchy bar with real-time mounted drive count badge.
  - Color-coded activity indicators (idle, active mount, syncing, error).
  - Rich tooltip with mount status and drive names.
  - Left-click toggles the full-featured popout panel directly beneath your bar.
  - Right-click quick-toggles Mount All / Unmount All; middle-click refreshes status.
- **Complete In-Panel Management (No Separate App Window Needed)**:
  - **Drive Cards**: Drive status, storage quota gauges, one-click mount/unmount toggle, and file manager launcher (`xdg-open`).
  - **Custom Mount Paths**: Change the mount directory per drive inline (`󰏫` button) or set a global default mount root (`~/Cloud`).
  - **In-Panel GUI Account Setup**: Add new cloud remotes directly through the widget without opening a terminal window. Supports browser-based OAuth for Google Drive, OneDrive, Dropbox, Box, pCloud, and direct credentials for Nextcloud, WebDAV, S3, and Proton Drive.
  - **Settings View**: Toggle auto-mount on login and configure root paths directly from the widget.
- **Robust CLI & Automation**:
  - Full-featured `odrive` command line utility (`odrive status`, `odrive mount`, `odrive set-path`, `odrive add-oauth`).
  - Systemd user service for auto-mounting drives on login.

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
4. Enable the widget in the right section of your Omarchy bar.

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

### Via the Bar Widget GUI (No Terminal Needed!)
1. Click the **Cloud icon** in the Omarchy bar (or press your widget shortcut).
2. Click **"+ Add Drive"** in the toolbar (or press `a`).
3. Select your provider (**Google Drive**, **OneDrive**, **Dropbox**, **Nextcloud**, etc.).
4. Enter a name for the drive and optionally customize its mount path.
5. For Google Drive / OneDrive / Dropbox: click **"Authenticate with Browser"** — your default browser will open to complete standard OAuth approval.
6. For Nextcloud / WebDAV / S3: enter your server URL and credentials directly in the form and click **"Connect & Mount"**.
7. Once confirmed, the drive is configured and immediately available!

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

## 🖥️ Widget Panel Shortcuts

When the ODrive panel is focused:

| Key | Action |
|-----|--------|
| `a` / `A` | Toggle Add Drive view |
| `s` / `S` | Toggle Settings view |
| `m` / `M` | Toggle Mount All / Unmount All |
| `r` / `R` | Refresh drive status and quotas |
| `o` / `O` | Open root cloud directory (`~/Cloud`) |
| `Tab` | Switch to adjacent bar panel |
| `Escape` | Back to Drives list / Close panel |

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
├── manifest.json            # Omarchy plugin manifest (bar-widget)
├── install.sh               # Installation & lifecycle manager
├── README.md                # Documentation
├── LICENSE                  # MIT License
├── bin/
│   └── odrive               # CLI executable entry point
├── lib/
│   └── odrive/
│       ├── __init__.py
│       ├── cli.py           # CLI commands & subcommands
│       ├── config.py        # Settings management & custom mount paths
│       ├── manager.py       # Core rclone, mount, unmount & quota engine
│       └── providers.py     # Supported cloud providers & metadata
├── ui/
│   ├── Panel.qml            # Main bar widget popout panel & multi-view manager
│   ├── Service.qml          # Background coordinator & Quickshell process runner
│   ├── DriveRow.qml         # Drive card with inline mount path editor
│   ├── AddAccountForm.qml   # Responsive in-panel account creation wizard
│   ├── EmptyState.qml       # Onboarding screen with quick-connect buttons
│   ├── RecentFiles.qml      # Recent cloud files list
│   ├── CloudIcon.qml        # Dynamic cloud glyph component
│   ├── Model.js             # Utility functions & formatting helpers
│   └── qmldir               # QML component registrations
├── assets/
│   └── icon.svg             # Application vector icon
└── systemd/
    └── odrive-automount.service # User systemd service template
```

---

## 📜 License

MIT License — Copyright (c) 2026 TiniTinyTerminator.

# ODrive — Unified Cloud Drive Manager for Omarchy

<p align="center">
  <b>Seamlessly mount, monitor, and manage Google Drive, OneDrive, Dropbox, Nextcloud, and more on Omarchy Linux.</b>
</p>

ODrive is a native Omarchy desktop plugin and CLI tool that brings all your cloud storage accounts together under one unified interface. Powered by `rclone` and the Omarchy Quickshell desktop environment, ODrive gives you one-click mounting, storage quota tracking, recent file access, and seamless file manager integration.

---

## ✨ Features

- **Multi-Cloud Integration**: Native support for **Google Drive**, **Microsoft OneDrive**, **Dropbox**, **Nextcloud / ownCloud**, **Box**, **pCloud**, **Proton Drive**, **WebDAV**, **Amazon S3 / MinIO / R2**, and any custom rclone remote.
- **Pure Omarchy Bar Widget**:
  - Compact cloud glyph in the Omarchy bar, coloured by state: **green** all drives mounted, **yellow** some or none mounted, **red** rclone missing or a command failed.
  - The glyph spins while mounting, unmounting or refreshing.
  - Rich tooltip with mount status and drive names.
  - Left-click toggles the full-featured popout panel directly beneath your bar.
  - Right-click quick-toggles Mount All / Unmount All; middle-click refreshes status.
- **Complete In-Panel Management (No Separate App Window Needed)**:
  - **Drive Cards**: Drive status, storage quota gauges, one-click mount/unmount toggle, and file manager launcher (`xdg-open`).
  - **Rename & Custom Mount Paths**: Rename a drive and change its mount directory inline (`󰏫` button), or set a global default mount root (`~/Cloud`).
  - **In-Panel GUI Account Setup**: Add new cloud remotes directly through the widget without opening a terminal window. Supports browser-based OAuth for Google Drive, OneDrive, Dropbox, Box, pCloud, and direct credentials for Nextcloud, WebDAV, S3, and Proton Drive.
  - **Settings View**: Toggle auto-mount on login and configure root paths directly from the widget.
- **Robust CLI & Automation**:
  - Full-featured `odrive` command line utility (`odrive status`, `odrive mount`, `odrive rename`, `odrive set-path`, `odrive add-oauth`).
  - Systemd user service for auto-mounting drives on login.

---

## 🚀 Quick Start

### 1. Requirements
- Omarchy Linux (v4.0+ Quattro)
- `rclone` (`sudo pacman -S rclone`)
- `fusermount3` (installed by default)

### 2. Installation

#### Via Omarchy Plugin Manager (Recommended)
Add and enable directly from git into your Omarchy shell:

```bash
omarchy plugin add https://github.com/TiniTinyTerminator/ODrive.git --enable
```

#### Via Git Checkout
Clone the repository and run the installer:

```bash
git clone https://github.com/TiniTinyTerminator/ODrive.git ~/Projects/ODrive
cd ~/Projects/ODrive
./install.sh
```

- `./install.sh`: Copies plugin files to `~/.config/omarchy/plugins/ttt.odrive`, links CLI to `~/.local/bin/odrive`, and enables the widget on the bar.
- `./install.sh --link`: Symlinks files directly into Omarchy (for active development).
- `./install.sh --uninstall`: Cleanly disables the widget and removes installed files while preserving your cloud accounts and configs.

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

# Rename a drive (unmounts and remounts it if needed)
odrive rename MyDrive WorkDrive
odrive rename MyDrive WorkDrive --mount-path ~/Cloud/Work   # rename and move it
odrive rename MyDrive WorkDrive --mount-path ""             # rename and reset to the default location

# Change only the mount directory
odrive set-path MyDrive ~/Cloud/Work

# Remove a cloud drive configuration
odrive remove MyDrive          # asks for confirmation
odrive remove MyDrive --yes    # no prompt
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
- **`auto_mount_all`**: Automatically mount enabled drives when `odrive auto-mount` runs. A per-remote `"auto_mount": false` (or `true`) under `remotes.<name>` overrides it.

### Auto-Mount on Login

The bar widget runs `odrive auto-mount --once` when the shell starts, so drives are mounted on login with no extra setup. `--once` records a marker in `$XDG_RUNTIME_DIR`, so shell reloads later in the same session don't remount drives you unmounted by hand.

To mount drives before the shell starts, you can also enable the included systemd service (it uses the same marker, so the two don't conflict):

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
├── install.sh               # Native installer script (copy, link, uninstall)
├── README.md                # Documentation & usage guide
├── LICENSE                  # MIT License
├── bin/
│   └── odrive               # CLI executable entry point
├── lib/
│   └── odrive/
│       ├── __init__.py      # Package definition & version (1.0.0)
│       ├── cli.py           # CLI subcommands & table formatting
│       ├── config.py        # Settings management & custom mount paths
│       ├── manager.py       # Core rclone, mount, unmount & quota engine
│       └── providers.py     # Supported cloud providers & metadata
├── ui/
│   ├── Panel.qml            # Main bar widget popout panel & multi-view manager
│   ├── Service.qml          # Background coordinator & Quickshell process runner
│   ├── DriveRow.qml         # Drive card with inline mount path editor & quota bar
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

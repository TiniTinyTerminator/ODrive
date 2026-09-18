.pragma library

// Model.js: Formatters and helpers for ODrive

function formatBytes(bytes) {
  var b = Number(bytes || 0)
  if (b <= 0 || !isFinite(b)) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB", "PB"]
  var idx = 0
  while (b >= 1024.0 && idx < units.length - 1) {
    b /= 1024.0
    idx++
  }
  return b.toFixed(1) + " " + units[idx]
}

function formatRelativeTime(ts) {
  var now = Math.floor(Date.now() / 1000)
  var diff = Math.max(0, now - Number(ts || 0))
  if (diff < 60) return "just now"
  var mins = Math.floor(diff / 60)
  if (mins < 60) return mins + "m ago"
  var hours = Math.floor(mins / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 30) return days + "d ago"
  return Math.floor(days / 30) + "mo ago"
}

function parseStatus(raw) {
  if (!raw || typeof raw !== "string") {
    return { ok: false, lastError: "Empty response from odrive backend" }
  }
  try {
    var parsed = JSON.parse(raw.trim())
    if (parsed && typeof parsed === "object") {
      parsed.ok = true
      return parsed
    }
  } catch (e) {
    return { ok: false, lastError: "Failed to parse odrive status: " + e }
  }
  return { ok: false, lastError: "Invalid status object" }
}

function providerIcon(providerId) {
  var id = String(providerId || "").toLowerCase()
  switch (id) {
    case "drive":
      return "󰊭"
    case "onedrive":
      return "󰏊"
    case "dropbox":
      return ""
    case "nextcloud":
      return "󰒋"
    case "box":
      return "󰉉"
    case "pcloud":
    case "protondrive":
      return "󰅟"
    case "webdav":
      return "󰒋"
    case "s3":
      return "󰋊"
    default:
      return "󰅟"
  }
}

var ALL_PROVIDERS = [
  {
    id: "drive",
    name: "Google Drive",
    category: "Cloud Storage",
    glyph: "󰊭",
    color: "#4285F4",
    authType: "oauth",
    description: "Google Drive (Personal, Workspace, Shared Drives)",
    defaultName: "GoogleDrive",
    authTag: "Browser OAuth 2.0"
  },
  {
    id: "onedrive",
    name: "Microsoft OneDrive",
    category: "Cloud Storage",
    glyph: "󰏊",
    color: "#0078D4",
    authType: "oauth",
    description: "Personal, Business, SharePoint accounts",
    defaultName: "OneDrive",
    authTag: "Browser OAuth 2.0"
  },
  {
    id: "dropbox",
    name: "Dropbox",
    category: "Cloud Storage",
    glyph: "",
    color: "#0061FF",
    authType: "oauth",
    description: "Dropbox Personal or Business storage",
    defaultName: "Dropbox",
    authTag: "Browser OAuth 2.0"
  },
  {
    id: "nextcloud",
    name: "Nextcloud / ownCloud",
    category: "Self-Hosted",
    glyph: "󰒋",
    color: "#0082C9",
    authType: "credentials",
    description: "Self-hosted cloud storage via WebDAV",
    defaultName: "Nextcloud",
    authTag: "Server & Password"
  },
  {
    id: "s3",
    name: "Amazon S3 / MinIO",
    category: "Object Storage",
    glyph: "󰋊",
    color: "#FF9900",
    authType: "s3",
    description: "AWS S3, MinIO, Cloudflare R2, Wasabi, B2",
    defaultName: "CloudStorage",
    authTag: "Access Key & Secret"
  },
  {
    id: "box",
    name: "Box",
    category: "Enterprise Cloud",
    glyph: "󰉉",
    color: "#0061D5",
    authType: "oauth",
    description: "Box Enterprise and Personal cloud storage",
    defaultName: "Box",
    authTag: "Browser OAuth 2.0"
  },
  {
    id: "pcloud",
    name: "pCloud",
    category: "Encrypted Cloud",
    glyph: "󰅟",
    color: "#14BF96",
    authType: "oauth",
    description: "Secure European cloud storage",
    defaultName: "pCloud",
    authTag: "Browser OAuth 2.0"
  },
  {
    id: "protondrive",
    name: "Proton Drive",
    category: "Encrypted Cloud",
    glyph: "󰅟",
    color: "#6D4AFF",
    authType: "protondrive",
    description: "End-to-end encrypted Swiss cloud storage",
    defaultName: "ProtonDrive",
    authTag: "Proton Login"
  },
  {
    id: "webdav",
    name: "Generic WebDAV",
    category: "Standard Protocol",
    glyph: "󰒋",
    color: "#7E57C2",
    authType: "webdav",
    description: "Fastmail, Mailbox.org, custom WebDAV servers",
    defaultName: "WebDAV",
    authTag: "URL & Login"
  }
]

function getProvider(providerId) {
  var id = String(providerId || "").toLowerCase()
  for (var i = 0; i < ALL_PROVIDERS.length; i++) {
    if (ALL_PROVIDERS[i].id === id) return ALL_PROVIDERS[i]
  }
  return ALL_PROVIDERS[0]
}


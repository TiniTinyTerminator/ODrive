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
      return "󰏲"
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

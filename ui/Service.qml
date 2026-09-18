import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property string pluginPath: ""
  readonly property string odriveCli: {
    if (pluginPath !== "") return pluginPath + "/bin/odrive"
    var localBin = Quickshell.env("HOME") + "/.local/bin/odrive"
    return localBin
  }

  property bool installed: false
  property string version: ""
  property string mountRoot: "~/Cloud"
  property int totalDrives: 0
  property int mountedDrives: 0
  property bool allMounted: false
  property var drives: []
  property var recentFiles: []

  property bool refreshing: false
  property bool actionBusy: false
  property string lastAction: ""
  property string lastError: ""

  readonly property int refreshIntervalSec: {
    var v = settings ? settings["refreshIntervalSec"] : undefined
    var n = parseInt(String(v !== undefined ? v : 30), 10)
    return isFinite(n) ? Math.max(10, Math.min(600, n)) : 30
  }

  // Pending optimistic states: remote_name -> true (mounting) or false (unmounting)
  property var _pendingMounts: ({})

  function refresh() {
    if (statusProc.running) return
    refreshing = true
    statusProc.running = true
  }

  function applyStatus(raw) {
    refreshing = false
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      lastError = parsed.lastError || "Failed to parse ODrive status"
      return
    }

    installed = parsed.installed === true
    version = String(parsed.version || "")
    mountRoot = String(parsed.mountRoot || "~/Cloud")
    totalDrives = Number(parsed.totalDrives || 0)
    mountedDrives = Number(parsed.mountedDrives || 0)
    allMounted = parsed.allMounted === true
    recentFiles = parsed.recentFiles || []
    if (parsed.vfsCacheMode) vfsCacheMode = String(parsed.vfsCacheMode)
    if (parsed.cacheMaxSizeGb !== undefined) cacheMaxSizeGb = Number(parsed.cacheMaxSizeGb)
    if (parsed.cacheMaxAge) cacheMaxAge = String(parsed.cacheMaxAge)
    if (parsed.autoMountAll !== undefined) autoMountAll = parsed.autoMountAll === true
    if (parsed.pollIntervalSec !== undefined) pollIntervalSec = Number(parsed.pollIntervalSec)
    lastError = ""

    // Apply drives with pending optimistic overrides cleared if reality caught up
    var rawDrives = parsed.drives || []
    var newDrives = []
    for (var i = 0; i < rawDrives.length; i++) {
      var d = rawDrives[i]
      if (root._pendingMounts[d.name] !== undefined) {
        if (d.mounted === root._pendingMounts[d.name]) {
          delete root._pendingMounts[d.name]
        } else {
          d.mounted = root._pendingMounts[d.name]
        }
      }
      newDrives.push(d)
    }
    drives = newDrives
  }

  function toggleMount(remoteName, currentMounted) {
    if (actionBusy) return
    var targetState = !currentMounted
    root._pendingMounts[remoteName] = targetState

    // Trigger optimistic UI update
    var updated = []
    for (var i = 0; i < drives.length; i++) {
      var d = drives[i]
      if (d.name === remoteName) d.mounted = targetState
      updated.push(d)
    }
    drives = updated

    lastAction = targetState ? ("Mounting " + remoteName + "…") : ("Unmounting " + remoteName + "…")
    runAction([odriveCli, targetState ? "mount" : "unmount", remoteName])
  }

  function mountAll() {
    if (actionBusy) return
    lastAction = "Mounting all cloud drives…"
    runAction([odriveCli, "mount-all"])
  }

  function unmountAll() {
    if (actionBusy) return
    lastAction = "Unmounting all cloud drives…"
    runAction([odriveCli, "unmount-all"])
  }

  function openFolder(remoteName) {
    var args = [odriveCli, "open"]
    if (remoteName && remoteName !== "") args.push(remoteName)
    Quickshell.execDetached(args)
  }

  function launchSetup(providerId) {
    var args = ["xdg-terminal-exec", "--app-id=TUI.float", "-e", odriveCli, "setup"]
    if (providerId && providerId !== "") {
      args.push("")
      args.push(providerId)
    }
    Quickshell.execDetached(args)
  }

  function openFile(filePath) {
    if (!filePath || filePath === "") return
    Quickshell.execDetached(["xdg-open", filePath])
  }

  function runAction(commandList) {
    actionBusy = true
    actionProc.command = commandList
    actionProc.running = true
  }

  property string vfsCacheMode: "full"
  property int cacheMaxSizeGb: 10
  property string cacheMaxAge: "24h"
  property bool autoMountAll: true
  property int pollIntervalSec: 30

  // File browser state
  property string browserRemote: ""
  property string browserPath: ""
  property var browserFiles: []
  property bool browserLoading: false
  property string currentLog: ""
  property bool logLoading: false

  function setBrowserPath(remote, path) {
    browserRemote = remote
    browserPath = path || ""
    browserLoading = true
    browserFiles = []
    filesProc.command = [odriveCli, "files", remote, browserPath]
    filesProc.running = true
  }

  function loadLog(remote) {
    logLoading = true
    currentLog = "Loading log…"
    logProc.command = [odriveCli, "log", remote]
    logProc.running = true
  }

  function removeRemote(remoteName) {
    if (actionBusy) return
    lastAction = "Removing " + remoteName + "…"
    runAction([odriveCli, "remove", remoteName])
  }

  function updateConfig(key, value) {
    runAction([odriveCli, "config", key, String(value)])
  }

  Process {
    id: statusProc
    command: [root.odriveCli, "status", "--json"]
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.applyStatus(this.text)
      }
    }
    onExited: {
      root.refreshing = false
    }
  }

  Process {
    id: filesProc
    command: []
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.browserLoading = false
        try {
          var items = JSON.parse(this.text.trim())
          if (Array.isArray(items)) root.browserFiles = items
          else root.browserFiles = []
        } catch (e) {
          root.browserFiles = []
        }
      }
    }
    onExited: {
      root.browserLoading = false
    }
  }

  Process {
    id: logProc
    command: []
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        root.logLoading = false
        root.currentLog = this.text.trim() || "No logs available."
      }
    }
    onExited: {
      root.logLoading = false
    }
  }

  Process {
    id: actionProc
    command: []
    running: false
    stdout: StdioCollector {
      onStreamFinished: {
        var out = this.text.trim()
        if (out.indexOf("✗") !== -1 || out.indexOf("Failed") !== -1) {
          root.lastError = out
        }
      }
    }
    onExited: {
      root.actionBusy = false
      root.lastAction = ""
      pollTimer.restart()
      root.refresh()
    }
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    root.refresh()
  }
}

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
  // Whether lastError came from a status refresh (cleared by the next good refresh) or from an action
  property bool _statusError: false
  // Something is wrong right now: drives the bar's error colour, cleared by the next good refresh
  property bool actionFailed: false

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
      _statusError = true
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
    if (_statusError) {
      lastError = ""
      _statusError = false
    }
    actionFailed = false

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
    runAction([odriveCli, targetState ? "mount" : "unmount", remoteName], remoteName)
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

  property bool authBusy: false
  property bool authWaiting: false
  property string authError: ""
  property bool authSuccess: false
  property string authSuccessMessage: ""
  signal accountCreated(string remoteName)

  function launchSetup(providerId) {
    // Never launch terminal! Directly summon ODrive GUI window on the "add" view!
    Quickshell.execDetached([
      "omarchy-shell", "shell", "summon", "ttt.odrive",
      JSON.stringify({ view: "add", provider: providerId || "" })
    ])
  }

  function addOAuth(remoteName, providerId, clientId, clientSecret, mountPath, mountAfter) {
    if (authBusy) return
    authBusy = true
    authWaiting = true
    authError = ""
    authSuccess = false
    authSuccessMessage = ""

    var args = [odriveCli, "add-oauth", remoteName, providerId]
    if (clientId && clientId !== "") {
      args.push("--client-id")
      args.push(clientId)
    }
    var stdinPayload = ""
    if (clientSecret && clientSecret !== "") {
      args.push("--client-secret-stdin")
      stdinPayload = clientSecret + "\n"
    }
    if (mountPath && mountPath !== "") {
      args.push("--mount-path")
      args.push(mountPath)
    }
    if (mountAfter) {
      args.push("--mount")
    }
    _startAuth(args, stdinPayload)
  }

  // Secrets reach the CLI on stdin only: argv is readable by every local user via /proc.
  property string _authStdin: ""

  function _startAuth(args, stdinPayload) {
    _authStdin = stdinPayload
    authProc.stdinEnabled = true
    authProc.command = args
    authProc.running = true
  }

  function cancelAuth() {
    if (authProc.running) {
      authProc.running = false
    }
    authBusy = false
    authWaiting = false
    authError = "Authorization cancelled."
  }

  function addCredentials(remoteName, providerId, optionsDict, mountPath, mountAfter) {
    if (authBusy) return
    authBusy = true
    authWaiting = false
    authError = ""
    authSuccess = false
    authSuccessMessage = ""

    var args = [odriveCli, "add-credentials", remoteName, providerId]
    if (mountPath && mountPath !== "") {
      args.push("--mount-path")
      args.push(mountPath)
    }
    if (mountAfter) {
      args.push("--mount")
    }
    _startAuth(args, JSON.stringify(optionsDict))
  }

  function renameRemote(remoteName, newName, newPath) {
    if (actionBusy) return
    lastAction = "Renaming " + remoteName + " to " + newName + "…"
    var args = [odriveCli, "rename", remoteName, newName]
    if (newPath !== undefined && newPath !== null) {
      args.push("--mount-path")
      args.push(newPath)
    }
    runAction(args, remoteName)
  }

  function setRemoteMountPath(remoteName, newPath) {
    if (actionBusy) return
    lastAction = "Updating location for " + remoteName + "…"
    runAction([odriveCli, "set-path", remoteName, newPath])
  }

  function setMountRoot(newRoot) {
    if (actionBusy) return
    lastAction = "Updating mount root…"
    runAction([odriveCli, "set-root", newRoot])
  }

  function openFile(filePath) {
    if (!filePath || filePath === "") return
    Quickshell.execDetached(["xdg-open", filePath])
  }

  // Remote whose optimistic mount state belongs to the running action
  property string _actionRemote: ""
  property var _actionQueue: []

  function runAction(commandList, remoteName) {
    if (actionProc.running) {
      _actionQueue.push({ command: commandList, remote: remoteName || "" })
      return
    }
    actionBusy = true
    _actionRemote = remoteName || ""
    actionProc.command = commandList
    actionProc.running = true
  }

  function _cleanOutput(text) {
    return String(text || "").replace(/\x1b\[[0-9;]*m/g, "").trim()
  }

  function _finishAction(exitCode) {
    var out = _cleanOutput(actionOut.text)
    var err = _cleanOutput(actionErr.text)
    var jsonMessage = ""
    try {
      var res = JSON.parse(out)
      if (res && res.ok === false) jsonMessage = String(res.message || res.error || "")
    } catch (e) {}

    if (exitCode !== 0 || jsonMessage !== "") {
      lastError = jsonMessage || err || out || "Command failed"
      _statusError = false
      actionFailed = true
    } else if (!_statusError) {
      lastError = ""
      actionFailed = false
    }

    // Drop the optimistic state either way; the refresh below shows what really happened
    if (_actionRemote !== "") delete _pendingMounts[_actionRemote]
    _actionRemote = ""

    if (_actionQueue.length > 0) {
      var next = _actionQueue.shift()
      runAction(next.command, next.remote)
      return
    }

    actionBusy = false
    lastAction = ""
    pollTimer.restart()
    refresh()
  }

  property string vfsCacheMode: "full"
  property int cacheMaxSizeGb: 10
  property string cacheMaxAge: "24h"
  property bool autoMountAll: true
  property int pollIntervalSec: 30
  property string currentLog: ""
  property bool logLoading: false

  function loadLog(remote) {
    logLoading = true
    currentLog = "Loading log…"
    logProc.command = [odriveCli, "log", remote]
    logProc.running = true
  }

  function removeRemote(remoteName) {
    if (actionBusy) return
    lastAction = "Removing " + remoteName + "…"
    runAction([odriveCli, "remove", "--yes", remoteName])
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
    stdout: StdioCollector { id: actionOut }
    stderr: StdioCollector { id: actionErr }
    onExited: function(exitCode, exitStatus) {
      // Let the collectors deliver their final text before reading it
      Qt.callLater(function() { root._finishAction(exitCode) })
    }
  }

  Process {
    id: authProc
    command: []
    running: false
    stdinEnabled: true
    onStarted: {
      if (root._authStdin !== "") write(root._authStdin)
      root._authStdin = ""
      // Closing stdin sends EOF, so the CLI never waits for more input
      stdinEnabled = false
    }
    stdout: StdioCollector {
      onStreamFinished: {
        var raw = this.text.trim()
        if (!raw) return
        try {
          var res = JSON.parse(raw)
          if (res.ok) {
            root.authSuccess = true
            root.authSuccessMessage = res.message || ("Successfully connected " + res.remote)
            root.authError = ""
            root.accountCreated(res.remote)
            root.refresh()
          } else {
            root.authError = res.error || "Failed to configure remote"
          }
        } catch (e) {
          if (raw.indexOf("✓") !== -1 || raw.indexOf("Successfully") !== -1) {
            root.authSuccess = true
            root.authSuccessMessage = raw
            root.refresh()
          } else {
            root.authError = raw || "Setup failed"
          }
        }
      }
    }
    stderr: StdioCollector {
      onStreamFinished: {
        var err = this.text.trim()
        if (err && !root.authSuccess && root.authError === "") {
          root.authError = err
        }
      }
    }
    onExited: {
      root._authStdin = ""
      root.authBusy = false
      root.authWaiting = false
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
    // Mounts on first shell start of the login session; the CLI skips it on later reloads
    runAction([odriveCli, "auto-mount", "--once"])
  }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "ttt.odrive"
  ipcTarget: "ttt.odrive"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool hasDrives: service.totalDrives > 0
  readonly property bool hasMounted: service.mountedDrives > 0
  readonly property color barIconColor: hasMounted ? barForeground : Qt.darker(barForeground, 1.6)

  // Subtitle in hero
  readonly property string heroMeta: {
    if (!service.installed) return "rclone not installed"
    if (!hasDrives) return "No drives configured"
    if (service.allMounted) return "All " + service.totalDrives + " drives mounted"
    if (hasMounted) return service.mountedDrives + " of " + service.totalDrives + " drives mounted"
    return "All drives unmounted"
  }

  // Bar tooltip
  readonly property string barTooltipText: {
    if (!service.installed) return "ODrive: rclone not installed"
    if (!hasDrives) return "ODrive: Click to configure cloud drives"
    var names = []
    for (var i = 0; i < service.drives.length; i++) {
      if (service.drives[i].mounted) names.push(service.drives[i].name)
    }
    if (names.length > 0) {
      return "ODrive: " + service.mountedDrives + "/" + service.totalDrives + " mounted (" + names.join(", ") + ")"
    }
    return "ODrive: " + service.totalDrives + " drives configured (none mounted)"
  }

  function openAppWindow(payload) {
    root.close()
    var target = payload || {}
    if (bar && bar.shell && typeof bar.shell.summon === "function") {
      bar.shell.summon("ttt.odrive", JSON.stringify(target))
      return
    }
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "ttt.odrive", JSON.stringify(target)])
  }

  // Derive size from content
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    service.refresh()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: service
    settings: root.settings
    pluginPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/ttt.odrive"
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { service.refresh(); return "ok" }
    function mountAll(): string { service.mountAll(); return "ok" }
    function unmountAll(): string { service.unmountAll(); return "ok" }
    function status(): string {
      return JSON.stringify({
        installed: service.installed,
        totalDrives: service.totalDrives,
        mountedDrives: service.mountedDrives,
        drives: service.drives
      })
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.barTooltipText

    iconComponent: Component {
      Item {
        anchors.fill: parent

        CloudIcon {
          anchors.centerIn: parent
          iconSize: Style.bar.iconFont
          color: root.barIconColor
          fontFamily: root.fontFamily
          active: root.hasMounted
          busy: service.actionBusy || service.refreshing
        }

        // Mounted drive count badge
        Rectangle {
          visible: service.totalDrives > 1 && root.hasMounted
          anchors {
            right: parent.right
            bottom: parent.bottom
            margins: -Style.space(2)
          }
          width: Math.max(badgeText.implicitWidth + Style.space(6), Style.space(14))
          height: Style.space(13)
          radius: height / 2
          color: Color.accent

          Text {
            id: badgeText
            anchors.centerIn: parent
            text: String(service.mountedDrives)
            color: Color.background
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption - Style.space(3)
            font.bold: true
          }
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (service.allMounted) service.unmountAll()
        else service.mountAll()
      } else if (buttonCode === Qt.MiddleButton) {
        service.refresh()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(580))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") service.refresh()
        else if (t === "m" || t === "M") {
          if (service.allMounted) service.unmountAll()
          else service.mountAll()
        }
        else if (t === "a" || t === "A") root.openAppWindow({ view: "add" })
        else if (t === "o" || t === "O") service.openFolder("")
        else if (t === "w" || t === "W") root.openAppWindow({})
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(10)

          // Hero Header
          PanelHero {
            id: hero
            width: parent.width
            title: "Cloud Drives"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              CloudIcon {
                iconSize: Style.font.display
                color: root.hasMounted ? Color.accent : root.foreground
                active: root.hasMounted
                busy: service.actionBusy || service.refreshing
              }
            }

            trailingControl: Component {
              ToggleSwitch {
                visible: root.hasDrives
                checked: service.allMounted
                busy: service.actionBusy
                foreground: hero.foreground
                onToggled: {
                  if (service.allMounted) service.unmountAll()
                  else service.mountAll()
                }

                PanelToolTip {
                  visible: containsMouse
                  text: service.allMounted ? "Unmount all drives" : "Mount all drives"
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          // Action Status / Error banner
          Text {
            visible: service.lastAction !== "" || service.lastError !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: service.lastAction !== "" ? service.lastAction : service.lastError
            color: service.lastError !== "" && service.lastAction === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Toolbar Buttons
          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              iconText: "󰐕"
              text: "Add Drive"
              fontFamily: root.fontFamily
              foreground: root.foreground
              bordered: true
              onClicked: service.launchSetup("")
            }

            Button {
              iconText: "󰉋"
              text: "Cloud Folder"
              fontFamily: root.fontFamily
              foreground: root.foreground
              bordered: true
              onClicked: service.openFolder("")
            }

            Button {
              iconText: "󰌹"
              text: "Open App"
              fontFamily: root.fontFamily
              foreground: root.foreground
              bordered: true
              onClicked: root.openAppWindow({})
            }

            Item { Layout.fillWidth: true }

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh status & quotas (R)"
              foreground: root.foreground
              hoverColor: Color.accent
              onClicked: service.refresh()
            }
          }

          // Section Header for Configured Drives
          PanelSectionHeader {
            visible: root.hasDrives
            text: "Configured Drives"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          // List of Configured Drives
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.hasDrives

            Repeater {
              model: service.drives

              DriveRow {
                width: parent.width
                drive: modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
                onToggleMount: service.toggleMount(modelData.name, modelData.mounted)
                onOpenFolder: service.openFolder(modelData.name)
              }
            }
          }

          // Empty State if no drives configured
          EmptyState {
            visible: !root.hasDrives
            width: parent.width
            foreground: root.foreground
            fontFamily: root.fontFamily
            onAddProvider: function(provId) { root.openAppWindow({ view: "add", provider: provId || "" }) }
          }

          // Recent Files
          RecentFiles {
            width: parent.width
            files: service.recentFiles
            foreground: root.foreground
            fontFamily: root.fontFamily
            onFileSelected: function(path) { service.openFile(path) }
          }
        }
      }
    }
  }
}

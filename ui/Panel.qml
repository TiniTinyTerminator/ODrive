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

  property string currentView: "drives" // "drives" | "add" | "settings"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color background: bar ? bar.background : Color.background
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property bool hasDrives: service.totalDrives > 0
  readonly property bool hasMounted: service.mountedDrives > 0

  // Bar status at a glance: "online" every drive mounted, "offline" some or none mounted,
  // "error" rclone missing or the last command failed. The theme has no green/amber, so
  // these are muted tones picked to sit next to Color.urgent.
  readonly property color statusOnline: "#6fa96f"
  readonly property color statusOffline: "#c9a24a"
  readonly property string statusState: {
    if (!service.installed || service.actionFailed) return "error"
    if (hasDrives && service.allMounted) return "online"
    return "offline"
  }
  readonly property color statusColor: {
    if (statusState === "error") return root.urgent
    if (statusState === "online") return statusOnline
    return statusOffline
  }
  readonly property color barIconColor: statusColor

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
    if (service.actionFailed && service.lastError !== "") return "ODrive: " + service.lastError
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

  function revealDrive(index) {
    Qt.callLater(function() { drivesList.positionViewAtIndex(index, ListView.Contain) })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    service.refresh()
    if (panelFlick) panelFlick.contentY = 0
    if (drivesList) drivesList.contentY = 0
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
    function add(): void {
      root.open()
      root.currentView = "add"
    }
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
          active: root.statusState === "online"
          busy: service.actionBusy || service.refreshing
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
    contentHeight: panel.fittedContentHeight(
      root.currentView === "drives" ? drivesView.implicitHeight : mainContentCol.implicitHeight,
      Style.space(580))

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
        else if (t === "a" || t === "A") {
          root.currentView = root.currentView === "add" ? "drives" : "add"
        }
        else if (t === "s" || t === "S") {
          root.currentView = root.currentView === "settings" ? "drives" : "settings"
        }
        else if (t === "o" || t === "O") service.openFolder("")
      }

      // ==================================================================
      // VIEW 1: DRIVES (DEFAULT MAIN VIEW)
      // Header stays put; the drive list takes the remaining height and
      // scrolls on its own, so any number of drives fits on screen.
      // ==================================================================
      ColumnLayout {
        id: drivesView
        anchors.fill: parent
        visible: root.currentView === "drives"
        spacing: Style.space(10)

        // Hero Header
        PanelHero {
          id: hero
          Layout.fillWidth: true
          title: "Cloud Drives"
          meta: root.heroMeta
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            CloudIcon {
              iconSize: Style.font.display
              color: root.statusColor
              active: root.statusState === "online"
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
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: service.lastAction !== "" ? service.lastAction : service.lastError
          color: service.lastError !== "" && service.lastAction === "" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }

        // Toolbar Buttons
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Button {
            iconText: "󰐕"
            text: "Add Drive"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: true
            onClicked: { root.currentView = "add" }
          }

          Button {
            iconText: "󰉋"
            text: "Folder"
            tooltipText: "Open mount directory (" + service.mountRoot + ")"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: true
            onClicked: service.openFolder("")
          }

          Button {
            iconText: "󰒓"
            text: "Settings"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: true
            onClicked: { root.currentView = "settings" }
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
          Layout.fillWidth: true
          text: "Configured Drives"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }

        // List of Configured Drives: grows to fit, then scrolls within the space left
        ListView {
          id: drivesList
          visible: root.hasDrives
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.preferredHeight: contentHeight
          Layout.maximumHeight: contentHeight
          Layout.minimumHeight: Math.min(contentHeight, Style.space(90))
          spacing: Style.space(6)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // Bound by index: each refresh assigns a new drives array, and a model of the
          // array itself would rebuild every row, resetting the scroll and open editors
          model: service.drives.length

          delegate: DriveRow {
            id: driveRow
            required property int index
            readonly property var entry: service.drives[index] || ({})
            width: ListView.view.width
            drive: entry
            foreground: root.foreground
            fontFamily: root.fontFamily
            mountRoot: service.mountRoot
            onToggleMount: service.toggleMount(entry.name, entry.mounted)
            onOpenFolder: service.openFolder(entry.name)
            onUpdateMountPath: function(newPath) {
              service.setRemoteMountPath(entry.name, newPath)
            }
            onRenameDrive: function(newName, newPath) {
              service.renameRemote(entry.name, newName, newPath)
            }
            onRemoveDrive: service.removeRemote(entry.name)
            // Keep an expanded editor or remove prompt in view
            onEditingLocationChanged: if (editingLocation) root.revealDrive(index)
            onConfirmingRemoveChanged: if (confirmingRemove) root.revealDrive(index)
          }
        }

        // Empty State if no drives configured
        EmptyState {
          visible: !root.hasDrives
          Layout.fillWidth: true
          foreground: root.foreground
          fontFamily: root.fontFamily
          onAddProvider: function(provId) {
            root.currentView = "add"
            addForm.selectProvider(provId)
          }
        }

        // Recent Files dropdown
        RecentFiles {
          Layout.fillWidth: true
          files: service.recentFiles
          foreground: root.foreground
          fontFamily: root.fontFamily
          onFileSelected: function(path) { service.openFile(path) }
        }

        // Takes any spare height so the sections above stay packed at the top
        Item {
          Layout.fillHeight: true
          Layout.preferredHeight: 0
        }
      }

      // Add and Settings views: long forms that scroll as a whole
      Flickable {
        id: panelFlick
        anchors.fill: parent
        visible: root.currentView !== "drives"
        contentWidth: width
        contentHeight: mainContentCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

        Column {
          id: mainContentCol
          width: panelFlick.width
          spacing: Style.space(10)

          // ==================================================================
          // VIEW 2: ADD ACCOUNT (IN-WIDGET GUI SETUP)
          // ==================================================================
          Column {
            visible: root.currentView === "add"
            width: parent.width

            AddAccountForm {
              id: addForm
              width: parent.width
              backend: service
              foreground: root.foreground
              background: root.background
              accent: root.accent
              urgent: root.urgent
              dim: root.dim
              fontFamily: root.fontFamily
              onAccountAdded: function(name) {
                root.currentView = "drives"
                service.refresh()
              }
              onCancelled: {
                root.currentView = "drives"
              }
            }
          }

          // ==================================================================
          // VIEW 3: SETTINGS (MOUNT ROOT & CONFIGURATION)
          // ==================================================================
          Column {
            visible: root.currentView === "settings"
            width: parent.width
            spacing: Style.space(12)

            RowLayout {
              width: parent.width
              spacing: Style.space(8)

              Button {
                iconText: "󰁝"
                text: "Back to Drives"
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                foreground: root.foreground
                bordered: true
                onClicked: { root.currentView = "drives" }
              }

              Text {
                Layout.fillWidth: true
                text: "ODrive Settings"
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                color: root.foreground
              }
            }

            BorderSurface {
              width: parent.width
              implicitHeight: cfgCol.implicitHeight + Style.space(20)
              radius: Style.cornerRadius
              color: Qt.rgba(1, 1, 1, 0.03)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

              ColumnLayout {
                id: cfgCol
                anchors {
                  fill: parent
                  margins: Style.space(12)
                }
                spacing: Style.space(12)

                // Global Mount Root Setting
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(4)

                  Text {
                    text: "Default Cloud Mount Root:"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: root.foreground
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)

                    TextField {
                      id: rootDirInput
                      Layout.fillWidth: true
                      text: service.mountRoot
                      placeholderText: "~/Cloud"
                    }

                    Button {
                      text: "Save"
                      iconText: "󰄬"
                      fontFamily: root.fontFamily
                      fontSize: Style.font.caption
                      foreground: root.foreground
                      bordered: true
                      onClicked: {
                        service.setMountRoot(rootDirInput.text.trim())
                      }
                    }
                  }

                  Text {
                    text: "Directory where new cloud drives are attached by default"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption - Style.space(2)
                    color: root.dim
                  }
                }

                // Auto-mount switch
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(8)

                  Column {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                      text: "Auto-mount all drives on login"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                      color: root.foreground
                    }

                    Text {
                      text: "Automatically mount all drives when Omarchy shell boots"
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption - Style.space(2)
                      color: root.dim
                    }
                  }

                  ToggleSwitch {
                    checked: service.autoMountAll
                    foreground: root.foreground
                    onToggled: service.updateConfig("auto_mount_all", !service.autoMountAll)
                  }
                }

                // Cache & Engine Info
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(3)

                  Text {
                    text: "Engine & Cache Configuration"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: root.foreground
                  }

                  Text {
                    text: "VFS Cache: " + service.vfsCacheMode.toUpperCase() + " (" + service.cacheMaxSizeGb + " GB limit, " + service.cacheMaxAge + " expiry)"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption - Style.space(2)
                    color: root.dim
                  }

                  Text {
                    text: "Status: " + (service.installed ? (service.version || "rclone ready") : "rclone missing")
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption - Style.space(2)
                    color: service.installed ? Color.accent : root.urgent
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}

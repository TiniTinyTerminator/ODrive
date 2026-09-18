import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string activeView: "drives" // drives | files | add | activity | settings
  property string activeRemote: ""

  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: Style.font.family

  function open(payloadJson) {
    root.opened = true
    backend.refresh()
    if (payloadJson) {
      try {
        var p = JSON.parse(payloadJson)
        if (p.view) root.activeView = p.view
        if (p.remote) root.activeRemote = p.remote
        if (p.provider) addForm.selectProvider(p.provider)
      } catch (e) {}
    }
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function toggle() {
    root.opened ? root.close() : root.open("{}")
  }

  Service {
    id: backend
    pluginPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/ttt.odrive"
    onDrivesChanged: {
      if (root.activeRemote === "" && backend.drives.length > 0) {
        root.activeRemote = backend.drives[0].name
      }
    }
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "ODrive — Cloud Storage"
    color: root.background
    implicitWidth: Style.space(1080)
    implicitHeight: Style.space(700)
    minimumSize: Qt.size(Style.space(740), Style.space(460))

    onVisibleChanged: {
      if (!visible && root.opened) root.opened = false
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()

      RowLayout {
        anchors.fill: parent
        spacing: 0

        // ====================================================================
        // LEFT NAVIGATION RAIL
        // ====================================================================
        Rectangle {
          Layout.fillHeight: true
          Layout.preferredWidth: Style.space(200)
          color: Qt.darker(root.background, 1.15)

          Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: Qt.rgba(1, 1, 1, 0.08)
          }

          ColumnLayout {
            anchors {
              fill: parent
              margins: Style.space(14)
            }
            spacing: Style.space(8)

            // Brand Header
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(10)

              CloudIcon {
                iconSize: Style.font.display
                color: root.accent
                active: backend.mountedDrives > 0
                busy: backend.actionBusy || backend.refreshing
              }

              Column {
                Layout.fillWidth: true
                spacing: 0

                Text {
                  text: "ODrive"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  color: root.foreground
                }

                Text {
                  text: "Cloud Manager"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              height: 1
              color: Qt.rgba(1, 1, 1, 0.06)
              Layout.topMargin: Style.space(8)
              Layout.bottomMargin: Style.space(8)
            }

            // Navigation Items
            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(4)

              NavButton {
                glyph: "󰅟"
                label: "Cloud Drives"
                viewId: "drives"
                badgeText: backend.totalDrives > 0 ? (backend.mountedDrives + "/" + backend.totalDrives) : ""
              }

              NavButton {
                glyph: "󰉋"
                label: "File Browser"
                viewId: "files"
                badgeText: ""
              }

              NavButton {
                glyph: "󰐕"
                label: "Add Account"
                viewId: "add"
                badgeText: ""
              }

              NavButton {
                glyph: "󰑐"
                label: "Activity & Logs"
                viewId: "activity"
                badgeText: ""
              }

              NavButton {
                glyph: "󰒓"
                label: "Settings"
                viewId: "settings"
                badgeText: ""
              }
            }

            Item { Layout.fillHeight: true }

            // Bottom Info Card
            Rectangle {
              Layout.fillWidth: true
              implicitHeight: Style.space(64)
              radius: Style.cornerRadius
              color: Qt.rgba(1, 1, 1, 0.04)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.06)

              Column {
                anchors.centerIn: parent
                spacing: Style.space(2)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: backend.installed ? "Engine Ready" : "rclone missing"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  color: backend.installed ? Color.accent : root.urgent
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: backend.version.replace("rclone ", "") || "v1.75+"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption - Style.space(2)
                  color: root.dim
                }
              }
            }
          }
        }

        // ====================================================================
        // RIGHT MAIN CONTENT AREA
        // ====================================================================
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0

          // Top Command Bar
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(56)
            color: root.background

            Rectangle {
              anchors.bottom: parent.bottom
              width: parent.width
              height: 1
              color: Qt.rgba(1, 1, 1, 0.08)
            }

            RowLayout {
              anchors {
                fill: parent
                leftMargin: Style.space(20)
                rightMargin: Style.space(20)
              }
              spacing: Style.space(12)

              Column {
                spacing: 0

                Text {
                  text: {
                    if (root.activeView === "drives") return "Configured Cloud Drives"
                    if (root.activeView === "files") return "Cloud File Browser"
                    if (root.activeView === "add") return "Connect New Cloud Account"
                    if (root.activeView === "activity") return "Mount Activity & Diagnostics"
                    if (root.activeView === "settings") return "ODrive Settings"
                    return "ODrive"
                  }
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  color: root.foreground
                }

                Text {
                  text: backend.lastAction !== "" ? backend.lastAction : (backend.mountedDrives + " of " + backend.totalDrives + " drives mounted")
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  color: backend.lastAction !== "" ? Color.accent : root.dim
                }
              }

              Item { Layout.fillWidth: true }

              // Quick Actions
              Button {
                iconText: "󰐕"
                text: "Add Drive"
                fontFamily: root.fontFamily
                foreground: root.foreground
                bordered: true
                onClicked: { root.activeView = "add" }
              }

              Button {
                iconText: backend.allMounted ? "󰅛" : "󰄬"
                text: backend.allMounted ? "Unmount All" : "Mount All"
                fontFamily: root.fontFamily
                foreground: root.foreground
                bordered: true
                onClicked: {
                  if (backend.allMounted) backend.unmountAll()
                  else backend.mountAll()
                }
              }

              Button {
                iconText: "󰉋"
                text: "Open ~/Cloud"
                fontFamily: root.fontFamily
                foreground: root.foreground
                bordered: true
                onClicked: backend.openFolder("")
              }

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Refresh status & quotas"
                foreground: root.foreground
                hoverColor: Color.accent
                onClicked: backend.refresh()
              }
            }
          }

          // Main View Content Container
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // ----------------------------------------------------------------
            // 1. DRIVES VIEW
            // ----------------------------------------------------------------
            Flickable {
              id: drivesFlick
              visible: root.activeView === "drives"
              anchors.fill: parent
              contentWidth: width
              contentHeight: drivesContent.implicitHeight + Style.space(40)
              clip: true
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              ColumnLayout {
                id: drivesContent
                anchors {
                  left: parent.left
                  right: parent.right
                  top: parent.top
                  margins: Style.space(20)
                }
                spacing: Style.space(16)

                // Metric Cards Row
                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(12)

                  MetricCard {
                    title: "Active Mounts"
                    value: backend.mountedDrives + " / " + backend.totalDrives
                    subtitle: backend.allMounted ? "All drives attached" : (backend.totalDrives - backend.mountedDrives) + " unmounted"
                    glyph: "󰅠"
                    glyphColor: Color.accent
                  }

                  MetricCard {
                    title: "Cloud Directory"
                    value: "~/Cloud"
                    subtitle: "FUSE mount root"
                    glyph: "󰉋"
                    glyphColor: root.foreground
                  }

                  MetricCard {
                    title: "Cache Mode"
                    value: backend.vfsCacheMode.toUpperCase()
                    subtitle: backend.cacheMaxSizeGb + " GB cache quota"
                    glyph: "󰋊"
                    glyphColor: root.dim
                  }
                }

                // Configured Drives Header
                RowLayout {
                  Layout.fillWidth: true

                  Text {
                    text: "Connected Accounts"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    color: root.foreground
                  }

                  Item { Layout.fillWidth: true }
                }

                // List of Configured Drive Cards
                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(10)
                  visible: backend.totalDrives > 0

                  Repeater {
                    model: backend.drives

                    BorderSurface {
                      id: driveCard
                      Layout.fillWidth: true
                      implicitHeight: cardCol.implicitHeight + Style.space(24)
                      radius: Style.cornerRadius
                      color: Qt.rgba(1, 1, 1, 0.03)
                      borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                      ColumnLayout {
                        id: cardCol
                        anchors {
                          fill: parent
                          margins: Style.space(14)
                        }
                        spacing: Style.space(10)

                        RowLayout {
                          Layout.fillWidth: true
                          spacing: Style.space(12)

                          // Provider Icon
                          Rectangle {
                            implicitWidth: Style.space(42)
                            implicitHeight: Style.space(42)
                            radius: Style.cornerRadius
                            color: modelData.color ? Qt.alpha(modelData.color, 0.15) : Qt.rgba(1, 1, 1, 0.08)

                            Text {
                              anchors.centerIn: parent
                              text: modelData.glyph || "󰅟"
                              color: modelData.color || root.foreground
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.display
                            }
                          }

                          // Title and Path
                          Column {
                            Layout.fillWidth: true
                            spacing: Style.space(2)

                            RowLayout {
                              spacing: Style.space(8)

                              Text {
                                text: modelData.name
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                                color: root.foreground
                              }

                              Text {
                                text: "(" + modelData.provider + ")"
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                color: root.dim
                              }

                              Text {
                                text: modelData.mounted ? "󰄬 Mounted" : "󰅛 Unmounted"
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                color: modelData.mounted ? Color.accent : root.dim
                              }
                            }

                            Text {
                              text: modelData.mounted ? modelData.mountPath : "Click mount switch to attach"
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              color: root.dim
                            }
                          }

                          // Action Buttons
                          Button {
                            iconText: "󰉋"
                            text: "Browse"
                            fontFamily: root.fontFamily
                            foreground: root.foreground
                            bordered: true
                            onClicked: {
                              root.activeRemote = modelData.name
                              root.activeView = "files"
                              backend.setBrowserPath(modelData.name, "")
                            }
                          }

                          Button {
                            visible: modelData.mounted
                            iconText: "󰌹"
                            text: "Open"
                            fontFamily: root.fontFamily
                            foreground: root.foreground
                            bordered: true
                            onClicked: backend.openFolder(modelData.name)
                          }

                          // Mount / Unmount Switch
                          ToggleSwitch {
                            checked: modelData.mounted
                            foreground: root.foreground
                            onToggled: backend.toggleMount(modelData.name, modelData.mounted)
                          }
                        }

                        // Storage Quota Progress Bar
                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: Style.space(4)
                          visible: modelData.quotaKnown === true

                          RowLayout {
                            Layout.fillWidth: true

                            Text {
                              text: Model.formatBytes(modelData.quotaUsed) + " used of " + Model.formatBytes(modelData.quotaTotal)
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              color: root.dim
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                              text: modelData.quotaPercent + "% used (" + Model.formatBytes(modelData.quotaFree) + " free)"
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              color: modelData.quotaPercent > 90 ? root.urgent : root.dim
                            }
                          }

                          Rectangle {
                            Layout.fillWidth: true
                            height: Style.space(6)
                            radius: height / 2
                            color: Qt.rgba(1, 1, 1, 0.1)

                            Rectangle {
                              width: Math.min(parent.width, Math.max(0, parent.width * (modelData.quotaPercent / 100.0)))
                              height: parent.height
                              radius: height / 2
                              color: modelData.quotaPercent > 90 ? root.urgent : Color.accent
                            }
                          }
                        }
                      }
                    }
                  }
                }

                // Empty state if no drives
                EmptyState {
                  visible: backend.totalDrives === 0
                  Layout.fillWidth: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onAddProvider: function(provId) {
                    root.activeView = "add"
                    addForm.selectProvider(provId)
                  }
                }
              }
            }

            // ----------------------------------------------------------------
            // 2. CLOUD FILE BROWSER VIEW
            // ----------------------------------------------------------------
            ColumnLayout {
              visible: root.activeView === "files"
              anchors.fill: parent
              anchors.margins: Style.space(20)
              spacing: Style.space(12)

              // Drive & Path Bar
              RowLayout {
                Layout.fillWidth: true
                spacing: Style.space(10)

                Text {
                  text: "Drive:"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: root.foreground
                }

                // Remote buttons selector
                Row {
                  spacing: Style.space(6)
                  Repeater {
                    model: backend.drives

                    Button {
                      text: modelData.name
                      iconText: modelData.glyph || "󰅟"
                      selected: root.activeRemote === modelData.name
                      fontFamily: root.fontFamily
                      foreground: root.foreground
                      bordered: true
                      onClicked: {
                        root.activeRemote = modelData.name
                        backend.setBrowserPath(modelData.name, "")
                      }
                    }
                  }
                }

                Item { Layout.fillWidth: true }

                Button {
                  iconText: "󰌹"
                  text: "Open Folder in System Files"
                  fontFamily: root.fontFamily
                  foreground: root.foreground
                  bordered: true
                  onClicked: backend.openFolder(root.activeRemote)
                }
              }

              // Breadcrumb Navigation
              BorderSurface {
                Layout.fillWidth: true
                implicitHeight: Style.space(38)
                radius: Style.cornerRadius
                color: Qt.rgba(1, 1, 1, 0.04)
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                RowLayout {
                  anchors {
                    fill: parent
                    leftMargin: Style.space(10)
                    rightMargin: Style.space(10)
                  }
                  spacing: Style.space(8)

                  PanelActionButton {
                    iconText: "󰁝"
                    tooltipText: "Up one level"
                    foreground: root.foreground
                    hoverColor: Color.accent
                    onClicked: {
                      var parts = backend.browserPath.split("/").filter(function(x) { return x.length > 0 })
                      parts.pop()
                      backend.setBrowserPath(root.activeRemote, parts.join("/"))
                    }
                  }

                  Text {
                    text: root.activeRemote + ": /" + backend.browserPath
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: root.foreground
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                  }

                  PanelActionButton {
                    iconText: "󰑐"
                    tooltipText: "Reload directory"
                    foreground: root.foreground
                    hoverColor: Color.accent
                    onClicked: backend.setBrowserPath(root.activeRemote, backend.browserPath)
                  }
                }
              }

              // File List
              Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: fileListCol.implicitHeight
                clip: true
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                Column {
                  id: fileListCol
                  width: parent.width
                  spacing: Style.space(4)

                  Text {
                    visible: backend.browserFiles.length === 0 && !backend.browserLoading
                    text: root.activeRemote === "" ? "Select a drive above to browse files." : "Empty folder or drive not mounted."
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: root.dim
                    topPadding: Style.space(40)
                    anchors.horizontalCenter: parent.horizontalCenter
                  }

                  Text {
                    visible: backend.browserLoading
                    text: "Loading files…"
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    color: Color.accent
                    topPadding: Style.space(40)
                    anchors.horizontalCenter: parent.horizontalCenter
                  }

                  Repeater {
                    model: backend.browserFiles

                    CursorSurface {
                      width: fileListCol.width
                      implicitHeight: Style.space(36)
                      hasCursor: false

                      MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.hasCursor = true
                        onExited: parent.hasCursor = false
                        onDoubleClicked: {
                          if (modelData.isDir) {
                            backend.setBrowserPath(root.activeRemote, modelData.relPath)
                          } else if (modelData.path) {
                            backend.openFile(modelData.path)
                          }
                        }
                      }

                      RowLayout {
                        anchors {
                          fill: parent
                          leftMargin: Style.space(12)
                          rightMargin: Style.space(12)
                        }
                        spacing: Style.space(10)

                        Text {
                          text: modelData.isDir ? "󰉋" : "󰈔"
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.icon
                          color: modelData.isDir ? Color.accent : root.dim
                        }

                        Text {
                          Layout.fillWidth: true
                          text: modelData.name
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.bodySmall
                          font.bold: modelData.isDir
                          color: root.foreground
                          elide: Text.ElideRight
                        }

                        Text {
                          text: modelData.isDir ? "Folder" : Model.formatBytes(modelData.size)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          color: root.dim
                        }

                        Text {
                          visible: modelData.modifiedTs > 0
                          text: Model.formatRelativeTime(modelData.modifiedTs)
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          color: Qt.darker(root.foreground, 1.8)
                        }
                      }
                    }
                  }
                }
              }
            }

            // ----------------------------------------------------------------
            // 3. ADD ACCOUNT VIEW (Native In-App GUI Setup)
            // ----------------------------------------------------------------
            AddAccountForm {
              id: addForm
              visible: root.activeView === "add"
              anchors.fill: parent
              backend: backend
              foreground: root.foreground
              background: root.background
              accent: root.accent
              urgent: root.urgent
              dim: root.dim
              fontFamily: root.fontFamily
              onAccountAdded: function(newRemoteName) {
                root.activeRemote = newRemoteName
                root.activeView = "drives"
                backend.refresh()
              }
            }

            // ----------------------------------------------------------------
            // 4. ACTIVITY & LOGS VIEW
            // ----------------------------------------------------------------
            ColumnLayout {
              visible: root.activeView === "activity"
              anchors.fill: parent
              anchors.margins: Style.space(20)
              spacing: Style.space(12)

              RowLayout {
                Layout.fillWidth: true

                Text {
                  text: "Live Mount Logs"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: root.foreground
                }

                Item { Layout.fillWidth: true }

                Repeater {
                  model: backend.drives

                  Button {
                    text: modelData.name
                    fontFamily: root.fontFamily
                    foreground: root.foreground
                    bordered: true
                    onClicked: backend.loadLog(modelData.name)
                  }
                }
              }

              BorderSurface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Style.cornerRadius
                color: Qt.darker(root.background, 1.25)
                borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                Flickable {
                  anchors.fill: parent
                  anchors.margins: Style.space(12)
                  contentWidth: width
                  contentHeight: logText.implicitHeight
                  clip: true
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  Text {
                    id: logText
                    width: parent.width
                    text: backend.currentLog || "Select a drive above to view its mount log."
                    font.family: "monospace"
                    font.pixelSize: Style.font.caption
                    color: root.foreground
                    wrapMode: Text.WrapAnywhere
                  }
                }
              }
            }

            // ----------------------------------------------------------------
            // 5. SETTINGS VIEW
            // ----------------------------------------------------------------
            Flickable {
              visible: root.activeView === "settings"
              anchors.fill: parent
              contentWidth: width
              contentHeight: settingsCol.implicitHeight + Style.space(40)
              clip: true
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              ColumnLayout {
                id: settingsCol
                anchors {
                  left: parent.left
                  right: parent.right
                  top: parent.top
                  margins: Style.space(20)
                }
                spacing: Style.space(16)

                Text {
                  text: "General Configuration"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.bold: true
                  color: root.foreground
                }

                BorderSurface {
                  Layout.fillWidth: true
                  implicitHeight: cfgInner.implicitHeight + Style.space(24)
                  radius: Style.cornerRadius
                  color: Qt.rgba(1, 1, 1, 0.03)
                  borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

                  ColumnLayout {
                    id: cfgInner
                    anchors {
                      fill: parent
                      margins: Style.space(16)
                    }
                    spacing: Style.space(14)

                    RowLayout {
                      Layout.fillWidth: true
                      Text {
                        text: "Mount Root Directory:"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        color: root.foreground
                        Layout.preferredWidth: Style.space(180)
                      }
                      Text {
                        text: backend.mountRoot
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        color: Color.accent
                      }
                    }

                    RowLayout {
                      Layout.fillWidth: true
                      Text {
                        text: "VFS Cache Mode:"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        color: root.foreground
                        Layout.preferredWidth: Style.space(180)
                      }
                      Text {
                        text: backend.vfsCacheMode
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        color: root.foreground
                      }
                    }

                    RowLayout {
                      Layout.fillWidth: true
                      Text {
                        text: "Cache Max Size:"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        color: root.foreground
                        Layout.preferredWidth: Style.space(180)
                      }
                      Text {
                        text: backend.cacheMaxSizeGb + " GB"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        color: root.foreground
                      }
                    }

                    RowLayout {
                      Layout.fillWidth: true
                      Text {
                        text: "Auto-mount on login:"
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        color: root.foreground
                        Layout.preferredWidth: Style.space(180)
                      }
                      ToggleSwitch {
                        checked: backend.autoMountAll
                        foreground: root.foreground
                        onToggled: backend.updateConfig("auto_mount_all", !backend.autoMountAll)
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
  }

  // ==========================================================================
  // HELPER COMPONENTS
  // ==========================================================================
  component NavButton: Item {
    id: navBtn
    property string glyph: ""
    property string label: ""
    property string viewId: ""
    property string badgeText: ""

    readonly property bool active: root.activeView === viewId

    Layout.fillWidth: true
    implicitHeight: Style.space(38)

    CursorSurface {
      anchors.fill: parent
      radius: Style.cornerRadius
      hasCursor: navMouse.containsMouse
      current: navBtn.active

      RowLayout {
        anchors {
          fill: parent
          leftMargin: Style.space(10)
          rightMargin: Style.space(10)
        }
        spacing: Style.space(8)

        Text {
          text: navBtn.glyph
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
          color: navBtn.active ? Color.accent : (navMouse.containsMouse ? root.foreground : root.dim)
        }

        Text {
          Layout.fillWidth: true
          text: navBtn.label
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: navBtn.active
          color: navBtn.active ? root.foreground : (navMouse.containsMouse ? root.foreground : root.dim)
        }

        Text {
          visible: navBtn.badgeText !== ""
          text: navBtn.badgeText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Color.accent
        }
      }

      MouseArea {
        id: navMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activeView = navBtn.viewId
      }
    }
  }

  component MetricCard: BorderSurface {
    id: mCard
    property string title: ""
    property string value: ""
    property string subtitle: ""
    property string glyph: ""
    property color glyphColor: Color.accent

    Layout.fillWidth: true
    implicitHeight: Style.space(76)
    radius: Style.cornerRadius
    color: Qt.rgba(1, 1, 1, 0.03)
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

    RowLayout {
      anchors {
        fill: parent
        margins: Style.space(12)
      }
      spacing: Style.space(12)

      Text {
        text: mCard.glyph
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
        color: mCard.glyphColor
      }

      Column {
        Layout.fillWidth: true
        spacing: 0

        Text {
          text: mCard.title
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: root.dim
        }

        Text {
          text: mCard.value
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
        }

        Text {
          text: mCard.subtitle
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(1)
          color: root.dim
        }
      }
    }
  }

  component ProviderConnectCard: BorderSurface {
    id: pCard
    property string providerName: ""
    property string providerDesc: ""
    property string providerGlyph: ""
    property color providerColor: root.foreground
    signal connectClicked()

    implicitWidth: Style.space(240)
    implicitHeight: Style.space(130)
    radius: Style.cornerRadius
    color: pMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.03)
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

    ColumnLayout {
      anchors {
        fill: parent
        margins: Style.space(14)
      }
      spacing: Style.space(8)

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          text: pCard.providerGlyph
          font.family: root.fontFamily
          font.pixelSize: Style.font.heading
          color: pCard.providerColor
        }

        Text {
          Layout.fillWidth: true
          text: pCard.providerName
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          color: root.foreground
        }
      }

      Text {
        Layout.fillWidth: true
        text: pCard.providerDesc
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: root.dim
        wrapMode: Text.WordWrap
      }

      Item { Layout.fillHeight: true }

      Button {
        Layout.fillWidth: true
        text: "Connect"
        iconText: "󰐕"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: pCard.connectClicked()
      }
    }

    MouseArea {
      id: pMouse
      anchors.fill: parent
      hoverEnabled: true
      propagateComposedEvents: true
    }
  }
}

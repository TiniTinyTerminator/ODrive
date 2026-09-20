import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

CursorSurface {
  id: root

  property var drive: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool isMounted: drive ? drive.mounted === true : false
  property bool editingLocation: false
  // Mount root, so the suggested path can follow a renamed drive
  property string mountRoot: "~/Cloud"
  readonly property string defaultMountPath: mountRoot + "/" + (drive ? drive.name : "")
  readonly property bool hasCustomPath: drive ? String(drive.mountPath) !== defaultMountPath : false
  property bool confirmingRemove: false

  signal toggleMount()
  signal openFolder()
  signal updateMountPath(string newPath)
  signal renameDrive(string newName, var newPath)
  signal removeDrive()
  signal selected()

  // True once the mount path has been typed in by hand, so renaming stops rewriting it
  property bool pathEdited: false
  readonly property bool hasEdits: editingLocation && root.drive
    && (nameInput.text.trim() !== String(root.drive.name)
        || pathInput.text.trim() !== String(root.drive.mountPath))

  function resetEditor() {
    nameInput.text = root.drive ? String(root.drive.name) : ""
    pathInput.text = root.drive ? String(root.drive.mountPath) : ""
    root.pathEdited = false
  }

  // An empty path means "use the default location", so don't store one that is already the default
  function _pathArgument(name, path) {
    return (path === "" || path === root.mountRoot + "/" + name) ? "" : path
  }

  function applyEdits() {
    if (!root.drive) return
    var oldName = String(root.drive.name)
    var newName = nameInput.text.trim()
    var newPath = pathInput.text.trim()
    root.editingLocation = false

    if (newName !== "" && newName !== oldName) {
      root.renameDrive(newName, _pathArgument(newName, newPath))
    } else if (newPath !== String(root.drive.mountPath)) {
      root.updateMountPath(_pathArgument(oldName, newPath))
    }
    root.pathEdited = false
  }

  implicitWidth: parent ? parent.width : Style.space(360)
  implicitHeight: column.implicitHeight + Style.space(16)

  hasCursor: false

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onEntered: root.hasCursor = true
    onExited: root.hasCursor = false
    onClicked: root.selected()
  }

  Column {
    id: column
    anchors {
      left: parent.left
      right: parent.right
      verticalCenter: parent.verticalCenter
      leftMargin: Style.space(10)
      rightMargin: Style.space(10)
    }
    spacing: Style.space(6)

    // Row 1: Provider Icon, Title, Status, and Action Controls
    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      // Provider icon badge
      Item {
        implicitWidth: Style.space(30)
        implicitHeight: Style.space(30)

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: (root.drive && root.drive.color) ? Qt.alpha(root.drive.color, 0.15) : Qt.rgba(1, 1, 1, 0.08)
        }

        Text {
          anchors.centerIn: parent
          text: root.drive ? (root.drive.glyph || "󰅟") : "󰅟"
          color: root.drive && root.drive.color ? root.drive.color : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }

      // Title & Path
      Column {
        Layout.fillWidth: true
        spacing: Style.space(1)

        RowLayout {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: root.drive ? root.drive.name : ""
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            color: root.foreground
            elide: Text.ElideRight
            Layout.maximumWidth: Style.space(140)
          }

          Text {
            text: root.isMounted ? "󰄬 mounted" : "󰅛 unmounted"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption - Style.space(1)
            color: root.isMounted ? Color.accent : Qt.darker(root.foreground, 1.8)
          }

          Item { Layout.fillWidth: true }
        }

        Text {
          text: root.drive ? root.drive.mountPath : ""
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(2)
          color: Qt.darker(root.foreground, 1.6)
          elide: Text.ElideMiddle
          width: parent.width
        }
      }

      // Action: Edit mount location
      PanelActionButton {
        iconText: "󰏫"
        tooltipText: root.editingLocation ? "Close editor" : "Rename or move this drive"
        foreground: root.editingLocation ? Color.accent : root.foreground
        hoverColor: Color.accent
        onClicked: {
          if (!root.editingLocation) root.resetEditor()
          root.editingLocation = !root.editingLocation
        }
      }

      // Action: Open in file manager
      PanelActionButton {
        visible: root.isMounted
        iconText: "󰉋"
        tooltipText: "Open in File Manager"
        foreground: root.foreground
        hoverColor: Color.accent
        onClicked: root.openFolder()
      }

      // Action: Mount / Unmount switch
      ToggleSwitch {
        checked: root.isMounted
        foreground: root.foreground
        onToggled: root.toggleMount()
      }

      // Action: Delete / Remove remote
      PanelActionButton {
        iconText: "󰆴"
        tooltipText: "Remove remote"
        foreground: root.confirmingRemove ? Color.urgent : Qt.darker(root.foreground, 1.6)
        hoverColor: Color.urgent
        onClicked: { root.confirmingRemove = !root.confirmingRemove }
      }
    }

    // Inline confirmation before deleting the rclone remote
    RowLayout {
      visible: root.confirmingRemove
      width: parent.width
      spacing: Style.space(8)

      Text {
        Layout.fillWidth: true
        text: "Remove " + (root.drive ? root.drive.name : "") + "? This deletes its rclone configuration."
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption - Style.space(1)
        color: Color.urgent
        wrapMode: Text.WordWrap
      }

      Button {
        text: "Remove"
        iconText: "󰆴"
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        foreground: Color.urgent
        bordered: true
        onClicked: {
          root.confirmingRemove = false
          root.removeDrive()
        }
      }

      Button {
        text: "Cancel"
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        foreground: root.foreground
        bordered: false
        onClicked: { root.confirmingRemove = false }
      }
    }

    // Row 2: Storage Quota Bar (if known)
    Column {
      width: parent.width
      visible: root.drive && root.drive.quotaKnown === true
      spacing: Style.space(3)

      RowLayout {
        width: parent.width

        Text {
          text: root.drive ? (Model.formatBytes(root.drive.quotaUsed) + " of " + Model.formatBytes(root.drive.quotaTotal)) : ""
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(2)
          color: Qt.darker(root.foreground, 1.6)
        }

        Item { Layout.fillWidth: true }

        Text {
          text: root.drive ? (root.drive.quotaPercent + "%") : ""
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(2)
          font.bold: true
          color: (root.drive && root.drive.quotaPercent > 90) ? Color.urgent : Qt.darker(root.foreground, 1.4)
        }
      }

      // Progress bar track
      Rectangle {
        width: parent.width
        height: Style.space(3)
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.08)

        // Progress fill
        Rectangle {
          width: Math.min(parent.width, Math.max(0, parent.width * ((root.drive ? root.drive.quotaPercent : 0) / 100.0)))
          height: parent.height
          radius: height / 2
          color: (root.drive && root.drive.quotaPercent > 90) ? Color.urgent : Color.accent
        }
      }
    }

    // Row 3: Inline Name & Mount Location Editor
    BorderSurface {
      visible: root.editingLocation
      width: parent.width
      implicitHeight: editCol.implicitHeight + Style.space(16)
      radius: Style.cornerRadius
      color: Qt.rgba(1, 1, 1, 0.04)
      borderSpec: Border.controlSpec("focus", root.foreground, Color.accent)

      ColumnLayout {
        id: editCol
        anchors {
          fill: parent
          margins: Style.space(10)
        }
        spacing: Style.space(8)

        Text {
          text: "Edit Drive"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          color: root.foreground
        }

        Text {
          text: "Name:"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(1)
          color: Qt.darker(root.foreground, 1.4)
        }

        TextField {
          id: nameInput
          Layout.fillWidth: true
          placeholderText: root.drive ? root.drive.name : ""
          onAccepted: { if (root.hasEdits) root.applyEdits() }
          // Letters, digits, '-' and '_' are what rclone remote names allow here
          onTextEdited: {
            var cleaned = text.replace(/[^A-Za-z0-9_-]/g, "")
            if (cleaned !== text) text = cleaned
            // Keep the suggested path in step with the name until the path is edited by hand
            if (!root.pathEdited && !root.hasCustomPath) {
              pathInput.text = root.mountRoot + "/" + cleaned
            }
          }
        }

        Text {
          text: "Mount location:"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(1)
          color: Qt.darker(root.foreground, 1.4)
        }

        TextField {
          id: pathInput
          Layout.fillWidth: true
          placeholderText: root.defaultMountPath
          onAccepted: { if (root.hasEdits) root.applyEdits() }
          onTextEdited: { root.pathEdited = true }
        }

        Text {
          visible: root.isMounted
          text: "Saving unmounts the drive and mounts it again."
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(2)
          color: Qt.darker(root.foreground, 1.6)
          wrapMode: Text.WordWrap
          Layout.fillWidth: true
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Button {
            text: "Save"
            iconText: "󰄬"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: true
            enabled: root.hasEdits
            opacity: enabled ? 1.0 : 0.45
            onClicked: { root.applyEdits() }
          }

          Button {
            text: "Cancel"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: false
            onClicked: {
              root.editingLocation = false
              root.resetEditor()
            }
          }

          Item { Layout.fillWidth: true }
        }
      }
    }
  }
}

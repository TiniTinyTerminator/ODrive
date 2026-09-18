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

  signal toggleMount()
  signal openFolder()
  signal updateMountPath(string newPath)
  signal removeDrive()
  signal selected()

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
        tooltipText: root.editingLocation ? "Close location editor" : "Change mount directory"
        foreground: root.editingLocation ? Color.accent : root.foreground
        hoverColor: Color.accent
        onClicked: { root.editingLocation = !root.editingLocation }
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
        foreground: Qt.darker(root.foreground, 1.6)
        hoverColor: Color.urgent
        onClicked: root.removeDrive()
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

    // Row 3: Inline Mount Location Editor
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
          text: "Change Mount Location"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          color: root.foreground
        }

        TextField {
          id: pathInput
          Layout.fillWidth: true
          text: root.drive ? root.drive.mountPath : ""
          placeholderText: "~/Cloud/" + (root.drive ? root.drive.name : "")
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Button {
            text: "Save & Remount"
            iconText: "󰄬"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: true
            onClicked: {
              root.updateMountPath(pathInput.text.trim())
              root.editingLocation = false
            }
          }

          Button {
            text: "Cancel"
            fontFamily: root.fontFamily
            fontSize: Style.font.caption
            foreground: root.foreground
            bordered: false
            onClicked: { root.editingLocation = false }
          }

          Item { Layout.fillWidth: true }
        }
      }
    }
  }
}

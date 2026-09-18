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

  signal toggleMount()
  signal openFolder()
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

    // Row 1: Icon, Title, Status, and Controls
    RowLayout {
      width: parent.width
      spacing: Style.space(8)

      // Provider icon badge
      Item {
        implicitWidth: Style.space(28)
        implicitHeight: Style.space(28)

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: root.drive && root.drive.color ? Qt.rgba(
            Color.channel(root.drive.color, 0),
            Color.channel(root.drive.color, 1),
            Color.channel(root.drive.color, 2),
            0.15
          ) : Qt.rgba(1, 1, 1, 0.08)
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
        spacing: Style.space(2)

        RowLayout {
          spacing: Style.space(6)

          Text {
            text: root.drive ? root.drive.name : ""
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            color: root.foreground
            elide: Text.ElideRight
          }

          // Mounted status indicator
          Text {
            text: root.isMounted ? "󰄬 mounted" : "󰅛 unmounted"
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            color: root.isMounted ? Color.accent : Qt.darker(root.foreground, 1.8)
          }
        }

        Text {
          text: root.isMounted ? (root.drive ? root.drive.mountPath : "") : (root.drive ? root.drive.provider : "")
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.5)
          elide: Text.ElideMiddle
          width: parent.width
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
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.5)
        }

        Item { Layout.fillWidth: true }

        Text {
          text: root.drive ? (root.drive.quotaPercent + "%") : ""
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          color: (root.drive && root.drive.quotaPercent > 90) ? Color.urgent : Qt.darker(root.foreground, 1.4)
        }
      }

      // Progress bar track
      Rectangle {
        width: parent.width
        height: Style.space(4)
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.1)

        // Progress fill
        Rectangle {
          width: Math.min(parent.width, Math.max(0, parent.width * ((root.drive ? root.drive.quotaPercent : 0) / 100.0)))
          height: parent.height
          radius: height / 2
          color: (root.drive && root.drive.quotaPercent > 90) ? Color.urgent : Color.accent
        }
      }
    }
  }
}

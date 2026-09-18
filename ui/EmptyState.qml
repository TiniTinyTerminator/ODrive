import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Item {
  id: root

  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal addProvider(string providerId)

  implicitWidth: parent ? parent.width : Style.space(360)
  implicitHeight: col.implicitHeight + Style.space(20)

  Column {
    id: col
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      margins: Style.space(12)
    }
    spacing: Style.space(12)

    Column {
      width: parent.width
      spacing: Style.space(4)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "No Cloud Drives Configured"
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        color: root.foreground
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Connect your cloud accounts to mount and manage files directly in Omarchy."
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        color: Qt.darker(root.foreground, 1.6)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        width: parent.width - Style.space(30)
      }
    }

    PanelSeparator {
      width: parent.width
      foreground: root.foreground
    }

    PanelSectionHeader {
      text: "Quick Connect"
      foreground: root.foreground
      fontFamily: root.fontFamily
    }

    // Grid of popular providers
    Flow {
      width: parent.width
      spacing: Style.space(8)

      Button {
        iconText: "󰊭"
        text: "Google Drive"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.addProvider("drive")
      }

      Button {
        iconText: "󰏊"
        text: "OneDrive"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.addProvider("onedrive")
      }

      Button {
        iconText: ""
        text: "Dropbox"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.addProvider("dropbox")
      }

      Button {
        iconText: "󰒋"
        text: "Nextcloud"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.addProvider("nextcloud")
      }

      Button {
        iconText: "󰅟"
        text: "Other Provider…"
        fontFamily: root.fontFamily
        foreground: root.foreground
        bordered: true
        onClicked: root.addProvider("")
      }
    }
  }
}

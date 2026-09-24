import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var files: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  signal fileSelected(string filePath)

  width: parent ? parent.width : Style.space(360)
  spacing: Style.space(4)
  visible: files && files.length > 0

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  PanelSectionHeader {
    text: "Recent Cloud Files"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Repeater {
    model: root.files

    CursorSurface {
      id: fileRow
      width: root.width
      implicitHeight: Style.space(32)
      hasCursor: false

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: fileRow.hasCursor = true
        onExited: fileRow.hasCursor = false
        onClicked: root.fileSelected(modelData.path)
      }

      RowLayout {
        anchors {
          fill: parent
          leftMargin: Style.space(8)
          rightMargin: Style.space(8)
        }
        spacing: Style.space(8)

        Text {
          text: "󰈔"
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Color.accent
        }

        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: modelData.name
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          color: root.foreground
          elide: Text.ElideRight
        }

        Text {
          text: Model.formatRelativeTime(modelData.modifiedTs)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.8)
        }
      }
    }
  }
}

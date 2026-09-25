import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Collapsible "Recent Cloud Files" section: the header toggles a list that
// scrolls on its own, so the panel keeps a fixed size however many files show.
ColumnLayout {
  id: root

  property var files: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool expanded: false
  property real maxListHeight: Style.space(170)

  signal fileSelected(string filePath)

  spacing: Style.space(4)
  visible: files && files.length > 0

  PanelSeparator {
    Layout.fillWidth: true
    foreground: root.foreground
  }

  // Header row doubles as the dropdown toggle. No hover box: the title sits flush
  // with the other section headers, so hover brightens the text instead.
  Item {
    id: header
    Layout.fillWidth: true
    implicitHeight: Style.space(30)

    MouseArea {
      id: headerMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.expanded = !root.expanded
    }

    RowLayout {
      anchors {
        fill: parent
        // Right edge lines up with the file rows' timestamps
        rightMargin: Style.space(8)
      }
      spacing: Style.space(8)

      PanelSectionHeader {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        topPadding: 0
        text: "Recent Cloud Files"
        foreground: headerMouse.containsMouse ? Qt.lighter(root.foreground, 1.4) : root.foreground
        fontFamily: root.fontFamily
      }

      // File count pill
      Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Math.max(implicitHeight, countText.implicitWidth + Style.space(12))
        implicitHeight: countText.implicitHeight + Style.space(4)
        radius: height / 2
        color: Qt.alpha(root.foreground, 0.08)

        Text {
          id: countText
          anchors.centerIn: parent
          text: String(root.files ? root.files.length : 0)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption - Style.space(1)
          color: Qt.darker(root.foreground, 1.3)
        }
      }

      // Same glyph and tint as the shell's Dropdown; points right when closed, down when open
      Text {
        Layout.alignment: Qt.AlignVCenter
        text: "󰅀"
        rotation: root.expanded ? 0 : -90
        color: headerMouse.containsMouse ? Color.accent : Qt.darker(root.foreground, 1.2)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Behavior on rotation { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      }
    }
  }

  ListView {
    id: fileList
    Layout.fillWidth: true
    Layout.preferredHeight: root.expanded ? Math.min(contentHeight, root.maxListHeight) : 0
    // Stay visible while the height animates closed
    visible: Layout.preferredHeight > 0
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
    Behavior on Layout.preferredHeight { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // Bound by index, so a status refresh with the same number of files
    // updates rows in place instead of rebuilding them and losing the scroll
    model: root.files ? root.files.length : 0

    delegate: CursorSurface {
      id: fileRow
      required property int index
      readonly property var file: root.files[index] || ({})
      width: ListView.view.width
      implicitHeight: Style.space(32)
      hasCursor: false

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: fileRow.hasCursor = true
        onExited: fileRow.hasCursor = false
        onClicked: root.fileSelected(fileRow.file.path)
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
          text: fileRow.file.name || ""
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          color: root.foreground
          elide: Text.ElideRight
        }

        Text {
          text: Model.formatRelativeTime(fileRow.file.modifiedTs)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          color: Qt.darker(root.foreground, 1.8)
        }
      }
    }
  }
}

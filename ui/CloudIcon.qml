import QtQuick
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property string fontFamily: Style.font.family
  property bool active: false
  property bool busy: false
  property bool hasError: false
  property int mountedCount: 0

  width: iconSize * 1.2
  height: iconSize
  implicitWidth: iconSize * 1.2
  implicitHeight: iconSize

  Text {
    id: cloudGlyph
    z: 0
    anchors.centerIn: parent
    text: root.active ? "󰅠" : "󰅟"
    color: root.hasError ? Color.urgent : root.color
    font.family: root.fontFamily
    font.pixelSize: root.iconSize
    opacity: root.busy ? (root.active ? 0.5 : 0.3) : (root.active ? 1.0 : 0.6)

    Behavior on opacity {
      NumberAnimation { duration: 150 }
    }
  }

  // Spinning sync indicator in front when busy
  Text {
    id: spinGlyph
    z: 1
    visible: root.busy
    anchors.centerIn: parent
    text: "󰑐"
    color: Color.accent
    font.family: root.fontFamily
    font.pixelSize: root.iconSize * 0.85
    transformOrigin: Item.Center

    RotationAnimation on rotation {
      running: root.busy
      from: 0
      to: 360
      duration: 1000
      loops: Animation.Infinite
    }
  }
}

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
    anchors.centerIn: parent
    text: root.active ? "󰅠" : "󰅟"
    color: root.hasError ? Color.urgent : root.color
    font.family: root.fontFamily
    font.pixelSize: root.iconSize
    opacity: root.active ? 1.0 : 0.6
  }

  // Spinning sync indicator when busy
  Text {
    id: spinGlyph
    visible: root.busy
    anchors.centerIn: parent
    text: "󰑐"
    color: Color.accent
    font.family: root.fontFamily
    font.pixelSize: root.iconSize * 0.8

    NumberAnimation on rotation {
      running: root.busy
      from: 0
      to: 360
      duration: 1200
      loops: Animation.Infinite
    }
  }
}

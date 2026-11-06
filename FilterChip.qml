import QtQuick
import qs.Commons
import qs.Ui

// A filter chip with an optional count badge. ButtonGroup draws plain text
// chips only; the unread count needs to sit inside the chip where it can be
// read and clicked as one control.
BorderSurface {
  id: root

  property string label: ""
  property bool selected: false
  property int count: 0
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family

  signal clicked()

  readonly property bool hot: mouse.containsMouse
  readonly property string countText: root.count > 99 ? "99+" : I18n.formatNumber(root.count)

  implicitWidth: content.implicitWidth + Style.space(22)
  implicitHeight: Style.spacing.controlHeight
  radius: Style.cornerRadius
  color: root.selected
    ? Style.selectedFillFor(root.foreground, root.accent)
    : (root.hot ? Style.hoverFillFor(root.foreground, root.accent) : "transparent")
  borderSpec: Border.controlSpec(
    root.selected ? "selected" : (root.hot ? "hover-cursor" : "normal"),
    root.foreground, root.accent)

  Row {
    id: content
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: root.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Rectangle {
      id: badge
      visible: root.count > 0
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(Style.space(16), badgeText.implicitWidth + Style.space(6))
      height: Math.max(Style.space(16), Style.font.caption + Style.space(6))
      radius: height / 2
      color: root.accent

      Text {
        id: badgeText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.countText
        color: Commons.Color.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}

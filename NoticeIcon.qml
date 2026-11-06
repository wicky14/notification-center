import QtQuick
import Quickshell
import qs.Commons

// The square at the head of a notification row: the sender's app icon when
// the shell resolved one, else the glyph an Omarchy sender asked for, else
// the first letter of the app or site. History keeps no sender images, so
// those three are the whole vocabulary.
Item {
  id: root

  property string glyph: ""
  property string iconName: ""
  property string label: ""
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property real size: Style.space(32)

  readonly property string letter: {
    var text = String(root.label || "").replace(/^www\./, "").trim()
    return text.length > 0 ? text.charAt(0).toUpperCase() : "•"
  }
  readonly property bool hasGlyph: String(root.glyph || "").length > 0

  // An absolute path is the sender's own file; anything else is a theme
  // icon name. Quickshell.iconPath answers "" when the name is missing, which
  // drops through to the glyph or letter.
  readonly property string iconSource: {
    var name = String(root.iconName || "")
    if (!name) return ""
    return name.charAt(0) === "/" ? Util.fileUrl(name) : Quickshell.iconPath(name, true)
  }

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Style.normalFillFor(root.foreground, root.accent)
    border.width: 0
  }

  Image {
    id: picture
    anchors.fill: parent
    anchors.margins: Style.space(5)
    source: root.iconSource
    sourceSize.width: root.size * 2
    sourceSize.height: root.size * 2
    fillMode: Image.PreserveAspectFit
    smooth: true
    mipmap: true
    asynchronous: true
    cache: true
    visible: status === Image.Ready && root.iconSource !== ""
  }

  Text {
    anchors.centerIn: parent
    visible: picture.status !== Image.Ready && root.hasGlyph
    textFormat: Text.PlainText
    text: root.glyph
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.title
  }

  Text {
    anchors.centerIn: parent
    visible: picture.status !== Image.Ready && !root.hasGlyph
    textFormat: Text.PlainText
    text: root.letter
    color: root.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.subtitle
    font.weight: Font.DemiBold
  }
}

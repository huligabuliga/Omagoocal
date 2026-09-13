import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The provisional event painted while a date range is being dragged. Accent
// belongs to the active system theme, not to any calendar, so the preview
// stays neutral until the editor chooses its destination.
Rectangle {
  id: root
  property var panel: null
  property bool showLabel: false

  color: Util.alpha(Color.accent, Model.chipAlpha(panel.lightSurface, false))
  radius: Style.cornerRadius > 0 ? Style.space(3) : 0
  clip: true

  Rectangle {
    width: Style.space(root.panel.lightSurface ? 3 : 2)
    height: parent.height
    color: Color.accent
  }

  Text {
    anchors.fill: parent
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(4)
    visible: root.showLabel
    verticalAlignment: Text.AlignVCenter
    text: "New event"
    textFormat: Text.PlainText
    color: root.panel.ink
    font.family: root.panel.mono
    font.pixelSize: Style.font.caption
    font.bold: true
    elide: Text.ElideRight
  }
}

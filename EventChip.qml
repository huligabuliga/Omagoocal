import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One event, drawn the same way everywhere it appears.
//
// The colour Google assigned is a 2px spine and a wash behind the text, never
// a solid fill: a week of solid blocks turns into a swatch book, and the
// titles stop being readable at exactly the density where you need them.
Rectangle {
  id: root
  property var panel: null
  property var event: null
  property bool compact: false          // month cells: one line, no times
  property bool overflow: false         // "+N more", not a real event
  property bool past: event && event.endAt < panel.now && !overflow

  // Too short to stack a time above a title. A quarter-hour block is about
  // one line of text tall, and the stacked layout spent that line on the
  // start time and then clipped the title through the middle — the two
  // things you actually read, both unreadable. Below this the chip puts them
  // side by side on the one line it has.
  readonly property bool tight: !compact && !overflow && height < Style.space(30)

  signal overflowClicked()

  readonly property color tint: event ? event.color : panel.ink

  // "eventTimes": "always" draws the start time even where it would otherwise
  // be dropped for space — on short or narrow chips, and inline on a one-line
  // month cell. The default "auto" keeps the density trade-off.
  readonly property bool clockAlways: (panel.eventTimes || "auto") === "always"
  readonly property bool showClock: !root.compact
    && (root.clockAlways || (root.height > Style.space(28) && root.width > Style.space(92)))
  readonly property bool inlineClock: root.compact && root.clockAlways

  color: overflow
    ? (hover.containsMouse ? Util.alpha(Color.accent, 0.26) : Util.alpha(panel.ink, 0.13))
    : Util.alpha(tint, Model.chipAlpha(panel.lightSurface, hover.containsMouse))
  radius: Style.cornerRadius > 0 ? Style.space(3) : 0
  // Delegates outlive their model entry by a frame when a view swaps out.
  visible: root.event !== null && root.event !== undefined
  // A past event fades, but on a light ground 45% is close to invisible.
  opacity: past ? (panel.lightSurface ? 0.62 : 0.45) : 1.0
  clip: true

  Behavior on color { ColorAnimation { duration: 120 } }
  Behavior on opacity { NumberAnimation { duration: 150 } }

  // The spine. Full saturation here is affordable because it is 2px wide.
  Rectangle {
    width: Style.space(root.panel.lightSurface ? 3 : 2)
    height: parent.height
    visible: !root.overflow
    color: root.tint
  }

  // The marker earns an outline instead of a spine: it is a control, not an
  // event, and it has to look pressable at 45px wide.
  Rectangle {
    anchors.fill: parent
    visible: root.overflow
    color: "transparent"
    radius: parent.radius
    border.width: 1
    border.color: hover.containsMouse
      ? Color.accent
      : Util.alpha(root.panel.ink, 0.30)
    Behavior on border.color { ColorAnimation { duration: 120 } }
  }

  // ---- Overflow marker: a count, centred, no colour of its own. It stands
  //      for a stack of events, so borrowing any single one's colour would
  //      be a lie about what is underneath.
  Text {
    anchors.centerIn: parent
    visible: root.overflow
    horizontalAlignment: Text.AlignHCenter
    text: root.overflow && root.event
      ? String(root.event.count) + (root.height > Style.space(40) ? "\nmore" : "")
      : ""
    color: hover.containsMouse ? Color.accent : root.panel.dim
    font.family: root.panel.mono
    font.pixelSize: Style.font.bodySmall
    font.bold: true
  }

  // ---- Short event: one line, time then title, centred in what height
  //      there is. Two Texts rather than one concatenated string, because
  //      the title is somebody else's text and never shares a run with ours.
  Item {
    anchors.fill: parent
    visible: root.tight

    Text {
      id: tightTime
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      // Under a narrow lane the clock eats the title it was meant to
      // introduce; the tooltip still carries it.
      visible: root.width > Style.space(104)
      text: root.event ? Model.clockLabel(root.event.startAt, root.panel.hours12) : ""
      textFormat: Text.PlainText
      color: Util.alpha(root.panel.ink, 0.6)
      font.family: root.panel.mono
      font.pixelSize: Style.font.caption
    }

    Text {
      anchors.left: tightTime.visible ? tightTime.right : parent.left
      anchors.leftMargin: Style.space(tightTime.visible ? 5 : 6)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      text: root.event ? root.event.title : ""
      textFormat: Text.PlainText
      color: root.panel.ink
      font.family: root.panel.mono
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Column {
    anchors.fill: parent
    visible: !root.overflow && !root.tight
    anchors.leftMargin: Style.space(6)
    anchors.rightMargin: Style.space(4)
    anchors.topMargin: root.compact ? 0 : Style.space(2)
    spacing: 0

    // In a narrow lane the start time costs a whole line of a title that has
    // only a few characters to spend. The tooltip still carries it; "Always"
    // overrides the trade-off.
    Text {
      width: parent.width
      visible: root.showClock
      text: Model.clockLabel(root.event.startAt, root.panel.hours12)
      textFormat: Text.PlainText
      color: Util.alpha(root.panel.ink, 0.6)
      font.family: root.panel.mono
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      height: root.compact ? root.height : implicitHeight
      verticalAlignment: root.compact ? Text.AlignVCenter : Text.AlignTop
      // Remote text is never parsed as markup — same rule as every
      // first-party Omarchy panel.
      text: (root.inlineClock
        ? Model.clockLabel(root.event.startAt, root.panel.hours12) + "  " : "")
        + root.event.title
      textFormat: Text.PlainText
      color: root.panel.ink
      font.family: root.panel.mono
      font.pixelSize: root.compact ? Style.font.caption : Style.font.bodySmall
      font.strikeout: false
      elide: Text.ElideRight
      maximumLineCount: root.compact ? 1 : 2
      wrapMode: root.compact ? Text.NoWrap : Text.Wrap
    }

    Text {
      width: parent.width
      visible: !root.compact && root.event.location !== "" && root.height > Style.space(56)
      text: "󰍎 " + root.event.location
      textFormat: Text.PlainText
      color: Util.alpha(root.panel.ink, 0.5)
      font.family: root.panel.mono
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: hover
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    onClicked: function(mouse) {
      if (root.overflow) root.overflowClicked()
      else if (mouse.button === Qt.MiddleButton && Model.isWebLink(root.event.link))
        Quickshell.execDetached(["/usr/bin/xdg-open", root.event.link])
      else
        root.panel.edit(root.event)
    }

    PanelToolTip {
      visible: hover.containsMouse
      text: root.overflow
        ? root.event.count + " more events in this slot\nOpen the day view to see them"
        : root.event.title
          + "\n" + Model.rangeLabel(root.event, root.panel.hours12)
          + "\n" + root.event.calendarName
          + (root.event.location ? "\n󰍎 " + root.event.location : "")
    }
  }
}

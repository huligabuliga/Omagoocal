import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Panel masthead. Deliberately asymmetric: the date reads as a headline on
// the left at display size, and every control sits in one quiet row on the
// right, so the eye lands on "where am I" before "what can I press".
Item {
  id: root
  property var panel: null

  implicitHeight: Math.max(masthead.implicitHeight, controls.implicitHeight)
  height: implicitHeight

  Column {
    id: masthead
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(1)

    Text {
      text: panel.title
      color: panel.ink
      font.family: panel.mono
      font.pixelSize: Style.font.displayLarge
      font.bold: true
      // Display sizes in a monospace face sit too loose by default; pulling
      // the tracking in is what makes it read as a masthead.
      font.letterSpacing: -1.2
    }

    Text {
      text: panel.subtitle
      color: panel.dim
      font.family: panel.mono
      font.pixelSize: Style.font.caption
      font.letterSpacing: 1.6
    }
  }

  Row {
    id: controls
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(14)

    // ---- Where. Chevrons flank a TODAY pill that lights up only when it
    //      would actually take you somewhere.
    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)
      visible: panel.view !== "settings"

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅁"
        tooltipText: "Previous  [ "
        foreground: panel.dim
        hoverColor: panel.ink
        onClicked: panel.step(-1)
      }

      Button {
        anchors.verticalCenter: parent.verticalCenter
        text: "TODAY"
        tooltipText: "Today  T"
        bordered: true
        enabled: !panel.onToday
        opacity: enabled ? 1 : 0.45
        foreground: panel.ink
        accent: Color.accent
        fontFamily: panel.mono
        fontSize: Style.font.caption
        onClicked: panel.goToday()
      }

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰅂"
        tooltipText: "Next  ] "
        foreground: panel.dim
        hoverColor: panel.ink
        onClicked: panel.step(1)
      }
    }

    ButtonGroup {
      anchors.verticalCenter: parent.verticalCenter
      visible: panel.connected
      foreground: panel.ink
      background: Color.popups.background
      accent: Color.accent
      fontFamily: panel.mono
      fontSize: Style.font.caption
      value: panel.view
      options: [
        { value: "day", label: "DAY", tooltip: "Day view  D" },
        { value: "week", label: "WEEK", tooltip: "Week view  W" },
        { value: "month", label: "MONTH", tooltip: "Month view  M" }
      ]
      onChanged: function(v) { panel.setView(v) }
    }

    Row {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      PanelActionButton {
        id: refreshButton
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰑐"
        tooltipText: "Refresh  R "
        foreground: panel.busy ? Color.accent : panel.dim
        hoverColor: panel.ink
        visible: panel.connected
        onClicked: panel.refreshNow()

        // PanelActionButton has no spinner of its own, so the whole button
        // turns while a refresh is in flight.
        RotationAnimator on rotation {
          running: panel.busy
          loops: Animation.Infinite
          from: 0
          to: 360
          duration: 1200
          onStopped: refreshButton.rotation = 0
        }
      }

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰐕"
        tooltipText: "New event  N "
        foreground: panel.dim
        hoverColor: Color.accent
        visible: panel.connected
        onClicked: panel.compose(null, false)
      }

      PanelActionButton {
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰒓"
        tooltipText: "Settings  , "
        foreground: panel.view === "settings" ? Color.accent : panel.dim
        hoverColor: panel.ink
        onClicked: panel.setView(panel.view === "settings"
          ? (panel.cfg.defaultView || "week") : "settings")
      }
    }
  }

  // ---- Failure line. Errors belong under the masthead, not in a toast that
  //      disappears before it is read.
  Text {
    anchors.left: parent.left
    anchors.top: masthead.bottom
    anchors.topMargin: Style.space(4)
    width: parent.width * 0.6
    visible: panel.error !== ""
    text: "⚠  " + panel.error
    textFormat: Text.PlainText   // API error bodies are remote text too
    color: Color.urgent
    elide: Text.ElideRight
    font.family: panel.mono
    font.pixelSize: Style.font.caption
  }
}

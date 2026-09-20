import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar label for the Google Calendar plugin, and the host for its panel.
//
// The label answers the only question a calendar in a status bar is asked in
// passing — "what is next, and how long have I got?" — and takes on that
// event's own colour as it closes in, so the bar itself is the warning.
// Panel.qml owns everything you have to look at deliberately.
BarWidget {
  id: root
  moduleName: "io.github.huligabuliga.omagoocal"

  readonly property bool showNextEvent: setting("showNextEvent", true) !== false
  // The clock format is a calendar preference, so it lives with the rest of
  // them in the backend config rather than being duplicated into shell.json.
  readonly property bool hours12: panelLoader.item ? panelLoader.item.hours12 === true : false

  readonly property var nextEvent: panelLoader.item ? panelLoader.item.nextEvent : null
  property date now: new Date()

  // The bar's own ground and ink, so the imminent label's colour can be made
  // legible against them rather than trusted as-is.
  readonly property color barGround: bar ? bar.background : Color.background
  readonly property color barInk: bar ? bar.barForeground : Color.foreground

  // Inside this window the pill wears the event's colour. Two minutes of
  // amber is noise; the last stretch before a meeting is the part that needs
  // to catch an eye that is not looking.
  readonly property int imminentMinutes: 15
  readonly property real minutesAway: nextEvent
    ? (nextEvent.startAt.getTime() - now.getTime()) / 60000
    : Infinity
  readonly property bool imminent: minutesAway <= imminentMinutes
  readonly property bool running: nextEvent && minutesAway <= 0

  // With nothing upcoming the label is empty and the glyph alone stands in:
  // the clock beside this widget already shows the date, and a second copy
  // of it read as a gap in the bar.
  readonly property bool iconOnly: vertical || !showNextEvent || !nextEvent
  readonly property string label: {
    if (!nextEvent) return ""
    var title = String(nextEvent.title)
    if (title.length > 22) title = title.substring(0, 21) + "…"
    return title + "  " + Model.relative(nextEvent.startAt, now)
  }

  function refresh() {
    if (panelLoader.item) panelLoader.item.refreshNow()
  }

  // ---- Panel plumbing. Bar.findPanelWidget routes summon/hide/toggle through
  //      open/close/opened on the bar-widget root, so they live here and
  //      forward down rather than on the panel itself.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.now = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // The shell registers its own handler for the widget id, which shadows this
  // one, so the plugin's extra verbs get a target of their own. open/close/
  // toggle stay here too so a keybinding can use either name.
  IpcHandler {
    target: "omagoocal"

    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function newEvent(): void { if (panelLoader.item) panelLoader.item.composeNow() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.iconOnly ? "" : root.label
    labelVisible: !root.iconOnly
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.nextEvent
      ? root.nextEvent.title + "\n" + Model.rangeLabel(root.nextEvent, root.hours12)
        + "\n" + root.nextEvent.calendarName
      : "No upcoming events"

    // Colour is the signal, so it moves before it is read. A running event
    // holds the colour steady; one that is merely close breathes. The colour is
    // made legible against the bar first: a yellow calendar on a light theme
    // would otherwise paint the label in near-invisible yellow.
    foreground: root.imminent && root.nextEvent
      ? Model.legible(root.nextEvent.color, root.barGround, root.barInk)
      : root.barInk

    Behavior on foreground { ColorAnimation { duration: 400; easing.type: Easing.OutCubic } }

    onPressed: function(b) {
      if (b === Qt.RightButton) root.refresh()
      else if (b === Qt.MiddleButton) { if (panelLoader.item) panelLoader.item.composeNow() }
      else root.togglePanel()
    }

    SequentialAnimation on opacity {
      running: root.imminent && !root.running
      loops: Animation.Infinite
      alwaysRunToEnd: true
      NumberAnimation { to: 0.55; duration: 1100; easing.type: Easing.InOutSine }
      NumberAnimation { to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
    }

    // Vertical bars have no room for a label, and a bar with nothing to name
    // shows only the glyph; either way the glyph carries the colour.
    Text {
      visible: root.iconOnly
      anchors.centerIn: parent
      text: "󰃭"
      color: button.foreground
      font.family: button.fontFamily
      font.pixelSize: Style.font.icon
    }
  }
}

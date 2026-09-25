import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// A strip of one chip per calendar, directly under the masthead. Clicking a
// chip hides that calendar's events from every view; clicking it again brings
// them back. The colour is Google's own, so a chip and the events it controls
// read as the same thing, and the choice is remembered in the backend config
// (the same one the settings page writes), so the next sync drops or restores
// the events without a second place to look.
Item {
  id: root
  property var panel: null

  readonly property var calendars: panel ? panel.calendars : []
  readonly property bool show: panel && panel.calendarChips && panel.connected
    && panel.view !== "settings"
    && root.calendars.length > 0

  visible: show
  implicitHeight: show ? flow.implicitHeight : 0
  height: implicitHeight

  // Wraps rather than scrolls: a dozen calendars should stay visible as
  // controls, not disappear off the edge of the panel.
  Flow {
    id: flow
    width: parent.width
    spacing: Style.space(4)

    Repeater {
      model: root.calendars

      Button {
        required property var modelData
        // Read the enabled state from the local config, not the last sync, so
        // a click flips the chip at once instead of waiting for the refetch
        // that the toggle sets off.
        readonly property bool on: root.panel.calendarEnabled(modelData)

        text: Model.shortCalendarName(modelData.name)
        tooltipText: (on ? "Hide " : "Show ") + modelData.name
          + (modelData.account ? " · " + modelData.account : "")
        bordered: true
        selected: on
        accent: modelData.color || Color.accent
        // A chip wears its calendar's colour, made legible against the panel
        // (a yellow calendar on a light theme would otherwise vanish). Hidden
        // calendars recede rather than vanish: the chip is how you get them
        // back, so it has to stay where the eye last saw it.
        foreground: on
          ? Model.legible(String(modelData.color || root.panel.ink),
                          String(Color.popups.background), String(root.panel.ink))
          : root.panel.faint
        opacity: on ? 1.0 : 0.65
        fontFamily: root.panel.mono
        fontSize: Style.font.caption
        onClicked: root.panel.toggleCalendar(modelData)
      }
    }
  }
}

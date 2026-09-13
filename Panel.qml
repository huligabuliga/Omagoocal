import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Google Calendar panel: day, week and month views over every connected
// account, with an inline editor and a settings page.
//
// The look is a printed timetable rather than a web calendar — hairline
// rules instead of boxes, monospace numerals holding their column, and no
// colour anywhere except the colours Google already assigned to the events
// themselves. That way the chroma on screen is information, not decoration.
//
// Data and every subprocess live in Store.qml; this file only draws and
// forwards. It never speaks HTTP and never opens a path.
Panel {
  id: root
  moduleName: "io.github.huligabuliga.omagoocal"
  ipcTarget: "io.github.huligabuliga.omagoocal"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // The data lives in Store.qml, one instance per shell, so a second
  // monitor's panel shows the same events without a second backend and
  // without a second copy of every notification. The host hands it over
  // through the bar facade; a replacement bar that offers no service lookup
  // gets a private copy instead.
  readonly property var hostStore: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var store: hostStore || privateStore.item

  Loader {
    id: privateStore
    active: !!root.bar && !root.hostStore
    source: Qt.resolvedUrl("Store.qml")
  }

  readonly property var events: store ? store.events : []
  readonly property var calendars: store ? store.calendars : []
  readonly property var accounts: store ? store.accounts : []
  readonly property var cfg: store ? store.cfg : ({})
  readonly property bool busy: store ? store.busy : false
  readonly property string error: store ? store.error : ""
  readonly property bool everSynced: store ? store.everSynced : false
  readonly property bool depsInstalled: store ? store.depsInstalled : false
  readonly property bool depsChecking: store ? store.depsChecking : true
  readonly property bool installing: store ? store.installing : false
  readonly property string installError: store ? store.installError : ""
  readonly property var requiredPackages: store ? store.requiredPackages : []

  function fail(message) { if (store) store.error = message }
  function ensureRange() { if (store) store.ensureRange(anchor) }
  function invalidate() { if (store) store.invalidate() }
  function refreshNow() { if (store) store.refreshNow(anchor) }
  function setConfig(key, value) { if (store) store.setConfig(key, value) }
  function calendarEnabled(cal) { return store ? store.calendarEnabled(cal) : true }
  function toggleCalendar(cal) { if (store) store.toggleCalendar(cal) }
  function login() { if (store) store.login() }
  function installDeps() { if (store) store.installDeps() }

  // Routing: no account means there is nothing else to show. Once one
  // exists, hand back to the calendar unless settings were asked for.
  function route(initial) {
    if (!connected) view = "settings"
    else if (initial || (view === "settings" && !settingsPinned)) view = cfg.defaultView || "week"
  }
  onStoreChanged: if (store) route(true)

  Connections {
    target: root.store
    function onSynced() { root.route(false) }
    function onStatusRead() { root.route(true) }
  }

  // ---------------------------------------------------------------- state
  property string view: "week"                  // day | week | month | settings
  property date anchor: new Date()              // the date the view is built around
  property date now: new Date()

  // Set when the user asks for settings, so a background refresh never yanks
  // them out of it — and cleared when they pick a calendar view, so the
  // not-connected screen can hand back over once an account appears.
  property bool settingsPinned: false
  property var editing: null                    // event under the editor, or null

  readonly property int weekStart: cfg.weekStart === undefined ? 1 : cfg.weekStart
  readonly property int notifyMinutes: cfg.notifyMinutes === undefined ? 10 : cfg.notifyMinutes
  readonly property int dayStartHour: cfg.dayStartHour === undefined ? 7 : cfg.dayStartHour
  readonly property int refreshMinutes: Math.max(1, cfg.refreshMinutes || 5)
  readonly property bool hours12: cfg.hours12 === true
  readonly property bool connected: accounts.length > 0
  readonly property var nextEvent: Model.nextEvent(events, now)

  // ------------------------------------------------------------- palette
  //
  // Everything downstream reads these four, so a theme change moves the
  // whole panel at once and no child ever names a literal colour.
  readonly property color ink: bar ? bar.foreground : Color.popups.text
  readonly property string mono: bar ? bar.fontFamily : Style.font.family
  // Omarchy ships light themes as well as dark ones, and several choices
  // below only hold for one or the other.
  readonly property bool lightSurface: Model.isLightSurface(String(Color.popups.background))

  readonly property color hair: Util.alpha(ink, lightSurface ? 0.16 : 0.12)
  // Secondary and tertiary text. Kept well above the 3:1 floor a dark ground
  // needs — 45%/26% of the foreground looked refined and read as unfinished.
  readonly property color dim: Util.alpha(ink, 0.66)
  readonly property color faint: Util.alpha(ink, 0.44)

  // ---------------------------------------------------------- navigation
  readonly property var viewDays: view === "day"
    ? [Model.startOfDay(anchor)]
    : Model.weekDays(anchor, weekStart)

  readonly property string title: view === "settings"
    ? "SETTINGS"
    : Qt.formatDate(anchor, "MMMM").toUpperCase()

  readonly property string subtitle: {
    if (view === "settings") {
      if (!connected) return "NOT CONNECTED"
      var on = calendars.filter(function(c) { return !c.error && c.enabled }).length
      return accounts.length + (accounts.length === 1 ? " ACCOUNT" : " ACCOUNTS")
        + " · " + on + (on === 1 ? " CALENDAR" : " CALENDARS")
    }
    if (view === "month") return anchor.getFullYear() + ""
    if (view === "day") return Qt.formatDate(anchor, "dddd d").toUpperCase() + " · " + anchor.getFullYear()
    var days = viewDays
    return anchor.getFullYear() + " · WEEK " + Model.isoWeek(anchor)
      + " · " + Qt.formatDate(days[0], "d MMM").toUpperCase()
      + " – " + Qt.formatDate(days[6], "d MMM").toUpperCase()
  }

  readonly property bool onToday: view === "month"
    ? (anchor.getFullYear() === now.getFullYear() && anchor.getMonth() === now.getMonth())
    : (view === "day" ? Model.sameDay(anchor, now)
                      : Model.startOfWeek(anchor, weekStart).getTime() === Model.startOfWeek(now, weekStart).getTime())

  function step(direction) {
    if (view === "month") anchor = Model.addMonths(anchor, direction)
    else if (view === "day") anchor = Model.addDays(anchor, direction)
    else anchor = Model.addDays(anchor, direction * 7)
    ensureRange()
  }

  function goToday() {
    anchor = new Date()
    ensureRange()
  }

  function setView(next) {
    settingsPinned = next === "settings"
    if (next === view) return
    view = next
    ensureRange()
  }

  // ------------------------------------------------------------- editing
  function compose(start, allDay, inclusiveEnd) {
    var writable = calendars.filter(function(c) { return c.writable && c.enabled })
    if (!writable.length) { fail("No writable calendar is enabled."); return }

    // Default to the account's own calendar. Alphabetical order lands on
    // whatever shared calendar sorts first, which is never where someone
    // means to put a new event.
    var target = writable[0]
    for (var i = 0; i < writable.length; i++) {
      if (writable[i].primary) { target = writable[i]; break }
    }
    var begin = start || new Date(now.getFullYear(), now.getMonth(), now.getDate(), now.getHours() + 1, 0)
    // Drafts keep Google's exclusive all-day end internally because the same
    // editor also receives API events. The editor turns it back into the
    // inclusive date a person expects to see.
    var finish
    if (allDay === true) {
      var selected = Model.dayRange(begin, inclusiveEnd || begin)
      begin = selected.start
      finish = Model.addDays(selected.end, 1)
    } else {
      finish = new Date(begin.getTime() + 3600000)
    }
    editing = {
      id: "",
      account: target.account,
      calendarId: target.id,
      title: "",
      allDay: allDay === true,
      startAt: begin,
      endAt: finish,
      location: "",
      description: "",
      colorId: "",
      color: target.color,
      writable: true
    }
  }

  function composeNow() {
    open()
    compose(null, false)
  }

  function edit(ev) {
    if (!ev.writable) { fail("That calendar is read-only."); return }
    var copy = {}
    for (var k in ev) copy[k] = ev[k]
    editing = copy
  }

  function saveEvent(ev) {
    if (!store) return
    var payload = {
      id: ev.id,
      account: ev.account,
      calendarId: ev.calendarId,
      title: ev.title || "(no title)",
      allDay: ev.allDay,
      start: ev.allDay ? Model.dayKey(ev.startAt) : Model.rfc3339(ev.startAt),
      // The editor works in inclusive days; Google wants the exclusive one.
      end: ev.allDay ? Model.exclusiveEndDate(ev.endAt) : Model.rfc3339(ev.endAt)
    }
    // Only fields the editor actually changed travel: PATCH leaves the rest
    // alone, which is what keeps a description the single-line field could
    // not show from being flattened on every save.
    if ("location" in ev) payload.location = ev.location
    if ("description" in ev) payload.description = ev.description
    if ("colorId" in ev) payload.colorId = ev.colorId

    var draft = editing
    editing = null
    store.mutate("save", payload,
           function() { root.invalidate() },
           function() { editing = draft })       // failed: hand the text back
  }

  function deleteEvent(ev) {
    if (!store) return
    var draft = editing
    editing = null
    store.mutate("delete", { account: ev.account, calendarId: ev.calendarId, id: ev.id },
           function() { root.invalidate() },
           function() { editing = draft })
  }

  // ---------------------------------------------------------- lifecycle
  function open() {
    root.controller.show()
    now = new Date()
    if (!everSynced || !onToday) goToday()
    else ensureRange()
  }

  function close() {
    editing = null
    root.controller.hide()
  }

  function toggle() { opened ? close() : open() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: root.now = date
  }


  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(1400))
    contentHeight: panel.fittedContentHeight(Style.space(760))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      blocked: root.editing !== null
      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.step(dx)
        if (dy !== 0) root.step(dy)
      }
      onActivateRequested: root.goToday()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t).toLowerCase()
        if (key === "d") root.setView("day")
        else if (key === "w") root.setView("week")
        else if (key === "m") root.setView("month")
        else if (key === ",") root.setView("settings")
        else if (key === "t") root.goToday()
        else if (key === "n") root.compose(null, false)
        else if (key === "r") root.refreshNow()
        else if (key === "[") root.step(-1)
        else if (key === "]") root.step(1)
      }

      Column {
        anchors.fill: parent
        spacing: Style.space(10)

        Header {
          id: header
          width: parent.width
          panel: root
        }

        Rectangle {
          width: parent.width
          height: 1
          color: root.hair
        }

        // ---- Body. One Loader, cross-faded on every view change, so the
        //      whole surface reads as one object being turned rather than
        //      four panes being swapped.
        Item {
          width: parent.width
          height: parent.height - header.height - Style.space(10) * 2 - 1

          Loader {
            id: body
            anchors.fill: parent
            sourceComponent: root.view === "settings" ? settingsView
                           : root.view === "month" ? monthView
                           : timeGrid

            // The fade is driven from onLoaded alone. Resetting opacity from
            // an onViewChanged handler races the reload the same view change
            // triggers, and loses often enough to show a blank panel.
            opacity: 0
            onLoaded: fade.restart()

            NumberAnimation {
              id: fade
              target: body
              property: "opacity"
              from: 0
              to: 1
              duration: 160
              easing.type: Easing.OutCubic
            }
          }

          // A first fetch across a dozen calendars takes a moment, and an
          // empty grid is indistinguishable from a broken one. Say which.
          Column {
            anchors.centerIn: parent
            spacing: Style.space(6)
            visible: root.view !== "settings" && root.events.length === 0
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 200 } }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.busy || !root.everSynced ? "󰃭" : "󰃰"
              color: root.faint
              font.family: root.mono
              font.pixelSize: Style.font.display
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.busy || !root.everSynced
                ? "Loading your calendars…"
                : "Nothing scheduled"
              color: root.dim
              font.family: root.mono
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }

      Component { id: monthView; MonthView { panel: root } }
      Component { id: timeGrid; TimeGrid { panel: root } }
      Component { id: settingsView; SettingsView { panel: root } }

      // ---- Editor. A scrim over the calendar rather than a second window:
      //      the event you are editing stays in the context it came from.
      Loader {
        anchors.fill: parent
        active: root.editing !== null
        sourceComponent: EventEditor { panel: root }
        z: 40
      }
    }
  }
}

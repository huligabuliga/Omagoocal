import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The plugin's data and every process that produces it, loaded once per
// shell as a service. A bar exists per monitor and each bar hosts its own
// panel; without this, two monitors meant two backends fetching the same
// calendars and two copies of every notification.
//
// All Google traffic goes through `omagoocal`; this file never speaks
// HTTP. One `sync` subprocess per refresh returns accounts, calendars and
// events together. Panels read the properties below and call the functions;
// nothing here knows what a view is.
Item {
  id: store

  // The backend ships inside the plugin, so a clone of the repo is the whole
  // thing — nothing to put on PATH before it works.
  // resolvedUrl percent-encodes, so a home directory with a space in it
  // must be decoded before it can be executed.
  readonly property string backend:
    decodeURIComponent(Qt.resolvedUrl("omagoocal").toString()).replace(/^file:\/\//, "")
  // Run through the system interpreter by absolute path rather than executing
  // the script: the same fixed interpreter the shebang names, but it no
  // longer matters whether a clone preserved the executable bit.
  // -I: isolated mode — PYTHON* environment variables and the user site are
  // ignored, and the script's own directory is not put on sys.path.
  // -X utf8: stdin/stdout are UTF-8 regardless of locale.
  readonly property var backendCmd: ["/usr/bin/python3", "-I", "-X", "utf8", backend]

  // Every process that will hold a Google access token runs with an explicit
  // minimal environment: only what the interpreter needs to find our state
  // directory and the session bus. Under clearEnvironment, null means "pass
  // the system's value", so nothing else from the shell — PYTHONPATH,
  // LD_PRELOAD, a proxy — can reach it. No exception: the sign-in window is
  // a separate program the shell opens itself, so the helper never needs
  // a display.
  component BackendProcess: Process {
    clearEnvironment: true
    environment: ({
      HOME: null,
      XDG_RUNTIME_DIR: null,
      DBUS_SESSION_BUS_ADDRESS: null
    })
    // Set by whoever kills the process (deadline, output ceiling) so the exit
    // handler drops the partial output instead of reporting it as junk.
    property bool killed: false
    // Quickshell emits `exited` only for a process that ran. One whose
    // interpreter could not be executed goes straight from running to not
    // running, and a handler waiting on `exited` would wait forever.
    property bool sawExit: false
    signal failedToStart()
    onRunningChanged: {
      if (running) return
      var ran = sawExit
      sawExit = false
      if (!ran) { killed = false; failedToStart() }
    }
    onExited: sawExit = true
  }

  // ---------------------------------------------------------------- state
  property date now: new Date()
  property var events: []
  property var calendars: []
  property var accounts: []
  property var cfg: ({})
  property bool busy: false
  property string error: ""
  property bool everSynced: false

  readonly property int notifyMinutes: cfg.notifyMinutes === undefined ? 10 : cfg.notifyMinutes
  readonly property int refreshMinutes: Math.max(1, cfg.refreshMinutes || 5)
  readonly property bool hours12: cfg.hours12 === true
  readonly property bool connected: accounts.length > 0

  // Fired after a sync or the startup status has landed, so a panel can
  // decide which view to stand on.
  signal synced()
  signal statusRead()

  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: { store.now = date; store.checkNotifications() }
  }

  // ---- Dependencies. GNOME Online Accounts is what makes this plugin
  //      installable by anyone: it carries the distro's own Google OAuth
  //      client, so no user ever creates a Google Cloud project and the
  //      plugin never needs Google's verification review.
  //
  //      The install follows the Omarchy convention: Omarchy's own installer
  //      in a visible floating terminal (which is also where its password
  //      prompt is answered), then a poll of pacman until the packages land.
  //
  //      Every executable here is an absolute path and no shell of ours is
  //      involved: the probe is pacman itself, and the install hands the
  //      terminal wrapper one fixed command.
  property bool depsInstalled: false
  property bool depsChecking: true
  property bool installing: false
  property string installError: ""

  readonly property var requiredPackages: ["gnome-online-accounts", "gnome-online-accounts-gtk", "python"]
  readonly property string pacman: "/usr/bin/pacman"
  readonly property string omarchyBin: "/usr/share/omarchy/bin"

  function checkDeps() {
    if (depsProc.running) return
    depsChecking = true
    depsProc.command = [pacman, "-Q"].concat(requiredPackages)
    depsProc.running = true
  }

  function installDeps() {
    installing = true
    installError = ""
    installProc.command = [
      omarchyBin + "/omarchy-launch-floating-terminal-with-presentation",
      omarchyBin + "/omarchy-pkg-add " + requiredPackages.join(" ")]
    installProc.startDetached()
    installPoll.restart()
    installTimeout.restart()
  }

  // ---------------------------------------------------------------- data
  //
  // A month either side of the anchor, so paging a week at a time almost
  // never costs a round trip and month view is always fully populated.
  property date anchor: new Date()   // the last date a panel asked for
  property string loadedKey: ""
  property string pendingKey: ""     // promoted to loadedKey only once it lands

  function rangeStart() { return Model.addDays(new Date(anchor.getFullYear(), anchor.getMonth(), 1), -14) }
  function rangeEnd() { return Model.addDays(new Date(anchor.getFullYear(), anchor.getMonth() + 1, 1), 14) }

  function ensureRange(date) {
    if (date) anchor = date
    var key = anchor.getFullYear() + "-" + anchor.getMonth()
    if (key === loadedKey && everSynced) return
    pendingKey = key
    sync()
  }

  // What is on screen is no longer trusted: fetch the range again.
  function invalidate() {
    loadedKey = ""
    ensureRange()
  }

  property bool syncQueued: false
  property bool forceFresh: false

  function sync() {
    // A refresh asked for while one is in flight is queued, not dropped: the
    // dropped one is always the one carrying the change the user just made.
    if (busy) { syncQueued = true; return }
    busy = true
    var argv = backendCmd.concat(["sync", Model.rfc3339(rangeStart()), Model.rfc3339(rangeEnd())])
    if (forceFresh) argv.push("fresh")
    forceFresh = false
    syncProc.command = argv
    syncProc.running = true
  }

  // The refresh button means "I don't trust what I see": skip every cache.
  function refreshNow(date) {
    forceFresh = true
    if (date) anchor = date
    invalidate()
  }

  // `fromCache` paints the last known result without claiming the range is
  // loaded, so the real sync that follows still runs.
  function applySync(payload, fromCache) {
    if (payload.error) { error = payload.error; return }
    var status = payload.status || {}
    // Never let a sync that started before an unsaved edit overwrite it, and
    // never let the startup snapshot — possibly older than config.json —
    // overwrite what status just read.
    if (!fromCache && !configProc.running && !configDirty) {
      var incoming = status.config || {}
      if (calendarsLocal) incoming.calendars = cfg.calendars
      if (barCalendarsLocal) incoming.barCalendars = cfg.barCalendars
      cfg = incoming
    }
    accounts = status.accounts || []
    calendars = payload.calendars || []
    events = Model.decorateAll(payload.events)

    // Per-calendar failures ride along inside the event list rather than
    // failing the whole refresh; one revoked account should not blank the
    // other three.
    var trouble = (payload.events || []).filter(function(e) { return e && e.error })
    error = trouble.length ? trouble[0].calendar + ": " + trouble[0].error : ""
    if (fromCache) return
    everSynced = true
    loadedKey = pendingKey         // a failed fetch leaves the month retryable
    synced()
  }

  // Payloads travel on stdin, not argv: argv is readable by every local
  // process, and these carry event text and settings. Same pattern Omarchy's
  // network panel uses for Wi-Fi secrets.
  property var mutationQueue: []

  function mutate(command, payload, onDone, onFail) {
    mutationQueue.push({ command: command, payload: payload, onDone: onDone || null, onFail: onFail || null })
    pumpMutations()
  }

  // One process, one mutation at a time: a delete followed at once by a
  // create must not overwrite each other's command or callback. The guard
  // is our own flag, not the process's `running`: Quickshell may start a
  // process later than it was asked to (during a reload, for one), and two
  // jobs queued inside that window would otherwise share one process.
  property bool mutating: false

  function pumpMutations() {
    if (mutating || mutationQueue.length === 0) return
    mutating = true
    var job = mutationQueue.shift()
    busy = true
    mutateProc.pending = job.onDone
    mutateProc.failed = job.onFail
    mutateProc.payload = JSON.stringify(job.payload)
    mutateProc.command = backendCmd.concat([job.command])
    mutateProc.running = true
  }

  // ---- Config writes.
  //
  // The shell is the owner of this config while it runs, so every write
  // sends the whole document and the last one wins. A control must never wait
  // on a subprocess to show the state the user just chose, so `cfg` moves
  // first and the disk catches up.
  property bool configDirty: false
  property bool refreshAfterConfig: false
  // Once the user has touched a toggle, we are the authority on the calendar
  // map for the rest of the session. A sync that was already in flight when
  // they clicked would otherwise hand back the old value and bounce the
  // switch — which is exactly what "I have to click it twice" looks like.
  property bool calendarsLocal: false
  // Same, for the bar map. Kept apart so touching one switch does not make us
  // the authority on the other.
  property bool barCalendarsLocal: false

  function setConfig(key, value) {
    var next = {}
    for (var k in cfg) next[k] = cfg[k]
    next[key] = value
    cfg = next
    persistConfig()
  }

  function persistConfig() {
    if (configProc.running) { configDirty = true; return }
    configDirty = false
    configProc.payload = JSON.stringify(cfg)
    configProc.command = backendCmd.concat(["setall"])
    configProc.running = true
  }

  function calendarKey(cal) { return Model.calendarKey(cal.account, cal.id) }

  // Read from the local config, not from the last sync: this is what makes a
  // toggle land on the first click instead of the third.
  function calendarEnabled(cal) {
    var value = (cfg.calendars || {})[calendarKey(cal)]
    return value !== false
  }

  function toggleCalendar(cal) {
    var map = {}
    for (var k in (cfg.calendars || {})) map[k] = cfg.calendars[k]
    map[calendarKey(cal)] = !calendarEnabled(cal)
    calendarsLocal = true
    refreshAfterConfig = true
    setConfig("calendars", map)
  }

  // ---- Which calendars the bar label may name.
  //
  // Purely a display filter over events we already hold, so unlike the
  // calendar switch above it costs no refetch: no `refreshAfterConfig`.
  readonly property var barCalendars: cfg.barCalendars || ({})

  function calendarInBar(cal) {
    return barCalendars[calendarKey(cal)] !== false
  }

  function toggleBarCalendar(cal) {
    var map = {}
    for (var k in barCalendars) map[k] = barCalendars[k]
    map[calendarKey(cal)] = !calendarInBar(cal)
    barCalendarsLocal = true
    setConfig("barCalendars", map)
  }

  // Sign-in is GOA's window, showing Google's own consent screen. The shell
  // opens that window directly by absolute path — the token-bearing helper
  // is never run with a display environment — and tells the helper to drop
  // its caches, then watches for the account to appear. The package that
  // ships the window is a checked dependency, so the path is fixed.
  readonly property string accountWindow: "/usr/bin/gnome-online-accounts-gtk"

  function login() {
    error = ""
    Quickshell.execDetached([accountWindow])
    loginProc.running = true
    accountWatch.restart()
  }

  // ------------------------------------------------------- notifications
  //
  // ponytail: fired ids live in memory, so restarting the shell inside an
  // event's lead window can repeat one notification. Persist the set if that
  // ever becomes more than a curiosity.
  property var fired: ({})

  function checkNotifications() {
    var due = Model.dueNotifications(events, now, notifyMinutes, fired)
    for (var i = 0; i < due.length; i++) {
      var ev = due[i]
      fired[ev.id] = true
      // "--" so a title beginning with "-" is text, not an option.
      Quickshell.execDetached(["/usr/bin/notify-send", "-a", "Calendar", "-u", "normal",
        "-t", "12000", "-i", "office-calendar", "--",
        Model.escapeMarkup(ev.title),
        Model.escapeMarkup(Model.relative(ev.startAt, now) + " · " + Model.rangeLabel(ev, hours12)
          + (ev.location ? "\n" + ev.location : ""))])
    }
  }

  // ---------------------------------------------------------- lifecycle
  Component.onCompleted: {
    statusProc.running = true        // config before first paint, so a
    snapshotProc.running = true      // panel opens on the user's default view
    checkDeps()
  }

  // Last sync, on disk. Painted at startup so a shell restart shows last
  // week's state at once rather than an empty grid, and the bar has a next
  // event to name from the first frame. Read by the backend, not by QML: the
  // backend opens state files no-follow, relative to a validated directory,
  // with a size ceiling — the shell never opens a path itself.
  BackendProcess {
    id: snapshotProc
    command: store.backendCmd.concat(["snapshot"])
    stdout: BackendOutput { id: snapshotOut; proc: snapshotProc }
    onStarted: snapshotOut.reset()
    onExited: function(code) {
      var text = snapshotOut.take()
      if (killed) { killed = false; return }
      if (store.everSynced || text === "") return
      try {
        var snap = JSON.parse(text)
        // Only if the saved window still covers the one we are about to
        // ask for; otherwise the fetch alone is the honest picture.
        if (snap.payload && Model.parseStamp(snap.timeMin) <= store.rangeStart()
            && Model.parseStamp(snap.timeMax) >= store.rangeEnd())
          store.applySync(snap.payload, true)
      } catch (e) { /* no snapshot yet, or a stale shape: the sync covers it */ }
    }
  }

  Timer {
    // Polling, not push: Google's watch channels need a public callback URL,
    // which a laptop on someone's desk does not have.
    interval: store.refreshMinutes * 60000
    running: store.connected
    repeat: true
    onTriggered: store.invalidate()
  }

  // Every backend process gets a hard deadline. The backend alarms itself
  // at 120s; this is the outer wall for the case where it cannot, so a hung
  // helper is killed, never waited on.
  component Deadline: Timer {
    property var target
    property int seconds
    interval: seconds * 1000
    running: target ? target.running === true : false
    onTriggered: {
      if (!target || !target.running) return
      if (target.killed !== undefined) target.killed = true
      store.error = "The backend stopped answering and was terminated."
      target.signal(9)
    }
  }

  Deadline { target: syncProc; seconds: 150 }
  Deadline { target: statusProc; seconds: 30 }
  Deadline { target: snapshotProc; seconds: 30 }
  Deadline { target: mutateProc; seconds: 90 }
  Deadline { target: configProc; seconds: 30 }
  Deadline { target: loginProc; seconds: 30 }
  Deadline { target: depsProc; seconds: 30 }

  // The producer caps its own output at 16 MiB; this is the consumer-side
  // ceiling so a misbehaving helper can never fill the shell's memory. It
  // counts UTF-16 units, which is what a QString's memory is proportional
  // to, so the buffer can never exceed twice this many bytes.
  readonly property int maxBackendOutput: 20 * 1024 * 1024

  readonly property string startFailure: "The backend could not be started. Is python installed?"

  // Backend output arrives line by line (the backend frames its JSON at
  // token boundaries), and is counted as it arrives: past the ceiling the
  // process is killed and what was buffered is dropped — never collected
  // in full first, which is what StdioCollector would do.
  component BackendOutput: SplitParser {
    splitMarker: "\n"
    property var proc
    property var lines: []
    property int units: 0
    property bool overflowed: false
    onRead: function(data) {
      if (overflowed) return
      units += data.length
      if (units > store.maxBackendOutput) {
        overflowed = true
        lines = []
        store.error = "Backend output exceeded the size limit."
        if (proc && proc.running) {
          if (proc.killed !== undefined) proc.killed = true
          proc.signal(9)
        }
        return
      }
      lines.push(data)
    }
    function take() {
      var text = overflowed ? "" : lines.join("")
      reset()
      return text
    }
    function reset() { lines = []; units = 0; overflowed = false }
  }

  BackendProcess {
    id: syncProc
    stdout: BackendOutput { id: syncOut; proc: syncProc }
    onStarted: syncOut.reset()
    onFailedToStart: { syncOut.reset(); store.busy = false; store.error = store.startFailure }
    onExited: function(code) {
      store.busy = false
      if (killed) { killed = false; syncOut.take(); return }
      var text = syncOut.take()
      if (code !== 0 && text === "") { store.error = "Backend exited with status " + code; return }
      try { store.applySync(JSON.parse(text || "{}")) }
      catch (e) { store.error = "Backend returned junk: " + text.substring(0, 120) }
      store.checkNotifications()
      if (store.syncQueued) { store.syncQueued = false; Qt.callLater(store.sync) }
    }
  }

  BackendProcess {
    id: statusProc
    command: store.backendCmd.concat(["status"])
    stdout: BackendOutput { id: statusOut; proc: statusProc }
    onStarted: statusOut.reset()
    onExited: function(code) {
      var text = statusOut.take()
      if (killed) { killed = false; return }
      if (text === "") return
      try {
        var status = JSON.parse(text)
        store.cfg = status.config || {}
        store.accounts = status.accounts || []
        store.statusRead()
        // Until now the first fetch waited for a click or the 5-minute
        // timer, so the bar named no event for minutes after a restart.
        if (store.connected) store.ensureRange()
      } catch (e) { /* first run, nothing stored yet */ }
    }
  }

  BackendProcess {
    id: mutateProc
    property var pending: null
    property var failed: null
    property string payload: ""
    stdinEnabled: true
    stdout: BackendOutput { id: mutateOut; proc: mutateProc }
    onStarted: { mutateOut.reset(); write(payload + "\n"); payload = "" }
    onFailedToStart: { payload = ""; settle({ error: store.startFailure }) }
    onExited: function(code) {
      var result = {}
      if (killed) { killed = false; mutateOut.take(); result = { error: store.error } }
      else try { result = JSON.parse(mutateOut.take() || "{}") } catch (e) { result = { error: "Backend returned junk." } }
      settle(result)
    }
    // One exit path for a mutation, however it ended: report, fire the
    // right callback, release the queue.
    function settle(result) {
      store.busy = false
      store.mutating = false
      if (result.error) { store.error = result.error; if (failed) failed() }
      else if (pending) pending()
      pending = null
      failed = null
      Qt.callLater(store.pumpMutations)
    }
  }

  BackendProcess {
    id: configProc
    property string payload: ""
    stdinEnabled: true
    stdout: BackendOutput { id: configOut; proc: configProc }
    onStarted: { configOut.reset(); write(payload + "\n"); payload = "" }
    onFailedToStart: { payload = ""; store.configDirty = false; store.error = "Settings were not saved: " + store.startFailure }
    onExited: {
      var result = {}
      if (killed) { killed = false; configOut.take(); result = { error: store.error } }
      else try { result = JSON.parse(configOut.take() || "{}") } catch (e) {}
      if (result.error) store.error = "Settings were not saved: " + result.error
      if (store.configDirty) { store.persistConfig(); return }
      if (!store.refreshAfterConfig) return
      store.refreshAfterConfig = false
      store.invalidate()
    }
  }

  Process {
    id: depsProc
    onExited: function(code) {
      store.depsChecking = false
      store.depsInstalled = code === 0
      if (code !== 0) return
      store.installing = false
      installPoll.stop()
      installTimeout.stop()
      store.invalidate()
    }
  }

  Process { id: installProc }

  Timer {
    id: installPoll
    interval: 2000
    repeat: true
    running: store.installing && !store.depsInstalled
    onTriggered: store.checkDeps()
  }

  Timer {
    id: installTimeout
    interval: 300000
    onTriggered: {
      if (!store.installing) return
      store.installing = false
      installPoll.stop()
      store.installError = "Still waiting on the installer. Check the Omarchy terminal."
    }
  }

  // After the GOA window opens, the account shows up asynchronously. Poll
  // briefly rather than making the user press refresh — with `status`, one
  // D-Bus call and no network, so a three-minute wait is not sixty full
  // syncs against Google. The first status that shows an account triggers
  // the one sync that is needed.
  Timer {
    id: accountWatch
    interval: 3000
    repeat: true
    property int ticks: 0
    onRunningChanged: if (running) ticks = 0
    onTriggered: {
      ticks++
      if (store.connected || ticks > 60) { stop(); return }
      if (!statusProc.running) statusProc.running = true
    }
  }

  BackendProcess {
    id: loginProc
    command: store.backendCmd.concat(["forget"])
    stdout: BackendOutput { id: loginOut; proc: loginProc }
    onStarted: loginOut.reset()
    onExited: function(code) {
      var result = {}
      try { result = JSON.parse(loginOut.take() || "{}") } catch (e) {}
      if (result.error) store.error = result.error
    }
  }
}

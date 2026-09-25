// Pure date, layout, and formatting helpers for the Omagoocal panel.
// No QML imports: everything here is testable with plain JS.

.pragma library

var DAY_MS = 86400000

function startOfDay(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
function addMonths(d, n) { return new Date(d.getFullYear(), d.getMonth() + n, 1) }
function sameDay(a, b) { return dayKey(a) === dayKey(b) }

function pad(n) { return (n < 10 ? "0" : "") + n }

function dayKey(d) {
  return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}

// RFC 3339 with the local UTC offset. Google rejects a naive timestamp, and
// sending UTC instead would silently shift every event the user types.
function rfc3339(d) {
  var off = -d.getTimezoneOffset()
  var sign = off < 0 ? "-" : "+"
  off = Math.abs(off)
  return dayKey(d) + "T" + pad(d.getHours()) + ":" + pad(d.getMinutes()) + ":00"
    + sign + pad(Math.floor(off / 60)) + ":" + pad(off % 60)
}

// Google hands back all-day dates as bare "YYYY-MM-DD". `new Date()` reads
// those as UTC midnight, which lands on the previous day west of Greenwich.
function parseStamp(value) {
  var text = String(value || "")
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) {
    var p = text.split("-")
    return new Date(+p[0], +p[1] - 1, +p[2])
  }
  return new Date(text)
}

function startOfWeek(d, weekStart) {
  var delta = (d.getDay() - weekStart + 7) % 7
  return addDays(startOfDay(d), -delta)
}

function weekDays(anchor, weekStart) {
  var first = startOfWeek(anchor, weekStart)
  var out = []
  for (var i = 0; i < 7; i++) out.push(addDays(first, i))
  return out
}

// Six rows always, so the grid never changes height between months — a
// calendar that resizes as you page through it is a calendar that fights you.
function monthGrid(year, month, weekStart) {
  var first = startOfWeek(new Date(year, month, 1), weekStart)
  var weeks = []
  for (var w = 0; w < 6; w++) {
    var row = []
    for (var i = 0; i < 7; i++) row.push(addDays(first, w * 7 + i))
    weeks.push(row)
  }
  return weeks
}

// The label for one date. Day view has a single column, so an index into the
// week order would always say "MON".
function weekdayLabel(date) {
  return ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"][date.getDay()]
}

function weekdayLabels(weekStart) {
  var names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
  var out = []
  for (var i = 0; i < 7; i++) out.push(names[(weekStart + i) % 7])
  return out
}

function isoWeek(d) {
  var t = new Date(d.getFullYear(), d.getMonth(), d.getDate())
  t.setDate(t.getDate() + 3 - ((t.getDay() + 6) % 7))
  var week1 = new Date(t.getFullYear(), 0, 4)
  return 1 + Math.round(((t - week1) / DAY_MS - 3 + ((week1.getDay() + 6) % 7)) / 7)
}

// ---------------------------------------------------------------- events

function decorate(ev) {
  var out = {}
  for (var k in ev) out[k] = ev[k]
  out.startAt = parseStamp(ev.start)
  out.endAt = parseStamp(ev.end)
  // A zero-length event still needs a body to draw.
  if (out.endAt <= out.startAt && !ev.allDay)
    out.endAt = new Date(out.startAt.getTime() + 1800000)
  return out
}

function decorateAll(list) {
  var out = []
  for (var i = 0; i < (list || []).length; i++) {
    if (!list[i] || list[i].error) continue
    var ev = decorate(list[i])
    // A timestamp the API sent that does not parse would become NaN
    // geometry and an unsortable entry; it is dropped, not drawn.
    if (isNaN(ev.startAt.getTime()) || isNaN(ev.endAt.getTime())) continue
    out.push(ev)
  }
  out.sort(function (a, b) { return a.startAt - b.startAt })
  return out
}

function onDay(events, day) {
  var from = startOfDay(day), to = addDays(from, 1)
  var out = []
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    // All-day events carry an exclusive end date, so the half-open test is
    // the same one timed events want.
    if (e.startAt < to && e.endAt > from) out.push(e)
  }
  return out
}

function splitAllDay(list) {
  var timed = [], allDay = []
  for (var i = 0; i < list.length; i++) {
    // Anything spanning a day boundary reads as a banner, not as a block on
    // the hour grid — a 3-day trip is not a 72-hour appointment.
    var spans = list[i].endAt - list[i].startAt >= DAY_MS
    ;(list[i].allDay || spans ? allDay : timed).push(list[i])
  }
  return { timed: timed, allDay: allDay }
}

// Events that transitively overlap in time, as runs. Input must be sorted by
// start. This is the unit both lane assignment and overflow work on.
function overlapRuns(events) {
  var runs = [], current = [], reach = null
  for (var i = 0; i < events.length; i++) {
    var e = events[i]
    if (current.length && e.startAt >= reach) {
      runs.push(current)
      current = []
      reach = null
    }
    current.push(e)
    if (reach === null || e.endAt > reach) reach = e.endAt
  }
  if (current.length) runs.push(current)
  return runs
}

// Greedy interval colouring inside one run: an event takes the leftmost lane
// whose previous occupant has already ended.
function assignLanes(run) {
  var columns = [], items = []
  for (var i = 0; i < run.length; i++) {
    var lane = 0
    while (lane < columns.length && columns[lane] > run[i].startAt) lane++
    columns[lane] = run[i].endAt

    var item = {}
    for (var k in run[i]) item[k] = run[i][k]
    item.lane = lane
    items.push(item)
  }
  return { items: items, lanes: columns.length }
}

// Lay a day's timed events into lanes.
//
// `maxLanes` caps how thin a column may be sliced. A field calendar routinely
// books nine jobs into the same two-hour slot, and nine 7px slivers are not a
// calendar. Past the cap the surplus collapses into "+N" markers that open the
// day view.
//
// Crucially the surplus is re-grouped by its own overlap before being marked,
// so one crowded morning cannot swallow an unrelated afternoon event that
// merely shares a chain of overlaps with it.
function layout(dayEvents, maxLanes) {
  var sorted = dayEvents.slice().sort(function (a, b) {
    return (a.startAt - b.startAt) || (b.endAt - a.endAt)
  })

  var out = []
  var runs = overlapRuns(sorted)

  for (var r = 0; r < runs.length; r++) {
    var laid = assignLanes(runs[r])

    if (!maxLanes || laid.lanes <= maxLanes) {
      for (var i = 0; i < laid.items.length; i++) {
        laid.items[i].lanes = laid.lanes
        out.push(laid.items[i])
      }
      continue
    }

    var visible = maxLanes - 1        // the last lane belongs to the markers
    var hidden = []
    for (var j = 0; j < laid.items.length; j++) {
      var item = laid.items[j]
      item.lanes = maxLanes
      if (item.lane < visible) out.push(item)
      else hidden.push(item)
    }

    var groups = overlapRuns(hidden)
    for (var g = 0; g < groups.length; g++) {
      var group = groups[g]
      var from = group[0].startAt, to = group[0].endAt
      for (var h = 1; h < group.length; h++) {
        if (group[h].startAt < from) from = group[h].startAt
        if (group[h].endAt > to) to = group[h].endAt
      }
      out.push({
        id: "overflow-" + from.getTime(),
        overflow: true,
        count: group.length,
        title: "+" + group.length + " more",
        startAt: from,
        endAt: to,
        color: group[0].color,
        allDay: false,
        lane: visible,
        lanes: maxLanes
      })
    }
  }
  return out
}

// The last day a person would name for an all-day event. Google stores the
// end exclusively — a one-day event on the 16th ends on the 17th — but nobody
// says a one-day event "ends tomorrow". Editors must show, and take back, the
// inclusive day, or every save stretches the event by one.
function inclusiveEndDay(ev) {
  return ev.allDay ? addDays(ev.endAt, -1) : ev.endAt
}

// The value to send back to Google for that same field.
function exclusiveEndDate(day) {
  return dayKey(addDays(day, 1))
}

// Fraction of the day an event occupies, clipped to the day being drawn.
function dayBounds(ev, day) {
  var from = startOfDay(day)
  var to = addDays(from, 1)
  var start = Math.max(ev.startAt.getTime(), from.getTime())
  var end = Math.min(ev.endAt.getTime(), to.getTime())
  return {
    top: (start - from.getTime()) / DAY_MS,
    height: Math.max(end - start, 900000) / DAY_MS   // 15 min floor, so a
  }                                                  // short event stays legible
}

// ------------------------------------------------------------ formatting

function clockLabel(d, ampm) {
  if (!ampm) return pad(d.getHours()) + ":" + pad(d.getMinutes())
  var h = d.getHours() % 12
  return (h === 0 ? 12 : h) + ":" + pad(d.getMinutes()) + (d.getHours() < 12 ? "am" : "pm")
}

function hourLabel(h, ampm) {
  if (!ampm) return pad(h) + ":00"
  if (h === 0) return "12am"
  if (h === 12) return "12pm"
  return (h % 12) + (h < 12 ? "am" : "pm")
}

function rangeLabel(ev, ampm) {
  if (ev.allDay) return "All day"
  return clockLabel(ev.startAt, ampm) + " – " + clockLabel(ev.endAt, ampm)
}

function relative(target, now) {
  var mins = Math.round((target - now) / 60000)
  if (mins < -60) return "started " + Math.round(-mins / 60) + "h ago"
  if (mins < 0) return "started " + -mins + "m ago"
  if (mins === 0) return "now"
  if (mins < 60) return "in " + mins + "m"
  if (mins < 60 * 24) {
    var h = Math.floor(mins / 60)
    var m = mins % 60
    return "in " + h + "h" + (m ? " " + m + "m" : "")
  }
  return "in " + Math.round(mins / 1440) + "d"
}

// Rec. 601 luma, 0-255. Close enough for picking ink and for asking whether a
// theme is light; a full colour-space conversion buys nothing here.
function luma(hex) {
  var c = String(hex || "#000000").replace("#", "")
  if (c.length === 3) c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
  if (c.length === 8) c = c.substr(2)          // QML hands back #aarrggbb
  var r = parseInt(c.substr(0, 2), 16) || 0
  var g = parseInt(c.substr(2, 2), 16) || 0
  var b = parseInt(c.substr(4, 2), 16) || 0
  return (r * 299 + g * 587 + b * 114) / 1000
}

// Text drawn on top of a Google event colour.
function readableOn(hex) {
  return luma(hex) > 150 ? "#0b0d0e" : "#f2f4f4"
}

function isLightSurface(hex) {
  return luma(hex) > 128
}

// ------------------------------------------------------------ legibility
//
// Google's colours are chosen against a white web page, so a yellow calendar is
// invisible as a light theme's bar label. readableOn() picks ink to draw *on* a
// colour; this goes the other way and moves a colour toward the bar's ink until
// it can be read *against* the bar's ground, keeping the hue recognisable.

function _channels(hex) {
  var c = String(hex || "").replace("#", "")
  if (c.length === 8) c = c.substr(2)          // #aarrggbb
  if (c.length === 3) c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2]
  if (c.length !== 6) return null
  var r = parseInt(c.substr(0, 2), 16)
  var g = parseInt(c.substr(2, 2), 16)
  var b = parseInt(c.substr(4, 2), 16)
  if (isNaN(r) || isNaN(g) || isNaN(b)) return null
  return [r, g, b]
}

function _luminance(rgb) {
  var out = []
  for (var i = 0; i < 3; i++) {
    var v = rgb[i] / 255
    out.push(v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4))
  }
  return 0.2126 * out[0] + 0.7152 * out[1] + 0.0722 * out[2]
}

// WCAG contrast ratio between two colours; 21 when either cannot be parsed.
function contrast(a, b) {
  var x = _channels(a), y = _channels(b)
  if (x === null || y === null) return 21
  var la = _luminance(x), lb = _luminance(y)
  var hi = Math.max(la, lb), lo = Math.min(la, lb)
  return (hi + 0.05) / (lo + 0.05)
}

function _hex(v) {
  var s = Math.round(Math.max(0, Math.min(255, v))).toString(16)
  return s.length < 2 ? "0" + s : s
}

// The colour, moved toward `ink` until it clears `minimum` against `ground`.
function legible(colour, ground, ink, minimum) {
  minimum = minimum || 2.2
  var source = _channels(colour), target = _channels(ink)
  if (source === null || target === null) return ink
  if (contrast(colour, ground) >= minimum) return colour
  var current = source.slice()
  for (var step = 0; step < 12; step++) {
    for (var ch = 0; ch < 3; ch++) {
      current[ch] = current[ch] + (target[ch] - current[ch]) * 0.2
    }
    var candidate = "#" + _hex(current[0]) + _hex(current[1]) + _hex(current[2])
    if (contrast(candidate, ground) >= minimum) return candidate
  }
  return ink
}

// How hard to wash an event's colour into the surface behind it.
//
// A 16% tint of a saturated colour reads clearly on a dark ground and washes
// out to nearly nothing on a white one, which throws away the colour coding
// exactly where Omarchy has light themes. Light surfaces get a heavier wash.
function chipAlpha(lightSurface, hovered) {
  if (lightSurface) return hovered ? 0.42 : 0.26
  return hovered ? 0.30 : 0.16
}

// Which events deserve a notification right now.
//
// Split out from the panel so the decision — the part with edge cases — can
// be tested without a notification daemon in the loop. `fired` is the set of
// ids already announced and is updated in place by the caller.
function dueNotifications(events, now, leadMinutes, fired) {
  if (!leadMinutes) return []
  var horizon = now.getTime() + leadMinutes * 60000
  var due = []
  for (var i = 0; i < events.length; i++) {
    var ev = events[i]
    if (ev.allDay || ev.overflow || fired[ev.id]) continue
    var at = ev.startAt.getTime()
    // Already started, or still beyond the lead window: not now.
    if (at < now.getTime() || at > horizon) continue
    due.push(ev)
  }
  return due
}

// Event text is somebody else's text: anyone who shares a calendar or sends
// an invite chooses it. Most notification daemons render the body as Pango
// markup, so it is escaped rather than trusted.
function escapeMarkup(text) {
  return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

// Only a web link is handed to xdg-open. A file:// or custom-scheme value in
// an event's link field would otherwise reach whatever handler the desktop
// maps that scheme to.
function isWebLink(url) {
  return /^https:\/\/\S+$/i.test(String(url || ""))
}

// ------------------------------------------------------- bar visibility
//
// The key a per-calendar preference is stored under. Account as well as id,
// because the same shared calendar can be subscribed from two accounts and
// they are separately switchable.
function calendarKey(account, id) { return account + "\t" + id }

// Whether the bar label may name this event.
//
// `map` is the config's `barCalendars`: key -> bool, and *absent means
// shown*. A calendar that appears after the setting was last touched must
// not be silently muted — the failure mode of the other polarity is a
// meeting you never see.
function shownInBar(ev, map) {
  if (!map) return true
  return map[calendarKey(ev.account, ev.calendarId)] !== false
}

// The soonest event the bar is allowed to name. All-day events are skipped
// whatever their calendar: the bar answers "how long have I got", and a
// banner has no answer to give.
function nextEvent(events, now, barCalendars) {
  for (var i = 0; i < events.length; i++) {
    if (events[i].allDay) continue
    if (!shownInBar(events[i], barCalendars)) continue
    if (events[i].endAt > now) return events[i]
  }
  return null
}

// ------------------------------------------------------- input parsing
//
// Typed dates and times are a trust boundary: everything here returns null
// on anything it does not fully understand, and the editor refuses to save
// until both sides parse.

function parseDayInput(text) {
  var m = /^(\d{4})-(\d{1,2})-(\d{1,2})$/.exec(String(text).trim())
  if (!m) return null
  var year = +m[1], month = +m[2] - 1, day = +m[3]
  var d = new Date(year, month, day)
  // Rejects 2026-02-31, which Date would silently roll into March.
  if (d.getFullYear() !== year || d.getMonth() !== month || d.getDate() !== day) return null
  return d
}

// Forgiving on shape, strict on range: "9", "930", "9:30", "9pm", "9:30 PM".
function parseTimeInput(text) {
  var raw = String(text).trim().toLowerCase().replace(/\s+/g, "")
  var suffix = /(am|pm)$/.exec(raw)
  if (suffix) raw = raw.slice(0, -2)

  var hours, minutes
  var colon = /^(\d{1,2}):(\d{2})$/.exec(raw)
  var bare = /^(\d{1,2})$/.exec(raw)
  var packed = /^(\d{3,4})$/.exec(raw)
  if (colon) { hours = +colon[1]; minutes = +colon[2] }
  else if (bare) { hours = +bare[1]; minutes = 0 }
  else if (packed) { hours = +raw.slice(0, raw.length - 2); minutes = +raw.slice(-2) }
  else return null

  if (suffix) {
    if (hours < 1 || hours > 12) return null
    hours = hours % 12 + (suffix[1] === "pm" ? 12 : 0)
  }
  if (hours > 23 || minutes > 59) return null
  return { hours: hours, minutes: minutes }
}

function combine(day, time) {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate(), time.hours, time.minutes)
}

// Google's fixed event palette. Hardcoded rather than fetched: it has not
// changed in a decade, and a modal that has to wait on a request before it
// can show a colour picker is a worse trade than a stale swatch would be.
var EVENT_COLORS = [
  { id: "", name: "Calendar default", hex: "" },
  { id: "1", name: "Lavender", hex: "#7986cb" },
  { id: "2", name: "Sage", hex: "#33b679" },
  { id: "3", name: "Grape", hex: "#8e24aa" },
  { id: "4", name: "Flamingo", hex: "#e67c73" },
  { id: "5", name: "Banana", hex: "#f6bf26" },
  { id: "6", name: "Tangerine", hex: "#f4511e" },
  { id: "7", name: "Peacock", hex: "#039be5" },
  { id: "8", name: "Graphite", hex: "#616161" },
  { id: "9", name: "Blueberry", hex: "#3f51b5" },
  { id: "10", name: "Basil", hex: "#0b8043" },
  { id: "11", name: "Tomato", hex: "#d50000" }
]

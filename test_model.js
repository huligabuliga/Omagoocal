// Self-check for Model.js. Run: node test_model.js
const fs = require('fs')
const src = fs.readFileSync(__dirname + '/Model.js', 'utf8').replace('.pragma library', '')
const M = {}
// Every top-level function and var in Model.js is exported, so a new helper
// needs no edit here (and two branches adding one no longer conflict).
const names = [...src.matchAll(/^(?:function|var)\s+([A-Za-z_]\w*)/gm)].map(m => m[1])
new Function('exports', src + '\n;Object.assign(exports,{' + names.join(',') + '})')(M)

const eq = (a, b, m) => { if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(m + ': ' + JSON.stringify(a) + ' != ' + JSON.stringify(b)) }
const ok = (c, m) => { if (!c) throw new Error(m) }

// all-day strings must parse as local midnight, not UTC midnight
const d = M.parseStamp('2026-03-15')
eq([d.getFullYear(), d.getMonth(), d.getDate()], [2026, 2, 15], 'all-day parse is local')

// rfc3339 carries an offset Google will accept
ok(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:00[+-]\d{2}:\d{2}$/.test(M.rfc3339(new Date(2026, 0, 2, 9, 5))), 'rfc3339 shape')

// week start
eq(M.startOfWeek(new Date(2026, 8, 10), 1).getDate(), 7, 'Monday-start week of Thu 10 Sep 2026 begins Mon 7')
eq(M.startOfWeek(new Date(2026, 8, 10), 0).getDate(), 6, 'Sunday-start week begins Sun 6')

// month grid is always 6x7 and starts on the configured weekday
const grid = M.monthGrid(2026, 8, 1)
eq(grid.length, 6, 'six rows')
eq(grid[0].length, 7, 'seven columns')
ok(grid.every(w => w.every(day => day.getDay() !== undefined)), 'dates')
eq(grid[0][0].getDay(), 1, 'first cell is a Monday')
eq(M.weekdayLabels(1)[0], 'MON', 'labels follow week start')

eq(M.isoWeek(new Date(2026, 0, 1)), 1, 'ISO week of 1 Jan 2026')

// overlap layout
const raw = [
  { id: 'a', start: '2026-01-05T09:00:00', end: '2026-01-05T10:00:00' },
  { id: 'b', start: '2026-01-05T09:30:00', end: '2026-01-05T10:30:00' },
  { id: 'c', start: '2026-01-05T09:45:00', end: '2026-01-05T10:15:00' },
  { id: 'd', start: '2026-01-05T14:00:00', end: '2026-01-05T15:00:00' },
]
const laid = M.layout(M.decorateAll(raw))
const by = Object.fromEntries(laid.map(e => [e.id, e]))
eq([by.a.lane, by.b.lane, by.c.lane], [0, 1, 2], 'three overlapping events take three lanes')
eq(by.a.lanes, 3, 'cluster width is three')
eq(by.d.lanes, 1, 'a disjoint event gets its own full-width cluster')
eq(by.d.lane, 0, 'and resets to lane 0')

// non-overlapping events reuse a lane rather than growing the cluster
const chain = M.layout(M.decorateAll([
  { id: 'x', start: '2026-01-05T09:00:00', end: '2026-01-05T10:00:00' },
  { id: 'y', start: '2026-01-05T09:30:00', end: '2026-01-05T11:00:00' },
  { id: 'z', start: '2026-01-05T10:00:00', end: '2026-01-05T10:30:00' },
]))
eq(chain.find(e => e.id === 'z').lane, 0, 'z reuses the lane x vacated')
eq(chain.find(e => e.id === 'z').lanes, 2, 'cluster is two wide, not three')

// day filtering and all-day split
const week = M.decorateAll([
  { id: 'm', start: '2026-01-05T09:00:00', end: '2026-01-05T10:00:00' },
  { id: 'trip', allDay: true, start: '2026-01-05', end: '2026-01-08' },
  { id: 'other', start: '2026-01-09T09:00:00', end: '2026-01-09T10:00:00' },
])
const day5 = M.onDay(week, new Date(2026, 0, 5))
eq(day5.map(e => e.id).sort(), ['m', 'trip'], 'day 5 holds the meeting and the trip')
eq(M.onDay(week, new Date(2026, 0, 7)).map(e => e.id), ['trip'], 'trip spans mid-range days')
eq(M.onDay(week, new Date(2026, 0, 8)).map(e => e.id), [], 'exclusive end date excludes day 8')
const split = M.splitAllDay(day5)
eq([split.timed.map(e => e.id), split.allDay.map(e => e.id)], [['m'], ['trip']], 'split')

// bounds are clipped to the day and floored so short events stay visible
const b = M.dayBounds(week.find(e => e.id === 'trip'), new Date(2026, 0, 6))
eq([b.top, b.height], [0, 1], 'a mid-span all-day fills its day')
const tiny = M.dayBounds(M.decorateAll([{ start: '2026-01-05T09:00:00', end: '2026-01-05T09:05:00' }])[0], new Date(2026, 0, 5))
ok(tiny.height >= 900000 / 86400000 - 1e-9, 'short events get a floor')
ok(Math.abs(tiny.top - 9 / 24) < 1e-9, 'top is the fraction of the day')

eq(M.readableOn('#ffffff'), '#0b0d0e', 'dark ink on a light chip')
eq(M.readableOn('#3f51b5'), '#f2f4f4', 'light ink on a dark chip')

const now = new Date(2026, 0, 5, 8, 30)
eq(M.relative(new Date(2026, 0, 5, 9, 0), now), 'in 30m', 'relative minutes')
eq(M.relative(new Date(2026, 0, 5, 11, 15), now), 'in 2h 45m', 'relative hours')
eq(M.nextEvent(week, now).id, 'm', 'next event skips all-day banners')

// the bar's calendar filter: absent means shown, only an explicit false mutes
const barred = M.decorateAll([
  { id: 'pto', account: 'me@x', calendarId: 'team', start: '2026-01-05T09:00:00', end: '2026-01-05T09:30:00' },
  { id: 'mine', account: 'me@x', calendarId: 'primary', start: '2026-01-05T11:00:00', end: '2026-01-05T12:00:00' },
])
eq(M.calendarKey('me@x', 'team'), 'me@x\tteam', 'key is account and id, tab-joined')
eq(M.nextEvent(barred, now).id, 'pto', 'with no map the nearest event wins')
eq(M.nextEvent(barred, now, {}).id, 'pto', 'an empty map mutes nothing')
eq(M.nextEvent(barred, now, { 'me@x\tteam': false }).id, 'mine', 'a muted calendar is skipped')
eq(M.nextEvent(barred, now, { 'me@x\tteam': true }).id, 'pto', 'an explicit true is shown')
eq(M.nextEvent(barred, now, { 'other@x\tteam': false }).id, 'pto',
   'the key carries the account, so the same calendar id elsewhere is untouched')
eq(M.nextEvent(barred, now, { 'me@x\tteam': false, 'me@x\tprimary': false }), null,
   'everything muted names nothing')
ok(M.shownInBar(barred[0], undefined), 'no map at all is not a mute')
ok(!M.shownInBar(barred[0], { 'me@x\tteam': false }), 'and false is')

// typed input is a trust boundary: junk must come back null, not a wrong date
eq(M.parseDayInput('2026-02-31'), null, 'impossible date is rejected, not rolled over')
eq(M.parseDayInput('not a date'), null, 'junk rejected')
eq(M.parseDayInput('2026-2-3').getMonth(), 1, 'single-digit month accepted')
ok(M.parseDayInput('2026-02-28') !== null, 'valid date accepted')

eq(M.parseTimeInput('9'), { hours: 9, minutes: 0 }, 'bare hour')
eq(M.parseTimeInput('930'), { hours: 9, minutes: 30 }, 'packed')
eq(M.parseTimeInput('9:30'), { hours: 9, minutes: 30 }, 'colon')
eq(M.parseTimeInput('9pm'), { hours: 21, minutes: 0 }, 'pm')
eq(M.parseTimeInput('12am'), { hours: 0, minutes: 0 }, 'midnight')
eq(M.parseTimeInput('12pm'), { hours: 12, minutes: 0 }, 'noon')
eq(M.parseTimeInput('1430'), { hours: 14, minutes: 30 }, '24h packed')
eq(M.parseTimeInput('25:00'), null, 'hour out of range')
eq(M.parseTimeInput('9:75'), null, 'minute out of range')
eq(M.parseTimeInput('13pm'), null, 'pm needs a 12-hour clock')
eq(M.parseTimeInput(''), null, 'empty rejected')

const combined = M.combine(M.parseDayInput('2026-09-10'), M.parseTimeInput('14:05'))
eq([combined.getMonth(), combined.getDate(), combined.getHours(), combined.getMinutes()], [8, 10, 14, 5], 'combine')
eq(M.EVENT_COLORS.length, 12, 'eleven Google colours plus the calendar default')

// lane capping: past the cap, the surplus collapses into one marker
const crowd = M.decorateAll(Array.from({ length: 9 }, (_, i) => ({
  id: 'c' + i, start: '2026-01-05T10:00:00', end: '2026-01-05T12:00:00', color: '#111111'
})))
const capped = M.layout(crowd, 3)
const markers = capped.filter(e => e.overflow)
const real = capped.filter(e => !e.overflow)
eq(real.length, 2, 'two real events survive a cap of three')
eq(markers.length, 1, 'one marker')
eq(markers[0].count, 7, 'marker counts the seven it hides')
eq(markers[0].lane, 2, 'marker takes the last lane')
ok(capped.every(e => e.lanes === 3), 'every item reports the capped width')
ok(real.every(e => e.lane < 2), 'real events stay left of the marker')
eq(markers[0].startAt.getTime(), crowd[0].startAt.getTime(), 'marker spans the hidden events')

// under the cap nothing collapses
const roomy = M.layout(crowd.slice(0, 3), 3)
eq(roomy.filter(e => e.overflow).length, 0, 'exactly at the cap, nothing collapses')
eq(roomy.length, 3, 'all three shown')

// disjoint clusters are capped independently
const mixed = M.layout(M.decorateAll([
  { id: 'solo', start: '2026-01-05T08:00:00', end: '2026-01-05T09:00:00' },
  ...Array.from({ length: 5 }, (_, i) => ({ id: 'p' + i, start: '2026-01-05T10:00:00', end: '2026-01-05T11:00:00' }))
]), 2)
eq(mixed.find(e => e.id === 'solo').lanes, 1, 'the lone event keeps full width')
eq(mixed.filter(e => e.overflow)[0].count, 4, 'the crowded cluster collapses four')

// a crowded morning must not swallow an unrelated afternoon event that only
// shares a chain of overlaps with it
const chained = M.layout(M.decorateAll([
  { id: 'a1', start: '2026-01-05T10:00:00', end: '2026-01-05T12:00:00' },
  { id: 'a2', start: '2026-01-05T10:00:00', end: '2026-01-05T12:00:00' },
  { id: 'a3', start: '2026-01-05T10:00:00', end: '2026-01-05T12:00:00' },
  { id: 'a4', start: '2026-01-05T10:00:00', end: '2026-01-05T12:00:00' },
  { id: 'bridge', start: '2026-01-05T11:30:00', end: '2026-01-05T15:00:00' },
  { id: 'pm', start: '2026-01-05T14:30:00', end: '2026-01-05T16:00:00' },
]), 3)
const marks = chained.filter(e => e.overflow)
const shown = chained.filter(e => !e.overflow).map(e => e.id)
// The afternoon event does not overlap the crowded morning, so it must survive
// as a real event rather than being folded into the morning's marker.
ok(shown.includes('pm'), 'the unrelated afternoon event still renders: ' + shown)
ok(marks.every(m => m.endAt <= new Date(2026, 0, 5, 15, 0)), 'no marker reaches past the events it hides')
ok(marks.every(m => m.startAt.getHours() === 10), 'markers sit on the slot they stand for')
eq(marks.reduce((n, m) => n + m.count, 0), 3, 'exactly the surplus is hidden')

// the weekday label must come from the date, not from a column index
eq(M.weekdayLabel(new Date(2026, 8, 10)), 'THU', '10 Sep 2026 is a Thursday')
eq(M.weekdayLabel(new Date(2026, 8, 13)), 'SUN', 'and the 13th a Sunday')

// Date-range selection is direction-independent and remains calendar-based
// across row, month, year and daylight-saving boundaries.
let range = M.dayRange(new Date(2026, 8, 18, 16), new Date(2026, 8, 15, 9))
eq([M.dayKey(range.start), M.dayKey(range.end)], ['2026-09-15', '2026-09-18'], 'backward range is normalized')
range = M.dayRange(new Date(2026, 11, 31), new Date(2027, 0, 2))
eq([M.dayKey(range.start), M.dayKey(range.end)], ['2026-12-31', '2027-01-02'], 'range crosses a year')
ok(M.dayInRange(new Date(2027, 0, 1), range.start, range.end), 'middle day is selected')
ok(!M.dayInRange(new Date(2027, 0, 3), range.start, range.end), 'day after range is not selected')
range = M.dayRange(new Date(2026, 2, 7), new Date(2026, 2, 9))
eq(M.dayKey(M.addDays(range.start, 1)), '2026-03-08', 'range advances by calendar day at DST')
const draftEnd = M.addDays(range.end, 1)
const editorEnd = M.inclusiveEndDay({ allDay: true, endAt: draftEnd })
eq(M.exclusiveEndDate(editorEnd), '2026-03-10', 'selected range round-trips through editor and Google payload')

// notification decisions
const nowN = new Date(2026, 0, 5, 9, 0)
const feed = M.decorateAll([
  { id: 'soon', start: '2026-01-05T09:05:00', end: '2026-01-05T09:30:00' },
  { id: 'later', start: '2026-01-05T11:00:00', end: '2026-01-05T12:00:00' },
  { id: 'started', start: '2026-01-05T08:55:00', end: '2026-01-05T09:30:00' },
  { id: 'allday', allDay: true, start: '2026-01-05', end: '2026-01-06' },
])
let firedSet = {}
eq(M.dueNotifications(feed, nowN, 10, firedSet).map(e => e.id), ['soon'], 'only the one inside the lead window')
firedSet = { soon: true }
eq(M.dueNotifications(feed, nowN, 10, firedSet).map(e => e.id), [], 'never announced twice')
eq(M.dueNotifications(feed, nowN, 0, {}).map(e => e.id), [], 'lead of zero means off')
eq(M.dueNotifications(feed, nowN, 180, {}).map(e => e.id), ['soon', 'later'], 'a wider window catches more')
// an overflow marker is not a real event and must never notify
const withMarker = M.layout(M.decorateAll(Array.from({ length: 6 }, (_, i) => ({
  id: 'n' + i, start: '2026-01-05T09:05:00', end: '2026-01-05T09:30:00'
}))), 3)
ok(withMarker.some(e => e.overflow), 'the fixture really does produce a marker')
ok(M.dueNotifications(withMarker, nowN, 10, {}).every(e => !e.overflow), 'markers never notify')

// All-day round trip. Google's end date is exclusive; the editor shows the
// inclusive day and must hand back exactly what it was given, or every save
// stretches the event by a day.
const fromGoogle = M.decorateAll([
  { id: 'oneday', allDay: true, start: '2026-09-16', end: '2026-09-17' },
  { id: 'threeday', allDay: true, start: '2026-09-16', end: '2026-09-19' },
])[0]
const lastDay = M.inclusiveEndDay(fromGoogle)
eq(M.dayKey(lastDay), '2026-09-16', 'a one-day event shows the day it is on')
eq(M.exclusiveEndDate(lastDay), '2026-09-17', 'and goes back to Google unchanged')

const span = M.decorateAll([{ id: 't', allDay: true, start: '2026-09-16', end: '2026-09-19' }])[0]
eq(M.dayKey(M.inclusiveEndDay(span)), '2026-09-18', 'a three-day event shows its last day')
eq(M.exclusiveEndDate(M.inclusiveEndDay(span)), '2026-09-19', 'and round-trips')

// Saving repeatedly must be a fixed point, not a ratchet.
let end = fromGoogle.endAt
for (let i = 0; i < 5; i++) {
  const inclusive = M.inclusiveEndDay({ allDay: true, endAt: end })
  end = M.parseStamp(M.exclusiveEndDate(inclusive))
}
eq(M.dayKey(end), '2026-09-17', 'five saves later the event is still one day long')

// A timed event is untouched by any of this.
const timed = M.decorateAll([{ id: 'x', start: '2026-09-16T09:00:00', end: '2026-09-16T10:00:00' }])[0]
eq(M.inclusiveEndDay(timed).getTime(), timed.endAt.getTime(), 'timed events pass through')

// theme adaptation
ok(M.isLightSurface('#eff1f5'), 'catppuccin-latte is a light surface')
ok(M.isLightSurface('#ffffff') && M.isLightSurface('#faf4ed'), 'white and rose-pine too')
ok(!M.isLightSurface('#000814'), 'futurenergy is dark')
ok(!M.isLightSurface('#1e1e2e') && !M.isLightSurface('#282828'), 'catppuccin and gruvbox are dark')
eq(M.luma('#ffffff') > 250, true, 'white is bright')
eq(M.luma('#000000'), 0, 'black is not')
// an #aarrggbb value from QML must not be read as if it were #rrggbb
ok(!M.isLightSurface('#ff000814'), 'alpha-prefixed dark colour stays dark')
ok(M.chipAlpha(true, false) > M.chipAlpha(false, false), 'light surfaces need a heavier wash')
ok(M.chipAlpha(true, true) > M.chipAlpha(true, false), 'hover always deepens')
ok(M.chipAlpha(false, true) > M.chipAlpha(false, false), 'on dark too')

// remote text never becomes markup in a notification; only web links open
eq(M.escapeMarkup('<b>Pay</b> & <a href="x">go</a>'), '&lt;b&gt;Pay&lt;/b&gt; &amp; &lt;a href="x"&gt;go&lt;/a&gt;', 'markup escaped')
eq(M.escapeMarkup(null), '', 'null is empty')
ok(M.isWebLink('https://calendar.google.com/event?eid=abc'), 'https link opens')
ok(!M.isWebLink('file:///etc/passwd'), 'file:// never opens')
ok(!M.isWebLink('javascript:alert(1)'), 'javascript: never opens')
ok(!M.isWebLink('http://example.com'), 'plain http is not a calendar link')
ok(!M.isWebLink('https://x y'), 'whitespace is rejected')
ok(!M.isWebLink(''), 'empty is rejected')

// an unparseable timestamp is dropped rather than becoming NaN geometry
const withBad = M.decorateAll([
  { id: 'ok', start: '2026-01-05T09:00:00', end: '2026-01-05T10:00:00' },
  { id: 'bad', start: 'not a date', end: '2026-01-05T10:00:00' },
  { id: 'bad2', start: '2026-01-05T09:00:00', end: '' },
])
eq(withBad.map(e => e.id), ["ok"], "invalid timestamps are dropped")

// calendar arithmetic at the year boundary and on leap days
eq(M.isoWeek(new Date(2026, 11, 31)), 53, '31 Dec 2026 is ISO week 53')
eq(M.isoWeek(new Date(2027, 0, 1)), 53, '1 Jan 2027 still belongs to week 53 of 2026')
eq(M.isoWeek(new Date(2025, 11, 29)), 1, '29 Dec 2025 is week 1 of 2026')
ok(M.parseDayInput('2028-02-29') !== null, '2028 is a leap year')
eq(M.parseDayInput('2027-02-29'), null, '2027 is not')
eq(M.addMonths(new Date(2026, 11, 15), 1).getFullYear(), 2027, 'month stepping crosses the year')
eq(M.dayKey(M.addDays(new Date(2026, 11, 31), 1)), '2027-01-01', 'day stepping crosses the year')
const wk = M.weekDays(new Date(2026, 0, 1), 1)
eq([M.dayKey(wk[0]), M.dayKey(wk[6])], ['2025-12-29', '2026-01-04'], 'a week that straddles New Year')

// The imminent bar label wears the event's colour; on a light theme a pale one
// has to be moved far enough from the bar's ground to be read.
ok(M.contrast(M.legible('#ffff00', '#ffffff', '#000000'), '#ffffff') >= 2.2,
  'yellow is made legible on a white bar')
eq(M.legible('#ffff00', '#000000', '#ffffff'), '#ffff00', 'yellow is left alone on a dark bar')
eq(M.legible('#0046f5', '#ffffff', '#000000'), '#0046f5', 'a legible colour is untouched')
ok(M.contrast(M.legible('#222222', '#000000', '#ffffff'), '#000000') >= 2.2,
  'a dark colour is lifted on a dark bar')
// ----------------------------------------------------------------- meetings

// the host is what a link is judged on, and userinfo is not the host
eq(M.linkParts('https://meet.google.com/abc-defg-hij').host, 'meet.google.com', 'plain host')
eq(M.linkParts('https://MEET.Google.com:443/x').host, 'meet.google.com', 'host is lowered, port dropped')
eq(M.linkParts('https://meet.google.com@evil.example/x').host, 'evil.example', 'userinfo is not the host')
eq(M.meetingProvider('https://meet.google.com@evil.example/x'), '', 'and a spoofed host matches nothing')
eq(M.linkParts('http://meet.google.com/x'), null, 'plain http is not a link we read')
eq(M.linkParts('file:///etc/passwd'), null, 'nor is a file path')

eq(M.meetingProvider('https://meet.google.com/abc-defg-hij'), 'Google Meet', 'Meet')
eq(M.meetingProvider('https://acme.zoom.us/j/9876543210?pwd=x'), 'Zoom', 'Zoom on a vanity subdomain')
eq(M.meetingProvider('https://teams.microsoft.com/l/meetup-join/19%3ameeting'), 'Microsoft Teams', 'Teams')
eq(M.meetingProvider('https://app.slack.com/huddle/T01/C02'), 'Slack huddle', 'a huddle is a call')
eq(M.meetingProvider('https://app.slack.com/client/T01/C02'), '', 'a Slack channel is not')
eq(M.meetingProvider('https://docs.google.com/document/d/1'), '', 'a doc is not a call')
eq(M.meetingProvider('https://zoom.us.evil.example/j/1'), '', 'a lookalike host matches nothing')

// links written by hand, with the sentence's punctuation left behind
eq(M.scrapeLinks('We are on https://meet.google.com/abc-defg-hij.'),
   ['https://meet.google.com/abc-defg-hij'], 'trailing full stop is not part of the address')
eq(M.scrapeLinks('(https://acme.zoom.us/j/1), and https://example.com/x'),
   ['https://acme.zoom.us/j/1', 'https://example.com/x'], 'two links, brackets dropped')
eq(M.scrapeLinks('nothing here'), [], 'prose with no links')
eq(M.scrapeLinks(null), [], 'null is empty')

// hangoutLink and the entry point are the same call, said twice
const meet = M.meetingLinks({
  conference: { name: 'Google Meet', entries: [
    { kind: 'video', uri: 'https://meet.google.com/abc-defg-hij' },
    { kind: 'video', uri: 'https://meet.google.com/abc-defg-hij/' },
    { kind: 'phone', uri: 'tel:+1-555-0100,,123456789#', label: '+1 555-0100', pin: '123456789' },
  ]},
  description: 'Join at https://meet.google.com/abc-defg-hij or dial in.',
})
eq(meet.map(m => m.uri), ['https://meet.google.com/abc-defg-hij', 'tel:+1-555-0100,,123456789#'],
   'one video link, one dial-in; the duplicates collapse')
eq(meet[0].provider, 'Google Meet', 'named from its host')
ok(meet[0].openable && !meet[1].openable, 'only https is clickable')
eq(meet[1].pin, '123456789', 'the pin survives, because a dial-in is useless without it')

// a Zoom link pasted into the notes by hand, with no conferenceData at all
const pasted = M.meetingLinks({
  description: 'Agenda below.\nhttps://acme.zoom.us/j/9876543210?pwd=aaa\nSee https://wiki.example.com/page for notes.',
})
eq(pasted.map(m => m.uri), ['https://acme.zoom.us/j/9876543210?pwd=aaa'],
   'the call is picked up and the wiki link is left in the notes')
eq(pasted[0].provider, 'Zoom', 'named without Google having said so')

// the provider name Google sent is the fallback, never the lead
eq(M.meetingLinks({ conference: { name: 'Acme Bridge', entries: [
  { kind: 'video', uri: 'https://bridge.acme.example/r/1' }]}})[0].provider,
  'Acme Bridge', 'an unknown host keeps the name the API gave it')

eq(M.meetingLinks({}), [], 'an event with no call has no box')
eq(M.meetingLinks({ description: 'nothing to join' }), [], 'nor does one with only prose')

// a video entry point sorts above the numbers you dial, whatever the order
// Google listed them in
const ordered = M.meetingLinks({ conference: { entries: [
  { kind: 'phone', uri: 'tel:+1-555-0100' },
  { kind: 'video', uri: 'https://acme.zoom.us/j/1' },
]}})
eq(ordered.map(m => m.kind), ['video', 'phone'], 'what you can click comes first')

// ---- one row, not six. A real Teams invitation body: the join link, then
// four more links on hosts this file recognises, then the dial-in.
const teamsBody = [
  '________________________________________________________________',
  'Microsoft Teams Need help?<https://aka.ms/JoinTeamsMeeting>',
  'Join the meeting now<https://teams.microsoft.com/l/meetup-join/19%3ameeting_ZjQ>',
  'Meeting ID: 123 456 789',
  'Or dial in: +1 555-0100,,123456789# <tel:+15550100,,123456789#>',
  'Find a local number<https://dialin.teams.microsoft.com/abc>',
  'For organizers: Meeting options<https://teams.microsoft.com/meetingOptions/?organizerId=1>',
  '________________________________________________________________',
].join('\n')

const teamsEvent = {
  conference: { name: 'Microsoft Teams', entries: [
    { kind: 'video', uri: 'https://teams.microsoft.com/l/meetup-join/19%3ameeting_ZjQ' },
    { kind: 'more', uri: 'https://dialin.teams.microsoft.com/abc' },
    { kind: 'phone', uri: 'tel:+15550100,,123456789#', label: '+1 555-0100' },
  ]},
  description: teamsBody,
}
eq(M.primaryMeeting(teamsEvent).uri, 'https://teams.microsoft.com/l/meetup-join/19%3ameeting_ZjQ',
   'the join link, not the meeting-options link beside it')
eq(M.primaryMeeting(teamsEvent).kind, 'video', 'and it is the video entry point')

// the same event with nothing but the pasted block: the first recognised
// link in a Teams body is still the join link
eq(M.primaryMeeting({ description: teamsBody }).uri,
   'https://teams.microsoft.com/l/meetup-join/19%3ameeting_ZjQ',
   'scraped, the join link still leads')

// Meet says its link twice and adds a tel.meet page; one row survives
eq(M.primaryMeeting({
  conference: { name: 'Google Meet', entries: [
    { kind: 'video', uri: 'https://meet.google.com/abc-defg-hij' },
    { kind: 'more', uri: 'https://tel.meet/abc-defg-hij?pin=1' },
    { kind: 'phone', uri: 'tel:+15550100,,1#', pin: '1' },
  ]},
  description: 'Join at https://meet.google.com/abc-defg-hij',
}).uri, 'https://meet.google.com/abc-defg-hij', 'Meet gives one row too')

// a dial-in alone is still worth showing; there is nothing to click
eq(M.primaryMeeting({ conference: { entries: [
  { kind: 'phone', uri: 'tel:+15550100', label: '+1 555-0100' }]}}).kind, 'phone',
  'with nothing clickable, the number is the answer')

eq(M.primaryMeeting({}), null, 'no call, no row')
eq(M.primaryMeeting({ description: 'lunch with https://wiki.example.com/x' }), null,
   'and a wiki link is not a call')

// how a row reads
const [video, phone] = M.meetingLinks({ conference: { name: 'Zoom Meeting', entries: [
  { kind: 'video', uri: 'https://acme.zoom.us/j/9876543210?pwd=aaa' },
  { kind: 'phone', uri: 'tel:+15550100,,9876543210#', label: '+1 555-0100', pin: '4242' },
]}})
eq(M.meetingName(video), 'Zoom', 'the host names the row')
eq(M.meetingDetail(video), 'acme.zoom.us/j/9876543210?pwd=aaa', 'the scheme is not worth eight characters')
eq(M.meetingCopyText(video), 'https://acme.zoom.us/j/9876543210?pwd=aaa', 'but a copied link keeps it')
eq(M.meetingName(phone), 'Zoom', 'a dial-in belongs to the same meeting')
eq(M.meetingDetail(phone), '+1 555-0100  ·  PIN 4242', 'and shows the pin it is useless without')
eq(M.meetingCopyText(phone), '+15550100,,9876543210#', 'a dialler gets the digits, not the scheme')
eq(M.meetingName({ kind: 'phone', uri: 'tel:+15550100' }), 'Dial in', 'an unattributed number still has a name')
eq(M.meetingName({ kind: 'video', uri: 'https://bridge.example/r/1' }), 'bridge.example', 'and an unknown link says where it goes')
eq(M.meetingDetail(null), '', 'nothing renders as nothing')

// ------------------------------------------------------------------- notes

// the preview is the *first* words, not the last — a single-line input
// scrolled to its cursor showed the tail of a description and nothing else
eq(M.notesPreview('Quarterly review.\nBring the deck.'), 'Quarterly review. Bring the deck.',
   'newlines collapse so the first line is not the whole budget')
eq(M.notesPreview('\n\n   Agenda: budget'), 'Agenda: budget', 'leading blank lines are not spent')
ok(M.notesPreview('x'.repeat(400)).startsWith('xxx'), 'a long note starts at its start')
eq(M.notesPreview('x'.repeat(400)).length, 160, 'and is capped')
ok(M.notesPreview('x'.repeat(400)).endsWith('…'), 'with the cut marked')
eq(M.notesPreview(''), '', 'empty stays empty')
eq(M.notesPreview(null), '', 'so does null')
eq(M.notesLineCount('a\nb\nc'), 3, 'three lines')
eq(M.notesLineCount('  \n '), 0, 'whitespace is not a line')
eq(M.notesLineCount(''), 0, 'nor is nothing')
// calendar-filter chip labels stay one short line
eq(M.shortCalendarName('Work'), 'Work', 'a short name passes through')
eq(M.shortCalendarName('Very long calendar name indeed'), 'Very long calendar', 'cut at a word boundary')
ok(M.shortCalendarName('Supercalifragilisticexpialidocious').length <= 18, 'a long single word is bounded')
ok(M.shortCalendarName('Supercalifragilisticexpialidocious').indexOf('…') !== -1, 'and elided')
eq(M.shortCalendarName(''), 'Calendar', 'an empty name still yields a chip')

console.log('all checks passed')

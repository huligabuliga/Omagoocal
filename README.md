# Omagoocal — Google Calendar for Omarchy

Your Google Calendar in the Omarchy bar: day, week and month views, multiple
accounts, event creation and editing, colour straight from Google, one-click
joining for events that have a call, and a notification before events start. Opens instantly — the last sync is painted
from disk before the first network request is made.

![week view](preview.png)

## Sign-in without a Google Cloud project

Google requires an OAuth client to reach the Calendar API, and there is no
anonymous path for read/write access. This plugin does not ship one and does
not ask you to create one. Instead it uses **GNOME Online Accounts** — the
same stack GNOME Calendar uses — which carries the distribution's own Google
client.

That means:

- No Google Cloud project, no API keys, no client ID to paste.
- No Google verification review, and none of the 100-test-user cap an
  unverified OAuth client lives under.
- Token refresh, secure storage and the account list are GOA's job, not this
  plugin's. Nothing here ever writes a refresh token to disk.

Sign-in opens GOA's window, which shows Google's own consent screen.

## Install

```bash
omarchy plugin add https://github.com/huligabuliga/Omagoocal.git --enable
```

Open the panel and press **Sign in with Google**. If GNOME Online Accounts
is missing, the panel offers an **Install dependencies** button first, which
runs the install in a visible Omarchy terminal:

```
gnome-online-accounts
gnome-online-accounts-gtk
```

The backend (`omagoocal`) ships inside the plugin, so a clone is all you
need. Symlink it onto your `PATH` if you want it as a CLI too.

### Dependencies

Everything comes from the Arch repositories; nothing is fetched at runtime
except your calendar data from Google.

| Package | Why |
|---|---|
| `gnome-online-accounts`, `gnome-online-accounts-gtk` | Google sign-in and token refresh. Installed on demand from the panel. |
| `python` | The backend is stdlib-only Python 3 — no `pip`, no `python-gobject`. Installed on demand with the others if missing. |
| `systemd` (`busctl`) | Talks to GNOME Online Accounts over D-Bus. |
| `libnotify` (`notify-send`) | Event notifications. Already part of Omarchy. |

The plugin writes only to its own state folder, `~/.local/state/omagoocal/`,
which it checks is a real directory it owns, mode `0700`, before every read
or write; files are replaced atomically through random exclusive temp files
and never through a symlink. It never edits your Hyprland, shell, or theme
configuration; enabling it in the bar goes through `omarchy plugin enable`,
which is your action.

Because the backend holds a Google access token while it runs, nothing on
that path is resolved through `PATH`, and nothing in the shell's environment
can reach it: the panel runs it as `/usr/bin/python3 -I` (isolated mode —
`PYTHON*` variables and the user site are ignored) with an explicit minimal
environment of `HOME`, `XDG_RUNTIME_DIR` and `DBUS_SESSION_BUS_ADDRESS`
only — it never opens a window or sees a display; the sign-in window is a
separate program the shell starts by absolute path. It
calls `/usr/bin/busctl`, `/usr/bin/notify-send`, `/usr/bin/xdg-open`,
`/usr/bin/pacman` and Omarchy's own installer under `/usr/share/omarchy/bin`
by absolute path. Every API response is capped at 8 MiB, every paginated
listing at 20 pages / 5000 items, one sync at 10 000 events and 500
calendars, and the backend's total output at 16 MiB. Remote strings are cut
to Google's own field limits (title and location 1024, description 8192)
and every field is coerced to the type the panel expects; a call's entry
points are capped at 8 per event and stripped of control characters before
the panel ever sees a URI. Those totals are enforced by one shared budget while the calendars are being fetched in parallel —
bytes charged before a page is decoded, items as each page lands — and the
first exhaustion cancels everything still queued, so the ceiling holds
during the work rather than after it has all been held in memory. Output
is encoded incrementally under the same kind of running count and framed
in bounded lines, which the panel reads one at a time and cuts off, killing
the helper, the moment its own ceiling is crossed. The backend ends
itself after 120 seconds no matter what it is waiting on, and the panel
kills any helper that outlives its own deadline. State files are only read
if they are regular files owned by you with mode `0600`, opened
non-blocking, so nothing planted in the folder can stall it.

No file is ever opened by the panel itself — the snapshot, like every state
file, is read by the backend through the same validated, no-follow, bounded
path. Calendar content is treated as untrusted: anyone who shares a calendar with
you chooses the text in it. Every event field is rendered as plain text
(never parsed as markup), notification text is escaped and passed after
`--`, only `https://` links are ever handed to `xdg-open`, and event ids are
URL-quoted before they touch a request path.

## Remove

```bash
omarchy plugin remove io.github.huligabuliga.omagoocal
rm -rf ~/.local/state/omagoocal        # preferences and caches
```

Your Google account stays in GNOME Online Accounts (it is not the plugin's to
delete); remove it there if you no longer want it. If you installed the GOA
packages only for this plugin, uninstall `gnome-online-accounts-gtk` and
`gnome-online-accounts` with your package manager.

## Using it

| Where | Action |
|---|---|
| Bar label | Next event and how long you have, from the calendars you left switched on for the bar. It takes that event's colour in the last 15 minutes before it starts; with nothing upcoming, just the glyph. |
| Bar left click | Open the calendar |
| Bar right click | Refresh, bypassing every cache |
| Bar middle click | New event |
| Grid click | New event at that time, rounded to the half hour |
| Month drag | New all-day event spanning the selected dates |
| All-day band click | New one-day all-day event |
| All-day band drag | New all-day event spanning the selected dates |
| Event click | Edit |
| Event middle click | Open in Google Calendar |
| 󰕧 on a chip | The event has a call. Open it for the link. |
| `+N more` | Too many events to show side by side — opens the day view |

Keys while the panel is open: `D` `W` `M` switch view, `T` today, `N` new
event, `R` refresh, `,` settings, `[` `]` step, arrows step, `Esc` close.
In the editor, `Ctrl+Enter` saves and `Esc` cancels.

### Joining the call

An event booked through anything that integrates with Google Calendar —
Meet, Zoom, Teams, Webex — carries the call with it, and so does one where
somebody pasted the link into the description by hand. Either way the event
card grows a **CALL** box with **JOIN** in it. A chip on the grid takes a
󰕧 when there is one, so you can see which of the morning's meetings you
have to be somewhere for.

One row, not six. An invitation's boilerplate is full of links — a Teams
block alone carries the join link, a dial-in lookup, a help page and the
organiser's meeting options — so the box shows the join link and nothing
else: the first video entry point the provider declared, which is the one
thing every provider fills in the same way. What Google sent beats anything
found in the prose. An event with only a dial-in number shows that instead,
with **COPY** in place of JOIN and the PIN it is useless without already
beside the number.

Only `https://` is ever handed to `xdg-open`, and only a link on a known
meeting host is ever considered — an unrecognised link stays in the notes
where it was written, because a box labelled CALL that offers you a
spreadsheet is worse than no box. The link is read, never rewritten: the
box is not editable, and saving an event never sends a description you did
not change.

The card is the editor, and the editor refuses read-only calendars, so a
call on a calendar you cannot write to is reached with middle click, which
opens the event in Google Calendar.

### Notes

The description was a single-line field. A single-line field scrolls to its
cursor, so what it showed of a long note was the *end* of it — the last
words of an invitation's footer, never the first words of what the meeting
is. It now shows the beginning, cut off at the right edge, and **EXPAND**
(or clicking the line) opens the whole thing as a proper multi-line editor.
The label says how many lines are folded away rather than only that
something is.

A note you never expanded is never sent back: only fields you actually
changed travel to Google, so saving a new end time cannot flatten a
description you did not touch.

IPC, for keybindings:

```bash
omarchy-shell omagoocal toggle
omarchy-shell omagoocal newEvent
omarchy-shell omagoocal refresh
```

## Settings

Reachable from the gear, or `,`. Connected accounts (add and remove), which
calendars to show, which of those the bar may name, notification lead time,
opening view, week start, 12/24 hour clock, whether event times are always
shown, an optional strip of calendar chips under the header (click one to
hide that calendar without opening settings), the hour the grid opens on,
how tall an hour is, and refresh interval.

### Keeping a calendar out of the bar

Each calendar has two controls, not one. The switch is visibility: off, and
the calendar is gone from every view. **BAR**, beside it, is narrower — the
calendar stays on the grid, but the bar will not name its events.

That is for the shared calendars. A team PTO calendar or a company-wide
holiday feed is worth having on your week and worthless as the one line a
status bar has: it parks something there for days and the bar stops telling
you anything about your own day. Switch BAR off for those and the bar goes
back to naming the next thing you actually have to be at.

The two are stored separately, and a calendar that appears after you last
touched the setting is shown in the bar until you say otherwise — a meeting
you never see is the worse failure. Muting a calendar in the bar is a filter
over events already fetched, so it takes effect without a refresh.

It is the bar label only. Notifications still follow the visibility switch:
if a calendar is on, its events still notify. Turn the calendar off, or set
the lead time to Off, if you want neither.

### Hour height

How many pixels an hour gets on the day and week grid, before the theme's
spacing scale. It sets what a short event has to work with: a quarter of it.
The default, **Comfortable**, gives a 15-minute event a line of text with
room around it. **Compact** is the old, denser grid — short events stay
readable there too, they just sit closer together. **Roomy** and **Tall**
trade visible hours for air.

Short events are drawn differently from long ones whatever the height:
below about two lines, the start time and the title share the one line the
chip has instead of being stacked, which is what used to clip both.

Preferences live in `~/.local/state/omagoocal/config.json`, alongside a
one-hour cache of calendar lists and, by default, the last sync result so
the panel opens instantly after a shell restart. That snapshot holds event
text on disk (`0600`, in a `0700` folder); **Keep last sync on disk** in
settings turns it off and deletes it, after which every open fetches fresh.
Delete the folder to reset everything; accounts themselves live in GNOME
Online Accounts.

## Themes

The panel takes every colour from the active Omarchy theme and adapts to light
ones as well as dark: Omarchy ships five light themes, and a 16% wash of an
event colour that reads well on `vantablack` disappears entirely on `white`.
Chip washes, the spine width, and the faded-past-event opacity are all chosen
from the surface luminance. Verified on `futurenergy`, `catppuccin-latte`,
`white` and `vantablack`.

## Notes

- **Colour** is Google's own: an event's colour when it has one, otherwise its
  calendar's.
- **Recurring events** are expanded by the API, and editing one edits that
  occurrence, not the series.
- **Deleting asks first.** Everything else is reversible from Google Calendar;
  a delete from here is not.
- **Edits send only what you changed.** The notes field is one line; a
  description with paragraphs that you never touched reaches Google
  untouched. Clearing a field clears it.
- **All-day events** are edited in inclusive days — a one-day event starts and
  ends on the same date, even though Google stores the end exclusively.
- **Notifications** go through `notify-send`. If you have Do Not Disturb on,
  you will not see them.
- **Refresh is polling**, not push: Google's watch channels need a public
  callback URL, which a laptop does not have. Events are fetched fresh every
  time; the calendar list and Google's colour palette are cached for an hour.
  The refresh button and `R` skip that cache.
- **Nothing is truncated.** Every paginated API response is followed to its
  last page, so a shared calendar with hundreds of jobs a month shows all of
  them.
- **One backend per shell.** The data and every subprocess live in a plugin
  service (`Store.qml`) that the shell loads once; each monitor's bar widget
  and panel read from it. Two monitors mean one fetch and one notification,
  not two of each.

## Development

```bash
node test_model.js      # date, layout, overflow and notification logic
python3 test_backend.py # GOA account discovery and API request shaping
```

`omagoocal` is stdlib-only Python and talks to GOA over `busctl`, so there
is no `pip` dependency and no `python-gobject`.

Layout: `Store.qml` (service: data, processes, notifications), `Panel.qml`
(the popup), `BarWidget.qml` (the bar label), the view files, `Model.js`
(pure date and layout helpers), `omagoocal` (the backend).

## License

MIT

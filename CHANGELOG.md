# Changelog

## 1.2.0 — 2026-09-29

- **Answer invitations from the card**: an event somebody else invited you to
  shows GOING? with YES / MAYBE / NO. The answer goes out on click, carries
  only your own row of the guest list, and tells the organiser, the way
  Google Calendar does. *@Frafal* (#7)
- **JOIN closes the calendar** as it opens the call, unless the card holds an
  edit you have not saved. *@Frafal* (#7)
- A short chip shows the call glyph too.
- Fixes on merge: a failed answer falls back to the last one Google accepted;
  a card closed while its answer was in flight no longer throws; a failed
  call reads as Google's sentence ("404 Not Found"), not its JSON.

## 1.1.0 — 2026-09-25

First release with outside contributions. Thank you all.

- **Short events keep their titles** and the hour height is a preference
  (Compact / Comfortable / Roomy / Tall). *@Frafal* (#5)
- **BAR toggle per calendar** so a shared PTO or holiday calendar stays on the
  grid but out of the bar label. *@Frafal* (#5)
- **Events with a call say how to join**: a CALL box with JOIN (or COPY for a
  dial-in), a video glyph on the chip, from `conferenceData` or a link pasted
  into the notes. *@Frafal* (#6)
- **Notes are a real multi-line editor** that opens collapsed to its first
  line. *@Frafal* (#6)
- **Drag to create all-day events** across dates in month view and the all-day
  band. *@tumbleweedlabs* (#1)
- **Event times: Always** setting for chips and the bar label. *@artemisa81* (#2)
- **Calendar chips** under the header, off by default. *@artemisa81* (#3)
- **The imminent bar label is legible on any theme.** *@artemisa81* (#4)
- Fixes on merge: all-day chips never show a clock; meeting hosts are matched
  at the start of the host (a provider name in the path no longer counts).

## 1.0.0 — 2026-09-11

Initial release.

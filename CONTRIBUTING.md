# Contributing

Thanks for helping. Omagoocal is small on purpose; a good PR does one thing,
carries its test, and leaves the security posture intact.

## Running it locally

```bash
git clone https://github.com/huligabuliga/Omagoocal ~/.config/omarchy/plugins/io.github.huligabuliga.omagoocal
omarchy restart shell
```

Bar widgets hot-reload on save; `Store.qml` is a *service* and does not, so
after touching it run `omarchy restart shell` again or you will be testing
stale code. `omarchy-shell omagoocal open` opens the panel from a terminal.

## Checks

Both run offline in under a second, and CI runs the same two:

```bash
node test_model.js
PATH= /usr/bin/python3 test_backend.py
```

Every top-level function in `Model.js` is exported to the test automatically,
so add a helper and its check in the same PR.

## Rules the code keeps

These came out of the marketplace security review and are not negotiable:

- The backend runs as `/usr/bin/python3 -I` with a minimal environment. Only
  absolute paths, no ambient `PATH` lookups, no shell strings.
- Remote text is never markup: `textFormat: Text.PlainText` on anything from
  Google or a description. Only `https://` is ever handed to `xdg-open`.
- Everything from the network is bounded: page counts, item counts, bytes,
  string lengths. New fields are coerced to the type the panel expects and
  stripped of control characters in the backend.
- Saving sends only the fields that changed (PATCH), never the whole event.
- Config keys go through `DEFAULTS` / `CONFIG_RANGES` / `CONFIG_ENUMS` in
  `omagoocal`, with a coercion test.

## Screenshots

Never post a screenshot of a real calendar. Build one from invented events
(a stand-in backend or a harness) and say so in the PR.

## Pull requests

- One change per PR, with the why in the description.
- Tests for model or backend logic; a live check in the shell for QML.
- Update `README.md` if behaviour or settings change.
- Default behaviour should stay the same for existing installs; new
  behaviour is a preference unless it is a clear fix.

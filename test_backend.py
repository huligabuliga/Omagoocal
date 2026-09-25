#!/usr/bin/env python3
"""Self-check for omagoocal. Runs offline: D-Bus and the Google API are stubbed.

    python3 test_backend.py
"""
import importlib.machinery, importlib.util, json, os, tempfile

spec = importlib.util.spec_from_loader(
    "gcal", importlib.machinery.SourceFileLoader(
        "gcal", os.path.join(os.path.dirname(os.path.abspath(__file__)), "omagoocal")))
gcal = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gcal)

gcal.STATE = tempfile.mkdtemp()          # mkdtemp is 0700 and ours: valid
gcal._state_cache = None
gcal.CONFIG = os.path.join(gcal.STATE, "config.json")
gcal.CACHE = os.path.join(gcal.STATE, "cache.json")
gcal.LAST_SYNC = os.path.join(gcal.STATE, "last-sync.json")

# -- Nothing below may reach D-Bus or the network. Both seams are stubbed
#    before any code path can use them; individual tests swap in richer fakes.
MANAGED = {"data": [{
    "/org/gnome/OnlineAccounts/Accounts/account_1": {
        "org.gnome.OnlineAccounts.Account": {
            "ProviderType": {"data": "google"},
            "PresentationIdentity": {"data": "a@b.com"},
            "Identity": {"data": "a@b.com"},
            "CalendarDisabled": {"data": False}}},
    "/org/gnome/OnlineAccounts/Accounts/account_2": {
        "org.gnome.OnlineAccounts.Account": {
            "ProviderType": {"data": "google"},
            "PresentationIdentity": {"data": "muted@b.com"},
            "CalendarDisabled": {"data": True}}},
    "/org/gnome/OnlineAccounts/Accounts/account_3": {
        "org.gnome.OnlineAccounts.Account": {
            "ProviderType": {"data": "imap_smtp"},
            "PresentationIdentity": {"data": "mail@b.com"},
            "CalendarDisabled": {"data": False}}},
    "/org/gnome/OnlineAccounts/Manager": {
        "org.gnome.OnlineAccounts.Manager": {}},
}]}
calls = []

def fake_busctl(*args):
    calls.append(args)
    if args[-1] == "GetManagedObjects":
        return MANAGED
    if args[-1] == "GetAccessToken":
        return {"data": ["ya29.token", 3599]}
    return {}

def unstubbed_api(*a, **k):
    raise AssertionError("api() reached before this test stubbed it — would have hit the network")

gcal.busctl = fake_busctl
gcal.api = unstubbed_api
gcal._accounts_cache = None
gcal._tokens.clear()

# -- config round-trip keeps defaults for untouched keys, and is chmod 600
gcal._write(gcal.CONFIG, {"notifyMinutes": 30})
assert gcal.load_config()["notifyMinutes"] == 30
assert gcal.load_config()["weekStart"] == gcal.DEFAULTS["weekStart"], "defaults fill in"
assert oct(os.stat(gcal.CONFIG).st_mode)[-3:] == "600"

# -- state I/O: random exclusive temp files, no stray .tmp, never through a symlink
assert not [f for f in os.listdir(gcal.STATE) if f.endswith(".tmp")], "temp file left behind"
link = os.path.join(gcal.STATE, "evil.json")
os.symlink("/dev/null", link)
try:
    gcal._write(link, {"x": 1})
    raise AssertionError("must refuse to write through a symlink")
except RuntimeError as exc:
    assert "symlink" in str(exc)
assert os.path.islink(link) and gcal._read(link, "fallback") == "fallback", "read must not follow it either"
os.unlink(link)

# -- a state directory that is a symlink is refused outright
real_state = gcal.STATE
gcal.STATE = tempfile.mkdtemp() + "/link"
os.symlink(real_state, gcal.STATE)
gcal._state_cache = None
try:
    gcal._state_fd()
    raise AssertionError("symlinked state dir must be refused")
except OSError:
    pass
gcal.STATE = real_state
gcal._state_cache = None

# -- bounded responses: one oversized body is an error, not a memory spike.
#    Patched at the opener, which is what request() actually goes through.
class _Resp:
    """A response body that is consumed as it is read, like a real socket."""
    def __init__(self, body): self.body = body; self.pos = 0
    def read(self, n=-1):
        end = len(self.body) if n < 0 else min(self.pos + n, len(self.body))
        chunk = self.body[self.pos:end]; self.pos = end
        return chunk
    def __enter__(self): return self
    def __exit__(self, *a): return False
real_open = gcal._opener.open
gcal._opener.open = lambda req, timeout=None: _Resp(b"x" * (gcal.MAX_RESPONSE_BYTES + 1))
try:
    gcal.request(gcal.API + "/big")
    raise AssertionError("oversized response must raise")
except RuntimeError as exc:
    assert "MiB" in str(exc)
gcal._opener.open = lambda req, timeout=None: _Resp(b'{"ok": true}')
assert gcal.request(gcal.API + "/small") == {"ok": True}
gcal._opener.open = real_open

# -- bounded pagination: an endless nextPageToken stops at the page ceiling
gcal.api = lambda account, path, params=None, payload=None, method=None, budget=None: {"items": [1], "nextPageToken": "again"}
try:
    gcal.api_items("a@b.com", "/endless", {})
    raise AssertionError("endless pagination must raise")
except RuntimeError as exc:
    assert "pages" in str(exc)
gcal.api = lambda account, path, params=None, payload=None, method=None, budget=None: {"items": [1] * 3000, "nextPageToken": "again"}
try:
    gcal.api_items("a@b.com", "/huge", {})
    raise AssertionError("aggregate item ceiling must raise")
except RuntimeError as exc:
    assert "items" in str(exc)

# -- ids from the API are quoted into the URL path, never concatenated raw
seen = []
gcal.api = lambda account, path, params=None, payload=None, method=None, budget=None: seen.append((method, path)) or {}
gcal._tokens["a@b.com"] = "t"
gcal.save({"id": "evil/../other?sendUpdates=all", "account": "a@b.com", "calendarId": "c@x",
           "title": "T", "start": "2026-01-01T09:00:00-06:00", "end": "2026-01-01T10:00:00-06:00"})
gcal.delete({"id": "a/b?c", "account": "a@b.com", "calendarId": "c@x"})
for method, path in seen:
    assert "/../" not in path and "?" not in path, (method, path)
    assert path.count("/") == 4, "id must be one path segment: " + path
assert seen[0][0] == "PATCH" and "evil%2F..%2Fother%3FsendUpdates%3Dall" in seen[0][1]
assert seen[1][0] == "DELETE" and path.endswith("a%2Fb%3Fc")
gcal._tokens.clear()                     # leave no seeded token for the GOA test below

# -- payloads arrive as one line on stdin; oversize or non-object is refused
import io, sys as _sys
_stdin = _sys.stdin
_sys.stdin = io.StringIO(json.dumps({"notifyMinutes": 42}) + "\n")
assert gcal.main(["setall"]) == {"ok": True} and gcal.load_config()["notifyMinutes"] == 42
_sys.stdin = io.StringIO("[1,2,3]\n")
try:
    gcal.main(["setall"]); raise AssertionError("non-object config must be refused")
except RuntimeError as exc:
    assert "object" in str(exc)
_sys.stdin = io.StringIO("x" * (gcal.MAX_PAYLOAD_BYTES + 10))
try:
    gcal._payload(["save"]); raise AssertionError("oversize payload must be refused")
except RuntimeError as exc:
    assert "KiB" in str(exc)
_sys.stdin = _stdin
# ...and a payload offered as an argument is refused, never read
try:
    gcal._payload(["save", '{"a": 1}']); raise AssertionError("argv payload must be refused")
except RuntimeError as exc:
    assert "stdin" in str(exc)

# -- the offline snapshot: absent reads as {}, kept only while the preference
#    is on, and removed the moment it is switched off
assert gcal.main(["snapshot"]) == {}, "no snapshot yet reads as empty"
gcal._write(gcal.LAST_SYNC, {"timeMin": "a", "timeMax": "b", "payload": {"events": [], "calendars": []}})
assert gcal.main(["snapshot"])["timeMin"] == "a"
_sys.stdin = io.StringIO(json.dumps({"snapshot": False}) + "\n")
gcal.main(["setall"])
assert not os.path.exists(gcal.LAST_SYNC), "turning the preference off must delete the snapshot"
assert gcal.main(["snapshot"]) == {}
_sys.stdin = io.StringIO(json.dumps({"snapshot": True}) + "\n")
gcal.main(["setall"])
_sys.stdin = _stdin

# -- a FIFO or a world-readable file in the state directory is refused, and a
#    FIFO must not block the read (O_NONBLOCK before the type check)
import time as _time
fifo = os.path.join(gcal.STATE, "fifo.json")
os.mkfifo(fifo, 0o600)
t0 = _time.monotonic()
assert gcal._read(fifo, "fallback") == "fallback"
assert _time.monotonic() - t0 < 1.0, "reading a FIFO must not block"
try:
    gcal._write(fifo, {"x": 1}); raise AssertionError("must refuse to replace a FIFO")
except RuntimeError as exc:
    assert "non-regular" in str(exc)
os.unlink(fifo)
loose = os.path.join(gcal.STATE, "loose.json")
with open(loose, "w") as fh: fh.write('{"x": 1}')
os.chmod(loose, 0o644)
assert gcal._read(loose, "fallback") == "fallback", "group/other-readable file is refused"
os.chmod(loose, 0o600)
assert gcal._read(loose, "fallback") == {"x": 1}
os.unlink(loose)

# -- schema: remote fields are coerced to type and size, never passed through
assert gcal._text("abc", 2) == "ab" and gcal._text(None, 5) == "" and gcal._text({"a": 1}, 5) == ""
assert len(gcal._text("x" * 20000, gcal.MAX_DESCRIPTION)) == gcal.MAX_DESCRIPTION

# -- whole-result ceilings: total events across calendars, and total output
gcal.api = lambda account, path, params=None, payload=None, method=None, budget=None: (
    {"items": [{"id": "primary", "summary": "W", "accessRole": "owner"}]} if path.endswith("calendarList")
    else {"event": {}} if path == "/colors"
    else {"items": [{"id": "e%d" % i, "summary": {"not": "a string"}, "start": {"date": "2026-01-01"}, "end": {"date": "2026-01-02"}} for i in range(5)]})
gcal._tokens["a@b.com"] = "t"
gcal._accounts_cache = None
coerced = gcal.events("2026-01-01T00:00:00Z", "2026-01-08T00:00:00Z", fresh=True)
# the fake returns five events per enabled calendar; every title must be the
# placeholder, whatever the calendar count
assert coerced and all(e["title"] == "(no title)" for e in coerced), \
    "non-string summary becomes the placeholder: " + repr([e["title"] for e in coerced][:3])
assert all(isinstance(e["description"], str) and isinstance(e["link"], str) for e in coerced)
saved_total = gcal.MAX_TOTAL_EVENTS
gcal.MAX_TOTAL_EVENTS = 3
try:
    gcal.events("2026-01-01T00:00:00Z", "2026-01-08T00:00:00Z"); raise AssertionError("total-events ceiling must raise")
except RuntimeError as exc:
    # the shared budget trips while the page is landing, before the flatten
    # step's own belt-and-braces check could
    assert isinstance(exc, gcal.BudgetExceeded) and "events budget exhausted" in str(exc), str(exc)
gcal.MAX_TOTAL_EVENTS = saved_total
gcal._tokens.clear()
saved_out = gcal.MAX_OUTPUT_BYTES
gcal.MAX_OUTPUT_BYTES = 10
try:
    gcal.emit({"big": "x" * 100}); raise AssertionError("output ceiling must raise")
except RuntimeError as exc:
    assert "refusing to emit" in str(exc)
gcal.MAX_OUTPUT_BYTES = saved_out
assert gcal.emit({"ok": True}) == '{"ok":true}'

# -- http: only the Calendar API host, and a redirect is refused so the token
#    can never be forwarded
try:
    gcal.request("https://evil.invalid/x"); raise AssertionError("off-API URL must be refused")
except RuntimeError as exc:
    assert "outside the Calendar API" in str(exc)
class _Redirect:
    def __enter__(self): return self
    def __exit__(self, *a): return False
real_open = gcal._opener.open
def fake_open(req, timeout=None):
    raise gcal.urllib.error.HTTPError(req.full_url, 302, "redirect refused for a token-bearing request", {}, None)
gcal._opener.open = fake_open
try:
    gcal.request(gcal.API + "/calendars/x/events"); raise AssertionError("redirect must surface as an error")
except RuntimeError as exc:
    assert "302" in str(exc)
gcal._opener.open = real_open
assert isinstance(gcal._opener.handlers[0], gcal.urllib.request.BaseHandler)
assert any(isinstance(h, gcal._NoRedirect) for h in gcal._opener.handlers), "no-redirect handler installed"

# -- snapshot shape is validated on the way out
gcal._write(gcal.LAST_SYNC, {"timeMin": "a", "timeMax": "b", "payload": {"events": "not a list", "calendars": []}})
assert gcal.main(["snapshot"]) == {}, "malformed snapshot must read as empty"
gcal._write(gcal.LAST_SYNC, {"timeMin": "a", "timeMax": "b", "payload": {"events": [], "calendars": []}})
assert gcal.main(["snapshot"])["timeMin"] == "a"

# -- outgoing fields are capped and typed like incoming ones
big = gcal._body({"title": "t" * 5000, "start": "2026-01-01T09:00:00-06:00", "end": "2026-01-01T10:00:00-06:00",
                  "description": "d" * 9000, "colorId": "7; DROP"})
assert len(big["summary"]) == gcal.MAX_TITLE and len(big["description"]) == gcal.MAX_DESCRIPTION and big["colorId"] is None
assert gcal._body({"title": {"x": 1}, "start": "2026-01-01", "end": "2026-01-02", "allDay": True})["summary"] == "(no title)"

# -- the budget is enforced while fetching, across calendars, and cancels the
#    rest: with a global allowance of 100 items and 50 calendars each able to
#    return 5000, the fake API must be asked for only a handful of pages
gcal._write(gcal.CACHE, {})
gcal._accounts_cache = None
gcal._tokens["a@b.com"] = "t"
many_cals = [{"id": "cal%d" % i, "summary": "C%d" % i, "accessRole": "owner"} for i in range(50)]
page_calls = []
def greedy_api(account, path, params=None, payload=None, method=None, budget=None):
    if path.endswith("calendarList"):
        return {"items": many_cals}
    if path == "/colors":
        return {"event": {}}
    if budget:
        budget.check()
    page_calls.append(path)             # counted only if it would really fetch
    if budget:
        budget.charge(items=2500)       # what api_items would charge for this page
    return {"items": [{"id": "e", "start": {"date": "2026-01-01"}, "end": {"date": "2026-01-02"}}] * 2500,
            "nextPageToken": "more"}
gcal.api = greedy_api
saved = gcal.MAX_TOTAL_EVENTS
gcal.MAX_TOTAL_EVENTS = 100
try:
    gcal.events("2026-01-01T00:00:00Z", "2026-01-08T00:00:00Z", fresh=True)
    raise AssertionError("global budget must abort the sync")
except gcal.BudgetExceeded as exc:
    # whichever thread's exception reaches _gather first: the one that
    # exhausted the budget, or a sibling that found it already cancelled
    assert "budget" in str(exc), str(exc)
assert len(page_calls) <= 8 + 1, "work continued after exhaustion: %d pages fetched" % len(page_calls)
gcal.MAX_TOTAL_EVENTS = saved
gcal._tokens.clear()

# -- bytes are charged before a response is decoded
b = gcal.Budget(items=10, nbytes=5, what="t")
try:
    b.charge(nbytes=6); raise AssertionError("byte budget must trip")
except gcal.BudgetExceeded:
    pass
assert b.cancelled.is_set()
try:
    b.check(); raise AssertionError("a cancelled budget must refuse further work")
except gcal.BudgetExceeded:
    pass
class _Body:
    def __init__(self, body): self.body = body
    def read(self, n=-1): return self.body if n < 0 else self.body[:n]
    def __enter__(self): return self
    def __exit__(self, *a): return False
real_open = gcal._opener.open
gcal._opener.open = lambda req, timeout=None: _Body(b'{"items": []}')
b2 = gcal.Budget(items=10, nbytes=4, what="t")
try:
    gcal.request(gcal.API + "/x", budget=b2); raise AssertionError("bytes must be charged before decode")
except gcal.BudgetExceeded:
    pass
gcal._opener.open = real_open

# -- emit stops at the ceiling before the whole string exists
saved_out = gcal.MAX_OUTPUT_BYTES
gcal.MAX_OUTPUT_BYTES = 50
class _Huge:
    """An iterable the encoder walks lazily; materializing it fully would
    take far longer than the test allows, so reaching the ceiling early is
    observable as the test finishing at all."""
    def __init__(self): self.served = 0
    def __iter__(self):
        while True:
            self.served += 1
            yield "x" * 10
huge = _Huge()
try:
    gcal.emit({"list": list(_ for _ in range(0))}) ; gcal.emit(huge and {"a": ["x" * 10] * 1000})
    raise AssertionError("output ceiling must raise")
except RuntimeError as exc:
    assert "refusing to emit" in str(exc)
gcal.MAX_OUTPUT_BYTES = saved_out
assert gcal.emit({"ok": True}) == '{"ok":true}'
framed = gcal.emit({"events": [{"title": "t" * 1000, "description": "d" * 5000}] * 40})
assert framed.count("\n") >= 3, "a large result is framed into several lines"
assert max(len(l) for l in framed.split("\n")) <= gcal.OUTPUT_LINE_BYTES + gcal.MAX_DESCRIPTION + 64, "no line exceeds the frame by more than one token"
assert json.loads(framed)["events"][3]["title"] == "t" * 1000, "still one valid document"
assert json.loads(framed.replace("\n", "")) == json.loads(framed), "and the panel's newline-stripped join is identical"

# -- config schema: wrong types and out-of-range values fall back, unknown keys
#    are dropped, calendars must be a str->bool map
c = gcal._coerce_config({"notifyMinutes": "10", "weekStart": 9, "defaultView": "yesterday",
                         "hours12": 1, "calendars": [1, 2], "evil": "x", "refreshMinutes": 0})
assert c["notifyMinutes"] == 10 and c["weekStart"] == 1 and c["defaultView"] == "week"
assert c["hours12"] is False and c["calendars"] == {} and "evil" not in c and c["refreshMinutes"] == 5
c = gcal._coerce_config({"weekStart": 0, "calendars": {"a\tb": False, "c": "no"}, "snapshot": False})
assert c["weekStart"] == 0 and c["calendars"] == {"a\tb": False} and c["snapshot"] is False
assert gcal._coerce_config({"eventTimes": "always"})["eventTimes"] == "always"
assert gcal._coerce_config({"eventTimes": "sometimes"})["eventTimes"] == "auto"
assert gcal._coerce_config("garbage") == gcal.DEFAULTS
_sys.stdin = io.StringIO(json.dumps({"evil": 1, "dayStartHour": 99, "notifyMinutes": 15}) + "\n")
gcal.main(["setall"])
saved_cfg = gcal.load_config()
assert "evil" not in saved_cfg and saved_cfg["dayStartHour"] == 7 and saved_cfg["notifyMinutes"] == 15
_sys.stdin = _stdin

# -- save/delete refuse malformed payloads with a named field
for bad, field in (({"account": "a@b.com"}, "calendarId"),
                   ({"account": "a@b.com", "calendarId": "c", "title": "t"}, "start"),
                   ({"account": "a@b.com", "calendarId": "c", "start": "x", "end": ""}, "end")):
    try:
        gcal.save(bad); raise AssertionError("must refuse: " + field)
    except RuntimeError as exc:
        assert field in str(exc), str(exc)
try:
    gcal.delete({"account": "a@b.com", "calendarId": "c"}); raise AssertionError("delete needs an id")
except RuntimeError as exc:
    assert "id" in str(exc)

# -- state writes are bounded like state reads; reads cross chunk boundaries
saved_state = gcal.MAX_STATE_BYTES
gcal.MAX_STATE_BYTES = 100
try:
    gcal._write(gcal.CONFIG, {"x": "y" * 200}); raise AssertionError("oversize state write must refuse")
except RuntimeError as exc:
    assert "not written" in str(exc)
gcal.MAX_STATE_BYTES = saved_state
assert gcal.load_config()["notifyMinutes"] == 15, "a refused write leaves the old document intact"
bigdoc = {"blob": "z" * (gcal.READ_CHUNK * 3)}
gcal._write(gcal.CACHE, bigdoc)
assert gcal._read(gcal.CACHE, None) == bigdoc, "multi-chunk read reassembles"

# -- response bytes are charged per chunk: the budget trips mid-stream and the
#    body is never fully read
class _Drip:
    def __init__(self, n): self.left = n; self.served = 0
    def read(self, k=-1):
        take = self.left if k < 0 else min(k, self.left)
        self.left -= take; self.served += take
        return b"x" * take
    def __enter__(self): return self
    def __exit__(self, *a): return False
drip = _Drip(gcal.READ_CHUNK * 10)
real_open = gcal._opener.open
gcal._opener.open = lambda req, timeout=None: drip
b3 = gcal.Budget(items=10, nbytes=gcal.READ_CHUNK * 2 + 1, what="t")
try:
    gcal.request(gcal.API + "/x", budget=b3); raise AssertionError("budget must trip mid-stream")
except gcal.BudgetExceeded:
    pass
assert drip.served <= gcal.READ_CHUNK * 3, "reading stopped at the budget, served %d" % drip.served
gcal._opener.open = real_open

# -- one retry on a transient status, none on a second failure, and never a
#    retry of a write on a 5xx (the server may have acted on it)
class _Fail:
    def __init__(self, codes): self.codes = list(codes); self.calls = 0
    def __call__(self, req, timeout=None):
        self.calls += 1
        code = self.codes.pop(0)
        if code == 200: return _Resp(b'{"ok": true}')
        raise gcal.urllib.error.HTTPError(req.full_url, code, "nope", {}, io.BytesIO(b""))
real_open = gcal._opener.open; real_delay = gcal.RETRY_DELAY; gcal.RETRY_DELAY = 0
f = _Fail([503, 200]); gcal._opener.open = f
assert gcal.request(gcal.API + "/x") == {"ok": True} and f.calls == 2, "one retry then success"
f = _Fail([429, 429]); gcal._opener.open = f
try:
    gcal.request(gcal.API + "/x"); raise AssertionError("second failure must stand")
except RuntimeError as exc:
    assert "429" in str(exc) and f.calls == 2, "exactly one retry"
f = _Fail([503, 200]); gcal._opener.open = f
try:
    gcal.request(gcal.API + "/x", data={"a": 1}, method="POST"); raise AssertionError("a write is not retried on 503")
except RuntimeError:
    assert f.calls == 1
f = _Fail([429, 200]); gcal._opener.open = f
assert gcal.request(gcal.API + "/x", data={"a": 1}, method="POST") == {"ok": True}, "a write IS retried on 429 (not acted on)"
gcal._opener.open = real_open; gcal.RETRY_DELAY = real_delay
assert gcal._tls.minimum_version == gcal.ssl.TLSVersion.TLSv1_2 and gcal._tls.check_hostname

# -- argv timestamps are validated before they reach a URL or the snapshot
for bad in ("2026-01-01", "yesterday", "2026-01-01T00:00:00", ""):
    try:
        gcal._stamp(bad, "timeMin"); raise AssertionError("must reject: " + repr(bad))
    except RuntimeError as exc:
        assert "timeMin" in str(exc)
assert gcal._stamp("2026-01-01T00:00:00-06:00", "t") and gcal._stamp("2026-01-01T00:00:00Z", "t")

# -- a calendar id with a control character cannot poison the config key
gcal._write(gcal.CACHE, {})
gcal._accounts_cache = None
gcal._tokens["a@b.com"] = "t"
gcal.api = lambda account, path, params=None, payload=None, method=None, budget=None: (
    {"items": [{"id": "good", "summary": "G", "accessRole": "owner"},
               {"id": "bad\tid", "summary": "B", "accessRole": "owner"},
               {"id": "", "summary": "E", "accessRole": "owner"}]} if path.endswith("calendarList") else {"items": []})
assert [c["id"] for c in gcal.calendar_list(fresh=True)] == ["good"]
gcal._tokens.clear()

# -- the CLI shebang names the isolated system interpreter
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "omagoocal")) as fh:
    assert fh.readline().rstrip() == "#!/usr/bin/python3 -IXutf8", "shebang must be the isolated, UTF-8 system interpreter"

# -- request bodies: all-day uses date, timed uses dateTime, blanks are dropped
timed = gcal._body({"title": "T", "start": "2026-01-01T09:00:00-06:00",
                    "end": "2026-01-01T10:00:00-06:00"})
assert "dateTime" in timed["start"] and "location" not in timed, "absent field is left alone"
cleared = gcal._body({"title": "T", "start": "2026-01-01T09:00:00-06:00",
                      "end": "2026-01-01T10:00:00-06:00", "location": "", "description": "", "colorId": ""})
assert cleared["location"] == "" and cleared["description"] == "" and cleared["colorId"] is None, "present-empty clears"
allday = gcal._body({"title": "T", "allDay": True,
                     "start": "2026-01-01", "end": "2026-01-02", "colorId": 5})
assert allday["start"] == {"date": "2026-01-01"} and allday["colorId"] == "5"

# -- GOA account discovery: only Google accounts, only with calendar enabled
gcal._accounts_cache = None
found = gcal.goa_accounts()
assert list(found) == ["a@b.com"], found
assert found["a@b.com"].endswith("account_1")
assert gcal.access_token("a@b.com") == "ya29.token"
try:
    gcal.access_token("nobody@b.com")
    raise AssertionError("unknown account must raise")
except RuntimeError as exc:
    assert "Not connected" in str(exc)

# -- events(): disabled calendars are skipped, event colour beats calendar
#    colour, cancelled events drop out, all-day is detected from `date`.
#    Starts from an empty TTL cache: this test exercises fetch-then-cache
#    itself, and earlier tests left their own entries on disk.
gcal._write(gcal.CACHE, {})
gcal._accounts_cache = None
gcal._tokens.clear()
gcal._write(gcal.CONFIG, {"calendars": {"a@b.com\tmuted": False}})
CALS = [{"id": "primary", "summary": "Work", "backgroundColor": "#111111",
         "accessRole": "owner", "primary": True},
        {"id": "muted", "summary": "Noise", "backgroundColor": "#222222",
         "accessRole": "reader"}]
EVENTS = [{"id": "1", "summary": "Standup", "colorId": "3",
           "start": {"dateTime": "2026-01-01T09:00:00Z"},
           "end": {"dateTime": "2026-01-01T09:15:00Z"}},
          {"id": "2", "summary": "Holiday", "start": {"date": "2026-01-02"},
           "end": {"date": "2026-01-03"}},
          {"id": "3", "summary": "Gone", "status": "cancelled",
           "start": {"date": "2026-01-02"}, "end": {"date": "2026-01-03"}}]
paths = []

def fake_api(account, path, params=None, payload=None, method=None, budget=None):
    paths.append(path)
    if path.endswith("calendarList"):
        return {"items": CALS}
    if path == "/colors":
        return {"event": {"3": {"background": "#ff0000"}}}
    # two pages, so pagination is exercised on every run
    if params and params.get("pageToken") == "p2":
        return {"items": EVENTS[2:]}
    return {"items": EVENTS[:2], "nextPageToken": "p2"}

gcal.api = fake_api
got = gcal.events("2026-01-01T00:00:00Z", "2026-01-08T00:00:00Z")
assert [e["title"] for e in got] == ["Standup", "Holiday"], got
assert got[0]["color"] == "#ff0000", "event colour must win"
assert got[1]["color"] == "#111111", "falls back to calendar colour"
assert got[1]["allDay"] is True and got[0]["allDay"] is False
assert got[0]["writable"] is True and got[0]["account"] == "a@b.com"
assert paths.count("/colors") == 1, "palette fetched once per account"
assert not any("muted" in p for p in paths), "disabled calendar was queried"
assert sum(1 for p in paths if p.endswith("/events")) == 2, "both pages fetched"

# -- the calendar list and palette come from the TTL cache on the second run
before = len(paths)
gcal.events("2026-01-01T00:00:00Z", "2026-01-08T00:00:00Z")
again = paths[before:]
assert not any(p.endswith("calendarList") for p in again), "calendarList should be cached"
assert "/colors" not in again, "palette should be cached"
assert sum(1 for p in again if p.endswith("/events")) == 2, "events are never cached"
gcal.events("2026-01-01T00:00:00Z", "2026-01-08T00:00:00Z", fresh=True)
assert any(p.endswith("calendarList") for p in paths[before + 2:]), "fresh bypasses the cache"

assert all(a[0] != "call" or a[1] == gcal.GOA for a in calls), "only GOA was ever addressed"

# -- forget clears the cache and spawns nothing: the sign-in window is the shell's job
_spawned = []
_real_popen = gcal.subprocess.Popen
gcal.subprocess.Popen = lambda *a, **k: (_spawned.append(a), _real_popen(*a, **k))[1]
try:
    gcal._write(gcal.CACHE, {"calendars": {"x@y": {"at": 1, "value": []}}})
    assert gcal.main(["forget"]) == {"ok": True}
    assert gcal._read(gcal.CACHE, None) == {}, "forget must empty the cache"
    assert _spawned == [], "forget must not start a process"
    assert not hasattr(gcal, "account_chooser") and not hasattr(gcal, "ACCOUNT_CHOOSERS")
finally:
    gcal.subprocess.Popen = _real_popen

# -- an account identity with control characters cannot poison the config key
_saved_busctl = gcal.busctl
gcal._accounts_cache = None
gcal.busctl = lambda *a: {"data": [{
    "/a": {"org.gnome.OnlineAccounts.Account": {"ProviderType": {"data": "google"},
             "PresentationIdentity": {"data": "bad\tname@example.com"}}},
    "/b": {"org.gnome.OnlineAccounts.Account": {"ProviderType": {"data": "google"},
             "PresentationIdentity": {"data": "\x00\x1f"}}},
}]}
try:
    accounts = gcal.goa_accounts()
    assert accounts == {"badname@example.com": "/a"}, accounts
finally:
    gcal.busctl = _saved_busctl
    gcal._accounts_cache = None
print("all checks passed")

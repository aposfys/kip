#!/usr/bin/env python3
"""Merge one part ("mac", "brief" or "scan") into the Docket widget's data file. Zero-token: no network, no Claude.

  pc-health.sh --json | docket-widget-write.py mac      hourly, from the local.pc-health LaunchAgent
  docket-widget-write.py brief < brief.json             end of the daily-health-tasks-brief task
  docket-widget-write.py scan < scan.json               end of the hourly inbox scan task
  docket-widget-write.py brief --file brief.json
  docket-widget-write.py --show                         print the file path and contents

brief.json: {"date": "YYYY-MM-DD", "one_thing": "...", "today": [{"title", "tag", "due"}],
             "week": [...], "overdue_count": 0, "open_count": 0,
             "week_count": 0, "waiting_count": 0, "nodate_count": 0,
             "next_deadline": {"title", "tag", "due"}}
  week holds the first 10 tasks due this week; week_count counts all of them. Every key but date is optional.
tag is phd, work, personal or cal (calendar event). due is "HH:MM", "YYYY-MM-DD" or "YYYY-MM-DD HH:MM".
scan.json: {"scanned_at": "ISO time mail was last checked", "agents_running": 2,
            "agents": [{"title", "project"}]}   ("running" is read as "agents", so agents/now can be piped in)

The file is ~/.claude/docket/docket.json (override with DOCKET_JSON=/path). The widget reads it
through a read-only sandbox exception. Not an App Group container: macOS blocks other processes,
like this launchd job, from writing into those.
Only known keys are kept and every string is cut short, so mail bodies or secrets cannot end up in it.
Writing one part never touches the others.
"""
import fcntl
import json
import os
import sys
import tempfile
from datetime import date, datetime


def target():
    return os.environ.get("DOCKET_JSON") or os.path.expanduser("~/.claude/docket/docket.json")


def text(v, limit):
    if v is None or isinstance(v, (dict, list)):
        return None
    v = " ".join(str(v).split())  # one line, no control characters
    return v[:limit] or None


def whole(v):
    try:
        return int(round(float(v)))
    except (TypeError, ValueError):
        return None


def number(v):
    try:
        return round(float(v), 1)
    except (TypeError, ValueError):
        return None


def listed(v, limit):
    return v[:limit] if isinstance(v, list) else []


def clean_mac(d):
    return {
        "battery_pct": whole(d.get("battery_pct")),
        "battery_health_pct": whole(d.get("battery_health_pct")),
        "cycles": whole(d.get("cycles")),
        "thermal": text(d.get("thermal"), 12),
        "mem_free_pct": whole(d.get("mem_free_pct")),
        "disk_free_gb": number(d.get("disk_free_gb")),
        "disk_total_gb": number(d.get("disk_total_gb")),
        "issues": [t for t in (text(x, 80) for x in listed(d.get("issues"), 6)) if t],
    }


def clean_item(x):
    if isinstance(x, str):
        x = {"title": x}
    if not isinstance(x, dict) or not text(x.get("title"), 90):
        return None
    tag = (text(x.get("tag"), 12) or "").strip("[]").lower() or None
    return {"title": text(x.get("title"), 90), "tag": tag, "due": text(x.get("due"), 16)}


def clean_brief(d):
    def items(key, limit):
        return [c for c in map(clean_item, listed(d.get(key), 20)) if c][:limit]

    return {
        "date": text(d.get("date"), 10) or date.today().isoformat(),
        "one_thing": text(d.get("one_thing"), 160),
        "today": items("today", 8),
        "week": items("week", 10),
        "overdue_count": whole(d.get("overdue_count")) or 0,
        "open_count": whole(d.get("open_count")),
        "week_count": whole(d.get("week_count")),
        "waiting_count": whole(d.get("waiting_count")),
        "nodate_count": whole(d.get("nodate_count")),
        "next_deadline": clean_item(d.get("next_deadline")),
    }


def stamp(v):
    """Any ISO time (with Z or fractions, as JavaScript writes it) as local time to the second, else None."""
    try:
        t = datetime.fromisoformat(str(v).strip().replace("Z", "+00:00"))
    except ValueError:
        return None
    return t.astimezone().isoformat(timespec="seconds")


def clean_scan(d):
    raw = d.get("agents") if "agents" in d else d.get("running")
    agents = [{"title": text(a.get("title"), 60), "project": text(a.get("project"), 30)}
              for a in listed(raw, 20) if isinstance(a, dict) and text(a.get("title"), 60)]
    running = whole(d.get("agents_running"))
    return {
        "scanned_at": stamp(d.get("scanned_at") or d.get("checked_at")),
        "agents_running": len(agents) if running is None else running,
        "agents": agents[:5],
    }


CLEAN = {"mac": clean_mac, "brief": clean_brief, "scan": clean_scan}


def write(part, obj, path):
    clean = CLEAN[part](obj)
    now = datetime.now().astimezone().isoformat(timespec="seconds")
    clean["updated_at"] = now
    folder = os.path.dirname(path) or "."
    os.makedirs(folder, exist_ok=True)
    with open(path + ".lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)  # the hourly agent and the morning brief may overlap
        try:
            with open(path) as fh:
                current = json.load(fh)
        except (OSError, ValueError):
            current = {}
        if not isinstance(current, dict):
            current = {}
        current[part] = clean
        current["updated_at"] = now
        fd, tmp = tempfile.mkstemp(dir=folder, prefix=".docket-", suffix=".json")
        with os.fdopen(fd, "w") as out:
            json.dump(current, out, indent=1, ensure_ascii=False)
        os.replace(tmp, path)  # atomic: the widget never reads a half-written file
    return clean


def main(argv):
    if argv[:1] == ["--show"]:
        path = target()
        print(path)
        print(open(path).read() if os.path.exists(path) else "(no file yet)")
        return
    if not argv or argv[0] not in CLEAN:
        sys.exit(__doc__)
    part = argv[0]
    raw = open(argv[2]).read() if argv[1:2] == ["--file"] and len(argv) > 2 else sys.stdin.read()
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as e:
        sys.exit(f"docket-widget-write: {part} input is not JSON ({e})")
    if isinstance(obj, dict) and isinstance(obj.get(part), dict):
        obj = obj[part]  # also accept {"brief": {...}}
    if not isinstance(obj, dict):
        sys.exit(f"docket-widget-write: {part} input must be a JSON object")
    path = target()
    write(part, obj, path)
    print(f"docket: {part} written to {path}")


if __name__ == "__main__":
    main(sys.argv[1:])

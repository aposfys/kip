#!/usr/bin/env python3
"""Self-check for docket-widget-write.py: merge keeps the other parts, junk and long text are dropped.
Run: python3 scripts/test_docket_widget_write.py
"""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
WRITER = os.path.join(HERE, "docket-widget-write.py")


def run(part, payload, path):
    env = dict(os.environ, DOCKET_JSON=path)
    subprocess.run([sys.executable, WRITER, part], input=json.dumps(payload), text=True,
                   env=env, check=True, capture_output=True)
    with open(path) as fh:
        return json.load(fh)


with tempfile.TemporaryDirectory() as tmp:
    path = os.path.join(tmp, "docket.json")
    brief = {
        "date": "2026-11-22", "one_thing": "Send chapter 2\nto supervisor", "secret_body": "x" * 500,
        "today": [{"title": "T" * 300, "tag": "[PhD]", "due": "10:00", "body": "mail body"}, "Plain string task", {"no": "title"}],
        "week": "not a list", "overdue_count": "2", "open_count": 14,
    }
    data = run("brief", brief, path)
    b = data["brief"]
    assert "secret_body" not in b and "body" not in b["today"][0], b
    assert b["one_thing"] == "Send chapter 2 to supervisor", b["one_thing"]
    assert len(b["today"]) == 2 and len(b["today"][0]["title"]) == 90 and b["today"][0]["tag"] == "phd", b["today"]
    assert b["week"] == [] and b["overdue_count"] == 2, b

    data = run("mac", {"battery_pct": 80, "disk_free_gb": "64", "issues": ["Disk almost full", {"x": 1}], "token": "abc"}, path)
    assert data["brief"]["one_thing"] == "Send chapter 2 to supervisor", "mac write must keep brief"
    assert data["mac"]["disk_free_gb"] == 64.0 and data["mac"]["issues"] == ["Disk almost full"], data["mac"]
    assert "token" not in data["mac"]

    data = run("brief", {"one_thing": "New day", "week_count": "14", "waiting_count": 3, "nodate_count": None,
                         "next_deadline": {"title": "Thesis committee report", "tag": "PhD", "due": "2026-12-01",
                                           "notes": "private"}}, path)
    assert data["mac"]["battery_pct"] == 80, "brief write must keep mac"
    b = data["brief"]
    assert b["week_count"] == 14 and b["waiting_count"] == 3 and b["nodate_count"] is None, b
    assert b["next_deadline"] == {"title": "Thesis committee report", "tag": "phd", "due": "2026-12-01"}, b

    # The scan task may pipe its agents/now doc as is: "running" and "checked_at", JavaScript times.
    data = run("scan", {"checked_at": "2026-11-22T12:05:00.123Z", "scheduled": [{"id": "x"}],
                        "running": [{"title": "Inbox Docket tabs", "project": "docket", "last_activity": "t"},
                                    {"no": "title"}] + [{"title": f"Agent {i}"} for i in range(6)]}, path)
    s = data["scan"]
    assert s["agents_running"] == 7 and len(s["agents"]) == 5 and "scheduled" not in s, s
    assert s["agents"][0] == {"title": "Inbox Docket tabs", "project": "docket"}, s["agents"][0]
    assert s["scanned_at"] and s["scanned_at"].count(":") >= 2 and "." not in s["scanned_at"], s["scanned_at"]
    assert data["brief"]["one_thing"] == "New day" and data["mac"]["battery_pct"] == 80, "scan write must keep the rest"
    data = run("scan", {"scanned_at": "not a time", "agents_running": 0}, path)
    assert data["scan"]["scanned_at"] is None and data["scan"]["agents"] == [], data["scan"]
print("ok")

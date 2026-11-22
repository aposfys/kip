# Docket

A macOS desktop widget that shows the daily brief and how the Mac is doing, with Aori the octopus.

- **Small:** Aori and the one thing for today.
- **Medium:** adds the top 3 for today, plus battery-health and disk rings.
- **Large:** adds the week and the overdue count.

Aori has four moods. Sleepy (22:00–07:00) wins over the rest. Next comes worried (overdue items or a Mac issue), then busy (3+ items today), and happy otherwise. A tap opens Inbox Docket in the browser. The widget makes no network calls. It reads one local JSON file and refreshes every 20 minutes. It also redraws at 07:00 and 22:00, so the mood changes on time. Each card shows how long ago the brief was updated. After 26 hours it shows a gentle stale state.

## Build and install

Needs Xcode 26 or later. The only dependencies are Apple frameworks.

```bash
xcodebuild -project Docket.xcodeproj -scheme Docket -configuration Release -derivedDataPath build/dd build
pkill -x Docket; rm -rf ~/Applications/Docket.app && cp -R build/dd/Build/Products/Release/Docket.app ~/Applications/
open ~/Applications/Docket.app
```

To add the widget, right-click the desktop and choose Edit Widgets. Then search for Docket.

Signing is ad hoc ("Sign to Run Locally"), which is enough for a widget on this Mac. To sign with a personal team instead, set `DEVELOPMENT_TEAM` on both targets in Xcode.

## Data

The widget reads `~/.claude/docket/docket.json`:

```json
{
  "updated_at": "2026-11-22T08:30:00Z",
  "mac": {"battery_pct": 80, "battery_health_pct": 91, "cycles": 210, "thermal": "nominal",
          "mem_free_pct": 34, "disk_free_gb": 120, "issues": []},
  "brief": {"date": "2026-11-22", "one_thing": "Send the chapter draft",
            "today": [{"title": "Lab meeting", "tag": "phd", "due": "2026-11-22 11:00"}],
            "week": [], "overdue_count": 0, "open_count": 7}
}
```

Tags are `phd`, `work`, `personal`, `cal` and `mail`. The file holds titles and numbers only, never mail bodies or secrets.

The file lives in the home folder, not an App Group container. macOS blocks other processes, such as the LaunchAgent and the scheduled task, from writing into a group container. The sandboxed widget gets read-only access to `~/.claude/docket/` through a home-relative-path entitlement (`Config/DocketWidget.entitlements`).

## Writers

All writers go through `scripts/docket-widget-write.py`, installed at `~/.claude/scripts/docket-widget-write.py`. It locks the file and replaces it atomically. Each call merges only its own part, `mac` or `brief`, and leaves the other part alone.

- **Hourly LaunchAgent** (`~/Library/LaunchAgents/local.pc-health.plist`): runs `pc-health.sh --alert` as before. It then pipes `pc-health.sh --json` into the writer's `mac` mode.
- **Morning brief task** (`daily-health-tasks-brief`): its last step pipes the brief's task titles into the writer's `brief` mode.
- **The app's Refresh button:** runs the same `mac` pipeline as the LaunchAgent, then reloads the widget.

```bash
~/.claude/scripts/pc-health.sh --json | python3 ~/.claude/scripts/docket-widget-write.py mac
echo '{"date":"2026-11-22","one_thing":"Send the chapter draft","today":[],"week":[],"overdue_count":0,"open_count":0}' \
  | python3 ~/.claude/scripts/docket-widget-write.py brief
```

Set `DOCKET_JSON` to write to another file, for example in tests.

## Checks

```bash
python3 scripts/test_docket_widget_write.py
~/Applications/Docket.app/Contents/MacOS/Docket --selftest
~/Applications/Docket.app/Contents/MacOS/Docket --snapshot build/snap
```

`--selftest` checks the mood rules, the stale cut-off, the 07:00/22:00 boundaries and the due labels. `--snapshot` writes `docket-light.png` and `docket-dark.png` to the folder you give it. Each image shows every mood and the stale state in all three sizes, drawn from the real data file.

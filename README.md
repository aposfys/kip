# Docket

A macOS desktop widget that shows the daily brief and how the Mac is doing, with the Docket robot.

- **Small:** the robot and the one thing for today.
- **Medium:** adds the top 3 for today, plus compact battery-health and disk rings.
- **Large:** adds the next PhD or personal deadline, the week with its waiting and no-date counts, when mail was last checked, how many agents are working, any Mac issue and the overdue count.

The robot has four moods, and each one changes its shape, so it reads in grayscale too. Happy has dot eyes and a smile. Busy has half-lid eyes, an open mouth and a halo. Worried has X eyes, a wavy mouth and sparks, and leans 5°. Sleepy has closed eyes and a Zzz. Sleepy (22:00–07:00) wins over the rest. Next comes worried (overdue items or a Mac issue), then busy (3+ items today), and happy otherwise. A tap opens Inbox Docket in the browser. The widget makes no network calls. It reads one local JSON file and refreshes every 20 minutes. It also redraws at 07:00 and 22:00, so the mood changes on time. Each card shows how long ago the brief was updated. After 26 hours it shows a gentle stale state: the robot turns grey. The robot moves gently in the app window only. The widgets stay still.

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
            "week": [], "overdue_count": 0, "open_count": 7,
            "week_count": 12, "waiting_count": 3, "nodate_count": 4,
            "next_deadline": {"title": "Committee report", "tag": "phd", "due": "2026-12-01"}},
  "scan": {"scanned_at": "2026-11-22T14:05:00+02:00", "agents_running": 2,
           "agents": [{"title": "MIC figures", "project": "phd"}]}
}
```

Tags are `phd`, `work`, `personal`, `cal` and `mail`. `week` holds the first 10 tasks due this week, and `week_count` counts all of them. Every key except `date` is optional. The agents count hides once the scan is over 3 hours old. The file holds titles and numbers only, never mail bodies or secrets.

The file lives in the home folder, not an App Group container. macOS blocks other processes, such as the LaunchAgent and the scheduled task, from writing into a group container. The sandboxed widget gets read-only access to `~/.claude/docket/` through a home-relative-path entitlement (`Config/DocketWidget.entitlements`).

## Writers

All writers go through `scripts/docket-widget-write.py`, installed at `~/.claude/scripts/docket-widget-write.py`. It locks the file and replaces it atomically. Each call merges only its own part, `mac`, `brief` or `scan`, and leaves the other parts alone.

- **Hourly LaunchAgent** (`~/Library/LaunchAgents/local.pc-health.plist`): runs `pc-health.sh --alert` as before. It then pipes `pc-health.sh --json` into the writer's `mac` mode.
- **Morning brief task** (`daily-health-tasks-brief`): its last step pipes the brief's task titles into the writer's `brief` mode.
- **Hourly inbox scan task:** its last step pipes the scan time and the running agents (titles only) into the writer's `scan` mode. The writer also takes the `agents/now` document as it is, reading `checked_at` and `running`.
- **The app's Refresh button:** runs the same `mac` pipeline as the LaunchAgent, then reloads the widget.

```bash
~/.claude/scripts/pc-health.sh --json | python3 ~/.claude/scripts/docket-widget-write.py mac
echo '{"date":"2026-11-22","one_thing":"Send the chapter draft","today":[],"week":[],"overdue_count":0,"open_count":0}' \
  | python3 ~/.claude/scripts/docket-widget-write.py brief
echo '{"scanned_at":"2026-11-22T14:05:00Z","running":[{"title":"MIC figures","project":"phd"}]}' \
  | python3 ~/.claude/scripts/docket-widget-write.py scan
```

Set `DOCKET_JSON` to write to another file, for example in tests.

## Robot artwork

`Design/robot/` holds the master SVGs: `happy`, `busy`, `worried`, `sleepy`, `stale` (happy, greyed out) and an 18 pt one-colour menu-bar template for each mood (`menubar-*.svg`). They are generated from `Shared/Robot.swift`, which also draws the robot in SwiftUI, so the two never drift apart. To change the robot, edit the Swift, rebuild and run:

```bash
~/Applications/Docket.app/Contents/MacOS/Docket --svg Design/robot
```

## Checks

```bash
python3 scripts/test_docket_widget_write.py
~/Applications/Docket.app/Contents/MacOS/Docket --selftest
~/Applications/Docket.app/Contents/MacOS/Docket --snapshot build/snap
```

`--selftest` checks the mood rules, the stale cut-off, the 07:00/22:00 boundaries, the due labels, the large widget's row budget, the new brief and scan keys, the 3-hour agents cut-off and the robot's path parser. `--snapshot` writes `docket-light.png`, `docket-dark.png` and `robot-moods.png` to the folder you give it. The widget images show every mood, the stale state and a crowded day in all three sizes, drawn from the real data file. The mood sheet shows every mood at 32, 44, 64 and 120 pt, in colour and in grayscale, plus the menu-bar glyphs.

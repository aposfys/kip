# kip

kip is a macOS menu-bar companion and desktop widget that shows the daily brief and how the Mac is doing. The name is always lowercase. The Xcode project, scheme, bundle ids, data folder and writer script keep the old working name, docket.

- **Small:** the robot and the one thing for today.
- **Medium:** adds the top 3 for today, plus compact battery-health and disk rings.
- **Large:** adds the next PhD or personal deadline, the week with its waiting and no-date counts, when mail was last checked, how many agents are working, any Mac issue and the overdue count.

The robot has four moods, and each one changes its shape, so it reads in grayscale too. Happy has dot eyes and a smile. Busy has half-lid eyes, an open mouth and a halo. Worried has X eyes, a wavy mouth and sparks, and leans 5°. Sleepy has closed eyes and a Zzz. Sleepy (22:00–07:00) wins over the rest. Next comes worried (overdue items or a Mac issue), then busy (3+ items today), and happy otherwise. A tap opens Inbox Docket in the browser. The widget makes no network calls. It reads one local JSON file and refreshes every 20 minutes. It also redraws at 07:00 and 22:00, so the mood changes on time. Each card shows how long ago the brief was updated. After 26 hours it shows a gentle stale state: the robot turns grey. The robot moves gently in the app window only. The widgets stay still.

## Menu-bar companion

The app lives in the menu bar as the robot in its current mood. A click opens a popover with three tabs.

- **Today:** Mac health and today's brief from the same JSON file, plus four actions. Run brief now asks Claude for a short brief from the task list. Health check runs `pc-health.sh` and refreshes the numbers. Disk preview runs `mo clean --dry-run`, which removes nothing. Open Inbox Docket opens the artifact.
- **Ask:** one question, one answer. Claude runs as `claude -p --model sonnet --max-turns 6` with only Read, Grep and Glob, in safe mode, with docket.json as context. Web or bulk questions go to agy through `~/.claude/skills/agy-delegate/agy-run.sh` in plan mode. kip picks the engine from the wording, and you can change it.
- **Tasks:** recurring prompts. Type "every Monday 9:00 check X and tell me" and kip shows the parsed schedule, prompt and engine to confirm. Each saved task is a LaunchAgent at `~/Library/LaunchAgents/local.docket-task-<id>.plist` that runs the same read-only one-shot, posts the answer as a notification and appends it to `~/.claude/docket/tasks/<id>.log`. Tasks can be paused, edited, deleted or run now. They run even when kip is closed.

When something is overdue the robot turns worried and kip posts one notification, once per overdue count per day, between 07:00 and 22:00. Mac issues change the mood too, but `pc-health.sh --alert` already notifies about them, so kip only adds the first issue to its overdue notification. kip starts no Claude runs on its own. Only the tasks you create run on a schedule.

Voice is off by default. When you turn it on in the gear menu, Ask gets a mic button that uses on-device speech recognition only, and answers are read out by the Mac's own voice. Open at login is in the same menu.

## Build and install

Needs Xcode 26 or later. The only dependencies are Apple frameworks.

```bash
xcodebuild -project Docket.xcodeproj -scheme Docket -configuration Release -derivedDataPath build/dd build
pkill -x kip; rm -rf ~/Applications/kip.app && cp -R build/dd/Build/Products/Release/kip.app ~/Applications/
open ~/Applications/kip.app
```

To add the widget, right-click the desktop and choose Edit Widgets. Then search for kip.

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
~/Applications/kip.app/Contents/MacOS/kip --svg Design/robot
```

## Checks

```bash
python3 scripts/test_docket_widget_write.py
~/Applications/kip.app/Contents/MacOS/kip --selftest
~/Applications/kip.app/Contents/MacOS/kip --snapshot build/snap
~/Applications/kip.app/Contents/MacOS/kip --companion-shot build/snap-companion
```

`--selftest` checks the mood rules, the stale cut-off, the 07:00/22:00 boundaries, the due labels, the large widget's row budget, the new brief and scan keys, the 3-hour agents cut-off and the robot's path parser. `--snapshot` writes `docket-light.png`, `docket-dark.png` and `robot-moods.png` to the folder you give it. The widget images show every mood, the stale state and a crowded day in all three sizes, drawn from the real data file. The mood sheet shows every mood at 32, 44, 64 and 120 pt, in colour and in grayscale, plus the menu-bar glyphs.

`--selftest` also checks the task parser, schedules and their LaunchAgent plists, task ids, the overdue alert's dedupe and quiet hours, the engine guess, and that headless Claude gets read-only tools. `--companion-shot` writes the popover's tabs, the task editor and the menu-bar icon for each mood.

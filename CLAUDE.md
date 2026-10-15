# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ClaudeBar is a macOS menu bar app for Claude Code, published as open source (MIT) at `github.com/nazaryuzhyn/claude-bar`. It shows the 5-hour and weekly rate limits with a pace tick, lists sessions (working / waiting / done), and plays a sound and posts a banner when a session finishes or waits for input. The Claude mark (`Resources/Icons/claude.pdf`, also inside the app icon) stays by the owner's decision, with the trademark disclaimer in `README.md` and `THIRD_PARTY_NOTICES`.

- **Commits and pushes only on the owner's explicit request**, one action at a time.
- **`docs/` is git-ignored local working notes** (Ukrainian): the design spec `docs/specs/2026-10-13-claudebar-design.md`, the original plan, and `docs/claudebar-worklog.md`. When `docs/` exists, keep the worklog current: numbered entries with every decision, correction and rejected alternative, appended as you work. Never reference `docs/` from tracked files as if readers had it.
- **The UI has two languages, Ukrainian and English** (`Language`, chosen in Settings, defaulting to the system's first language). Every user-facing string lives in `Texts` with both variants side by side (`pick("…", "…")`); add both whenever you add one. `README.md` is in English.
- **Main requirement: minimal CPU and memory while running.** No polling. Measure before/after for anything on the reload path (see "Measuring" below).

## Commands

Only Command Line Tools are installed (Swift 6.4, SDK MacOSX27.0, no Xcode). Run everything from the repo root.

```bash
scripts/test.sh                                    # Swift Testing suite (ClaudeBarCoreTests)
scripts/test.sh --filter LimitsAggregatorTests     # one suite
scripts/test.sh --filter "LimitsAggregatorTests/readingsOfAnEarlierWindowAreLeftOut"  # one test
scripts/test-hooks.sh                              # shell tests for hook.sh and the bridge (temp CLAUDEBAR_DIR)
scripts/test-install.sh                            # configure.sh and statusline.sh against a scratch HOME
scripts/install.sh                                 # full install: test-hooks + test-install, bundle, scripts to bin/, configure.sh install, launch
scripts/uninstall.sh                               # configure.sh uninstall, quit, delete the app and the data folder
scripts/bundle.sh                                  # app only: release build, ad-hoc sign with sandbox, install to ~/Applications, restart if running
swift build --scratch-path ~/Library/Caches/ClaudeBar/build   # debug build only
```

- `scripts/test.sh` passes `-plugin-path …/plugins/testing` because CLT ship no XCTest and swiftc does not find the Swift Testing macro plugin on its own. Use it, not plain `swift test`.
- Always build with `--scratch-path ~/Library/Caches/ClaudeBar/build`. Bundles built under the iCloud-synced `~/Desktop` get `com.apple.FinderInfo` xattrs, and `codesign` rejects them as "detritus".
- `~/Library/Caches/ClaudeBar/build/debug/ClaudeBar --snapshot <dir>` renders the panel and the label to PNG in light and dark. Use the unsandboxed debug build. Set `CLAUDEBAR_DIR=<dir>` to render from fixture data and pass `-language en|uk` (an argument-domain default, so nothing is persisted). For the Claude mark instead of the SF Symbol fallback, run a copy of the binary with `claude.pdf` next to it. The README screenshots in `assets/` were made this way from invented demo sessions; never use real session names. `screencapture` does not work here: there is no Screen Recording permission.
- `log stream --level debug --predicate 'subsystem == "local.claudebar"'` shows every reload ("Read N limits and M sessions"), notification decisions, window fitting, and panel visibility and timer ticks.
- `scripts/generate-sounds.py` and `scripts/generate-icon.swift` regenerate the committed WAVs and the icon.
- Wrap long or risky runs in `perl -e 'alarm N; exec @ARGV' …`. Never let a test write into `scripts/`: a test once overwrote `hook.sh` with the harness and fork-bombed the machine. `test-hooks.sh` now refuses to start from inside itself (`CLAUDEBAR_HOOK_TESTS`).

## Architecture

Two shell scripts write JSON records; the sandboxed app watches the folders and renders them. Data lives in `~/Library/Application Support/ClaudeBar/` (folders 0700, files 0600):

```
Claude Code status line ─► bin/statusline-bridge.sh ─► limits/<session_id>.json   (rate_limits, cost, session_name)
Claude Code hooks       ─► bin/hook.sh              ─► events/<session_id>.json   (state, cwd, title, host, message, at)
                                                            │ DispatchSource on both folders, 200 ms coalescing
ClaudeBar.app ─► RecordFolder ─► LimitsAggregator / SessionList / TransitionDetector / ThresholdTracker ─► AppModel ─► MenuBarLabel, PanelView
```

- **`ClaudeBarCore`** (library, fully unit-tested, fixed-clock fixtures in `Tests/…/Fixtures.swift`) holds all logic. That covers decoding (`Records`, `RecordFolder`) and aggregation (`LimitsSummary`). It covers pace (`Pace`), session rows and ageing (`Sessions`), and transitions and thresholds (`Transitions`). It covers banner policy (`NoticePolicy`), the sound cooldown (`SoundGate`) and wake planning (`WakePlanner`). All wording, in both languages, is in `Texts`; `AppModel.texts` follows the `language` setting.
- **`ClaudeBar`** (executable) is the SwiftUI/AppKit glue: `AppModel` (`@MainActor @Observable`), `FolderWatcher`, `Notifier`, the views.
- The app reads; the scripts write. Each session writes only its own file, so concurrent sessions never collide.
- **Wiring into Claude Code** is `scripts/configure.sh install|uninstall` for the profile in `CLAUDE_CONFIG_DIR` (default `~/.claude`), and `uninstall-all` for every profile listed in `ClaudeBar/profiles`. Each profile's original status line is saved under its own name (`statusline-original`, or `statusline-original-<md5 of the config dir>` for other profiles: one name per folder, in any locale), derived the same way in `statusline.sh`, which runs it with `/bin/sh -c` as Claude Code would. `CLAUDE_CONFIG_DIR` must be absolute. `configure.sh` writes `settings.json` through a symlink and keeps its mode, writes it before anything else and stops on failure, only wraps a status line of type `command` with a `command`, and on uninstall drops only what ClaudeBar's entries left empty. When a profile's saved original is missing (a v0.1.0 install), uninstall removes the wrapper and points to the backups. In tests, `CLAUDEBAR_MANAGED_DIR` and `CLAUDEBAR_MDM_DIR` point the policy check away from the machine's real policy. It touches only ClaudeBar's hook entries (matched by `ClaudeBar/bin/hook.sh` in the command) and the status line, backs up `settings.json` before any change, refuses a broken one, and is idempotent. The status line: a user with one gets `bin/statusline.sh`, which feeds the bridge and then runs the saved original; uninstall restores it. A user without one gets none (the owner's decision: not everyone wants a status line, and the app must work it out itself rather than through an install flag); hooks alone give sessions and alerts, and the panel says limits need a status line (`SessionList.statusLineLooksMissing`: Claude answered, yet no status line data). Settings then offers **Limits → Turn on**: the sandboxed app cannot edit Claude Code's settings, so it leaves the marker `events/statusline-request` (`StatusLineRequest`); the next hook event removes it and runs `bin/configure.sh add-statusline`, which adds ClaudeBar's minimal status line only where there is none. The marker carries no data, so a compromised app can request nothing but that fixed status line. Installs before 0.2 got the wrapper with an empty saved original; it still prints a minimal `Model · folder` for them. A status line that already mentions `statusline-bridge.sh` (directly or in a script it names) is left alone. The owner's own setup is such a manual one, so `install.sh` changes nothing in their settings.

### Rules that are not obvious from one file

- **No polling.** After each reload `WakePlanner` sets one one-shot timer for the next meaningful moment: a window reset, a session turning "unknown" or hidden, or hourly cleanup. A 30 s timer runs only while the panel is visible. Wake from sleep, a clock change and a time zone change re-plan via notifications.
- **Panel visibility comes from the window, not SwiftUI.** `MenuBarExtra(.window)` never calls `onDisappear` when the panel closes. `PanelVisibility` observes `NSWindow.didChangeOcclusionStateNotification` instead. `onAppear`/`onDisappear` were removed for this reason.
- **Redraw economy.** On Swift 6.4, `@Observable` skips an assignment of an equal `Equatable` value. `summary` still changes on every limits write (`lastObservedAt`). So the label reads only `menuBarFigure` (kind, percent text, resetsAt) and `waitingCount`. `now` moves only while the panel is visible. Keep new label inputs free of observation timestamps.
- **Limit selection.** Usage only grows within a window, but an idle session's file can be rewritten with old figures. So per window: take the latest `resets_at` (readings within `WindowKind.sameWindowTolerance` = 1 h count as the same window), then the highest `used_percentage` among them, clamped to 0–100. The menu bar shows the more-used window, the 5-hour one on a tie.
- **Plans without limits.** Claude Code documents `rate_limits` in the status line for Pro and Max only, and only after the session's first API response. The bridge records `answered` once `cost.total_api_duration_ms` is positive; only then does a profile without windows count as `planReportsNoLimits`, and the panel shows today's cost at API prices instead of bars. Before the first reply it says limits will appear. With limits present, cost is never shown (the owner removed it on purpose).
- **Profiles.** The bridge records `config_dir` only when `CLAUDE_CONFIG_DIR` is set and is not `~/.claude`, so `nil` is the default profile, old records included. `LimitsAggregator.summarizeProfiles` gives each profile its own `LimitsSummary` (figures of two accounts must never mix); `profile` is the display name, set only when there are several, `configDir` keys threshold alerts by full path (`ThresholdTracker.key`, the bare kind for the default profile, as stored before profiles existed). The panel shows a block per profile; the menu bar shows the most used one (`LimitsAggregator.menuBarFigure(of:)`), named for VoiceOver and in the alert title.
- **Private mode.** The app keeps a marker file `events/private-mode` (no `.json`, no leading dot, so `RecordFolder` and `FolderCleanup` pass it by); the hook and the bridge check it with `-e` and then store no title, message or session name. Switching it on also strips those keys from existing files (`PrivateMode.apply`) and removes delivered `session:*` banners from Notification Center. `reload()` shows records through `PrivateMode.shown` and strips again whenever a record written in the switching moment still holds a text (`needsStripping`); the strip skips a file a script rewrote in the meantime.
- **Company policy.** Managed settings outrank user settings. `configure.sh install` reads `/Library/Application Support/ClaudeCode/managed-settings.json`, its `managed-settings.d/*.json` drop-ins and the `com.anthropic.claudecode` MDM plist, and warns on `disableAllHooks`, `allowManagedHooksOnly` and a managed `statusLine`. Server-managed settings are not on disk. In the app, `hooksLookBlocked` (status line data, but no hook event ever seen, remembered in defaults because `SessionEnd` deletes records) shows `Texts.noSessionEvents`.
- **Decoding is defensive.** Dates outside 2000–2100 make a record "damaged"; huge values once crashed the app on every launch via `Int` overflow. A damaged file keeps that session's last good record and is logged once.
- **Notifications.** `TransitionDetector` takes its first read as a baseline, so a launch replays nothing. A session first seen later is announced only if its event is under 5 min old. No banner while the session's host app (bundle id found by `hook.sh` walking the process tree) is frontmost; the sound still plays. `Notifier` re-reads authorization before every notice, because `UNUserNotificationCenter.add` succeeds even when notifications are denied.

### Trust boundary (scripts ↔ sandbox)

The app is sandboxed with no network and read-write access only to `limits/` and `events/` (`Resources/ClaudeBar.entitlements`). `bin/` is out of reach on purpose. The scripts run outside the sandbox and read files the app can write, so treat everything in those folders as hostile:

- Temp files go in `ClaudeBar/` itself (`.<id>.limits.<pid>` / `.<id>.event.<pid>`), never inside the watched folders, then `mv -fh`. Inside the watched folders a temp file could be swapped for a symlink, and creating it would wake the app.
- The previous record is opened once by a `perl` one-liner with `O_NOFOLLOW | O_NONBLOCK` and read only if the open handle is a regular file (≤64 KB), then parsed with `jq --arg … | try fromjson`. A `[ -f ] && [ ! -L ]` check before `jq --rawfile` was raceable (the app could swap in a symlink to read other files, or a FIFO to hang the script; proven in review). Values from it never reach bash arithmetic unless they match `^[0-9]+$`, because `$((…))` executes `a[$(cmd)]`.
- The payload goes to jq on stdin, never `--argjson` (ARG_MAX ≈ 1 MB). `session_id` must match `^[A-Za-z0-9_-]+$`.
- Scripts print nothing, always exit 0, use `umask 077`, and run under `/bin/bash` 3.2 with jq 1.7.1. Write-skipping matters for CPU: the bridge skips a record that differs only in `observed_at`/`cost` while the previous one is under 60 s old, and the hook throttles `PostToolUse` for a working session to once a minute.

### Bundle id and banner icon

The bundle id is `local.claudebar.menubar`. Notification Center caches a banner icon per bundle id. Neither a new `CFBundleVersion`, a renamed icon file, `lsregister -f` nor killing `usernoted` refreshes it. A changed icon reaches banners only with a new bundle id. The cost of that: notification permission must be re-enabled in System Settings (it came back as denied, without a prompt), defaults reset, and a new sandbox container appears. Containers of old ids can only be removed by the owner.

## Measuring

- **Benchmark:** run the release binary unsandboxed with `CLAUDEBAR_DIR` pointing at a copy of the real data. Rewrite one limits file 60 times with only `observed_at` changed. Compare `ps -o time=` before and after.
- **Live:** count "Read " lines in `log stream` over 1–2 minutes, plus `footprint <pid>` for `phys_footprint`.
- Session activity varies a lot, so compare live numbers only against a benchmark taken in the same session.

---
name: poni-ui-check
description: See Poni's UI without clicking around: render every popover tab, notch tab and the games page to PNGs (light/dark, Indonesian or English), and stack them for review. Use after any UI change, when checking design consistency, or when hunting untranslated strings.
---

# Check Poni's UI by rendering it

The popover (MenuBarExtra) and the notch can't be opened reliably by automation:
AppleScript `click` on SwiftUI presses several buttons at once (it once jumped the calendar
to May 2022), and synthetic mouse clicks land on the wrong spot on this Mac. Clicking
blindly can also hit real user data (Clipboard delete buttons). So render instead.

## Render

```sh
.claude/skills/poni-ui-check/snap.sh <scratchpad>/shots        # Indonesian
.claude/skills/poni-ui-check/snap.sh <scratchpad>/shots-en en  # English; missing translations show in CAPITALS
```

Output: `panel-<Tab>-light|dark.png`, `notch-<Tab>.png`, `game-ular|kartu|xo|catur|hangman|sudoku.png`.
Stack several into one image to review them in one read:

```sh
swift .claude/skills/poni-ui-check/stack.swift out.png a.png b.png c.png
```

## Reading the renders

- **Yellow boxes with 🚫** are AppKit-backed controls (`Toggle`, `Slider`, `TextField`, `Picker`, `Stepper`) that `ImageRenderer` can't draw. Not a bug.
- **Empty ScrollView content** (Git, Clipboard, AI chat) is also a renderer limit; check the code for the empty state instead.
- **Ring labels floating above Stats cards** are a mid-animation artifact; a live screenshot shows them correctly.
- **Dimmed tabs** (Sistem, Cleaner) can be the renderer catching a loading state.
- The **Rapat** tab is skipped: rendering it asks for Calendar access.

## Live check (when a render isn't enough)

- Run the real app: `pkill -f 'Poni.app/Contents/MacOS/baterai-safer$'; scripts/bundle.sh dev-local && open .build/Poni.app`.
  The `$` matters: the root helper runs the same binary as `… baterai-safer daemon`; never match it (it can't be
  killed without root anyway, and stopping it would stop the charge limiter).
  **Build release first** (`swift build -c release`): `bundle.sh` copies whatever binary is in `.build/release` (a stale binary once shipped a hang).
- Open the notch with ⌃⌥Space (`osascript -e 'tell application "System Events" to key code 49 using {control down, option down}'`), a tab with its shortcut (⌃⌥R Rapat, ⌃⌥N Catatan, …), then `screencapture -x -R355,0,760,340 out.png`.
- Don't pass `-AppleLanguages` on the command line: `main.swift` treats unknown args as a bad command and exits. Use `defaults write io.github.lshinkuro.BateraiSafer AppleLanguages -array en`, launch, then `defaults delete …` right after.
- New builds trigger permission prompts (Calendar, Downloads, Automation). Leave those to the user.
- Put the user's installed app back when done: `pkill -f .build/Poni.app; open /Applications/Poni.app`.

## Keeping the harness working

`Snap.swift` builds views directly (`BatteryTab(m:)`, `MusicView(m:)`, `GamesPage()`…). When a view's
initializer or a tab enum changes, update the harness to match.

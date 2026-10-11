# Mochi 🍡🌱

A cute break-timer pet for macOS. A little mochi blob with a leaf sprout floats on your screen. It works alongside you, yawns when a break is near, and bounces with a tip when it's time to rest.

![Mochi's poses](docs/poses_light.png)

## Features
- **Floating mascot.** It's always on top, draggable, and never steals focus. It shows on every Space and over fullscreen apps. Choose Small, Medium or Large.
- **Menu bar countdown** (`🌱 19:42`), with a popover for these controls:
  - Start, Pause / Resume, Take break now, Skip, Snooze, Reset and Stop
  - **−1 / +1 / +5 min** to adjust the time while the timer runs
- **Presets:**
  - Gentle 🌱 (default): 20 min focus, then a 20 s eye break. Every 3rd break is a 5 min stretch.
  - Pomodoro 🍅: 25/5, with a 15 min break every 4th.
  - Deep Focus 🌊: 52/17.
  - Custom ✨: choose your own lengths.
- **Gentle nudges:**
  - Mochi bounces and shows a tip bubble.
  - A notification with **Start break / Snooze 5 min / Skip**.
  - An optional soft chime.
  - Snooze is limited to 2 per break.
- **Mochi's moods:** working, almost done (yawning), break time (bouncing and waving), on break (sleeping Zzz) and paused (droopy sprout).
- **Click Mochi** to start the timer, start a due break, or resume from pause.
- **Stepping away counts.** Being idle, locked or asleep for 5 minutes or more counts as a break you took, and Mochi starts a fresh focus when you're back.
- Open at login, start automatically, show or hide Mochi, sound on or off.
- **Calm mode** (on by default): motion runs in Core Animation, so Mochi uses about 1% CPU while visible, against about 7% in full mode.
- Honours Reduce Motion, light and dark mode.

## Build & run
You only need the Command Line Tools, not Xcode.

```bash
./build.sh
```

This builds the app, installs it to `~/Applications/Mochi.app` and launches it. Use `NO_OPEN=1 ./build.sh` to build without launching.

Run the checks:

```bash
swift run MochiChecks
```

Render the mascot poses to PNG:

```bash
swift run MochiPreview ./previews
```

### Debug switches
`MOCHI_CALM=0/1` forces full or calm animation. `MOCHI_POSE=breakDue` (or another pose) forces a pose.

### Fast demo mode
Use short timers to watch a whole cycle in seconds:

```bash
MOCHI_FOCUS_SECONDS=8 MOCHI_BREAK_SECONDS=6 MOCHI_IDLE_SECONDS=20 ~/Applications/Mochi.app/Contents/MacOS/Mochi
```

## Project layout
| Target | What's in it |
|---|---|
| `MochiCore` | Pure logic: `TimerEngine` state machine (based on end dates, so it survives sleep), `Preset`, `Tips`, `MochiSettings`, `AwayPolicy` |
| `MochiUI` | Mascot drawn entirely with SwiftUI shapes (no image assets), poses, progress ring, speech bubble, `FloatingPanelController` |
| `Mochi` | The app: `AppModel` (single owner), menu bar view, `MascotHost` (engine → pose), `Nudger` (notifications and sound), `SystemMonitor`, `LaunchAtLogin` |
| `MochiChecks` | Logic checks (`swift run MochiChecks`) |
| `MochiPreview` | Renders poses and sizes to PNG for design review |

### Toolchain notes (this machine)
- **SwiftPM manifest fix.** Leftover Swift 5.10 `PackageDescription.private.swiftinterface` files in the Command Line Tools broke every package manifest. They were renamed to `.bak`.
- **Tests run through `MochiChecks`.** The installed `Testing.framework` is mismatched and silently discovers zero tests. Reinstalling the Command Line Tools should fix that, and then the checks could move back to Swift Testing.

## Opening in VS Code
```bash
code .
```

Install the **Swift** extension (swiftlang). Build and run with `./build.sh`.

## Ideas for v2
- Detect fullscreen video and meetings (camera or mic in use), and hold nudges until they end.
- A global hotkey to start, pause or show the popover.
- Gentle stats: breaks taken today and a weekly streak, shown as a little garden that grows.
- More mascot skins (cat, sprout, cloud) and seasonal accessories.
- A sparkle burst when a break completes. The sprout reacts to clicks.
- A Shortcuts and Focus mode integration.

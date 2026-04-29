# Grabbit

| Logo | What is it? |
|---|---|
| ![Grabbit Icon](./grabbit_logo.png) |  A lightweight macOS screenshot and annotation tool that lives in your menu bar. Trigger a capture with a global hotkey, draw a selection, then annotate and export — all without touching the Dock. |

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Global hotkey capture** — press the shortcut from any app to start a region screenshot
- **Region selection** — drag to select any area of the screen on a full-screen overlay
- **Annotation tools**
  - Arrows — draw, move, resize the tail, delete
  - Text — click to place, double-click to edit inline, configurable font/size/color/outline
  - Shapes — rectangle, circle, rounded rectangle with configurable border and fill
- **Image effects** — optional border and drop shadow (offset, blur, opacity)
- **Zoom** — 0.1× to 8× magnification with +/− buttons or pinch gesture
- **Export** — Save As PNG/JPEG/TIFF via the title bar button, or copy to clipboard
- **Persistent preferences** — all tool settings and the hotkey are saved across launches
- **Configurable shortcut** — change the hotkey from the Settings dialog; the menu bar item always reflects the current shortcut

---

## Installation

Pre-built binaries are attached to each [GitHub Release](https://github.com/recursivecodes/grabbit/releases).

1. Download **Grabbit.zip** from the latest release and unzip it.
2. Move **Grabbit.app** to your `/Applications` folder.
3. **Remove the quarantine attribute.** Because Grabbit is unsigned, macOS Gatekeeper will block it on first launch. Run this once in Terminal:
   ```bash
   xattr -dr com.apple.quarantine /Applications/Grabbit.app
   ```
4. Open Grabbit from `/Applications` or Spotlight.

> macOS will still ask for **Screen Recording** permission on first launch — this is required for the capture to work. You can also grant it manually in **System Settings → Privacy & Security → Screen Recording**.

---

## Requirements

- macOS 13 Ventura or later
- Xcode command-line tools (`xcode-select --install`) — for building from source only
- Screen Recording permission (the app will prompt on first launch)

---

## Building from source

```bash
bash build.sh
```

This compiles all Swift sources, generates the app icon, and produces `build/Grabbit.app`.

To run immediately after building:

```bash
open build/Grabbit.app
```

The build script uses `swiftc` directly — no Xcode project or Swift Package Manager required.

### Releasing

Push a version tag to trigger the GitHub Actions workflow, which builds the app and publishes a release with `Grabbit.zip` attached:

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## Usage

### Taking a screenshot

1. Press the global hotkey (default **⌥⇧P**) from any app.
2. The screen dims and a crosshair cursor appears.
3. Click and drag to select the region you want to capture.
4. Release — the editor opens with your selection.

Press **Escape** at any point during selection to cancel.

### Annotating

Select a tool from the toolbar at the top of the editor:

| Tool | How to use |
|------|-----------|
| **Arrow** | Click-drag to draw. Drag the tail handle to reposition the start point. Drag the body to move the whole arrow. |
| **Text** | Click to place a text box. Double-click an existing label to edit it inline. Drag to reposition. |
| **Shape** | Click-drag to draw. Drag the bottom-right handle to resize. Drag the body to move. |

Select any annotation and press **Delete** or **Backspace** to remove it. Right-click for a context menu.

### Adjusting effects

The sidebar on the right has two tabs:

- **Properties** — tool-specific settings (weight, color, font, shape type, etc.)
- **Effects** — border and drop shadow toggles with sliders for weight, offset, blur, and opacity

All settings are saved automatically and restored on the next launch.

### Exporting

- **Save As…** — click the button in the title bar to save as PNG, JPEG, or TIFF
- **Copy** — press **⌘C** or right-click → Copy Image to copy the annotated image to the clipboard

---

## Changing the keyboard shortcut

1. Click the menu bar icon and choose **Settings…**
2. Click the shortcut field — it enters recording mode.
3. Press the new key combination (must include at least one of ⌘, ⌥, or ⌃).
4. Click **Save**.

The menu bar item title and icon tooltip update immediately to show the new shortcut. Press **Escape** in the recorder to cancel without changing anything.

The shortcut is stored in `UserDefaults` and persists across relaunches.

---

## Project structure

```
Sources/
  main.swift                    — entry point, sets up NSApplication
  AppDelegate.swift             — menu bar icon, status menu, hotkey wiring
  HotkeyManager.swift           — Carbon hotkey registration + HotkeyConfig model
  SettingsWindowController.swift — settings dialog with hotkey recorder
  CaptureSession.swift          — screen capture via CGDisplayCreateImage
  OverlayWindowController.swift — full-screen selection overlay
  AnnotationOverlay.swift       — annotation rendering and interaction (arrows, text, shapes)
  EditorWindowController.swift  — editor window, sidebar, zoom, export

Resources/
  Info.plist                    — bundle metadata

build.sh                        — single-command build script
make_icon.swift                 — generates the app icon set
```

---

## Permissions

Grabbit requires **Screen Recording** permission to capture the display. On first launch macOS will prompt you. If you decline, you can grant it later in:

**System Settings → Privacy & Security → Screen Recording**

The app does not require network access or any other permissions.

---

## License

MIT

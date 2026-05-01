# Grabbit

| Logo | What is it? |
|---|---|
| ![Grabbit Icon](./grabbit_logo.png) |  A lightweight macOS screenshot and annotation tool that lives in your menu bar. Trigger a capture with a global hotkey, draw a selection, then annotate and export — all without touching the Dock. |

![macOS](https://img.shields.io/badge/macOS-13%2B-blue) ![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## Sponsor

If you find this app helpful, please consider buying me a coffee ☕️❤️!

[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/toddraymont)

## Features

- **Global hotkey capture** — press the shortcut (default ⌥⇧P) from any app to start a region screenshot
- **Quick Capture** — a second hotkey (default ⌥P) captures a region and copies it straight to the clipboard without opening the editor; sends a system notification on copy
- **Region selection** — drag to select any area of the screen on a full-screen overlay
- **File menu** — Open… (⌘O), New from Clipboard (⌘N), Close Image (⌘W), Save (⌘S), and Save As… (⌘⇧S); supports PNG, JPEG, TIFF, BMP, GIF, HEIC, and WebP
- **Annotation tools**
  - Arrows — click-drag to draw; drag the tail handle to reposition; drag the body to move
  - Text — click to place, double-click to edit inline; configurable font, size, color, and outline
  - Shapes — rectangle, circle, rounded rectangle with configurable border and fill
  - Blur / Pixelate — draw a rectangle to obscure any region; choose Gaussian Blur or Pixelate style; intensity slider 1–100
  - Highlight — draw a semi-transparent color band over any region; configurable color and opacity
- **Layer arrangement** — right-click any annotation to Bring to Front, Bring Forward, Send Backward, or Send to Back; z-order is respected in both the preview and the exported image
- **Clicking to select** — click any annotation in no-tool mode to automatically activate the correct tool and select that annotation
- **Image effects** — optional border and drop shadow (offset, blur, opacity)
- **Zoom** — 0.1× to 8× magnification with +/− buttons or pinch gesture
- **Export** — Save As PNG/JPEG/TIFF, or copy to clipboard (⌘C)
- **Persistent preferences** — all tool settings and hotkeys are saved across launches
- **Two configurable shortcuts** — change the capture hotkey and the quick-capture hotkey independently in Settings

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

### Local code signing (recommended)

Without a code signing certificate, macOS TCC will prompt you for Screen Recording permission on **every new build** because it tracks permission by binary identity, which changes each time you compile.

To fix this, create a local self-signed certificate once. macOS will then recognise the same identity across all future builds and the permission prompt won't reappear.

**One-time setup:**

1. Open **Keychain Access** (Applications → Utilities → Keychain Access)
2. From the menu: **Keychain Access → Certificate Assistant → Create a Certificate…**
3. Fill in the fields:
   - **Name:** `Grabbit Dev` (must match exactly)
   - **Identity Type:** Self Signed Root
   - **Certificate Type:** Code Signing
4. Click **Create**, then **Done**

That's it. The build script will automatically find and use the certificate on every subsequent build. Grant Screen Recording permission once after the first signed build and it will persist.

### Releasing

Push a version tag to trigger the GitHub Actions workflow, which builds the app and publishes a release with `Grabbit.zip` attached:

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## Usage

### Taking a screenshot

1. Press the capture hotkey (default **⌥⇧P**) from any app.
2. The screen dims and a crosshair cursor appears.
3. Click and drag to select the region you want to capture.
4. Release — the editor opens with your selection.

Press **Escape** at any point during selection to cancel.

For a faster workflow, press the **Quick Capture** hotkey (default **⌥P**) to capture a region and copy it directly to the clipboard — the editor never opens.

You can also open the editor without capturing: click the menu bar icon and choose **Open Editor**, then use **File → Open…** or **File → New from Clipboard** to load an image.

### Annotating

Select a tool from the toolbar at the top of the editor:

| Tool | How to use |
|------|-----------|
| **Arrow** | Click-drag to draw. Drag the tail handle to reposition the start point. Drag the body to move the whole arrow. |
| **Text** | Click to place a text box. Double-click an existing label to edit it inline. Drag to reposition. |
| **Shape** | Click-drag to draw. Drag the bottom-right handle to resize. Drag the body to move. |
| **Blur / Pixelate** | Click-drag to draw a blur region. Choose Gaussian Blur or Pixelate in the sidebar. Use the Intensity slider to control how strongly the content is obscured. |
| **Highlight** | Click-drag to draw a highlight band. Choose the color and opacity in the sidebar. |

Click any annotation while no tool is active to select it — the correct tool activates automatically. Select any annotation and press **Delete** or **Backspace** to remove it. Right-click for a context menu including layer arrangement (Bring to Front, Bring Forward, Send Backward, Send to Back).

### Adjusting effects

The sidebar on the right has two tabs:

- **Properties** — tool-specific settings (weight, color, font, shape type, etc.)
- **Effects** — border and drop shadow toggles with sliders for weight, offset, blur, and opacity

All settings are saved automatically and restored on the next launch.

### Exporting

- **Save** (⌘S) — writes to the last-used file path; falls back to Save As on first save
- **Save As…** (⌘⇧S) — choose a new path and format (PNG, JPEG, TIFF)
- **Copy** — press **⌘C** or right-click → Copy Image to copy the annotated image to the clipboard

---

## Changing the keyboard shortcuts

Grabbit has two configurable hotkeys: the main **Capture** shortcut (opens the editor after capture) and the **Quick Capture** shortcut (copies to clipboard silently).

1. Click the menu bar icon and choose **Settings…**
2. Click the shortcut field you want to change — it enters recording mode.
3. Press the new key combination (must include at least one of ⌘, ⌥, or ⌃).
4. Click **Save**.

The menu bar item updates immediately. Press **Escape** in the recorder to cancel without changing anything.

Both shortcuts are stored in `UserDefaults` and persist across relaunches.

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

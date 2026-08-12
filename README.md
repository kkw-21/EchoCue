# EchoCue

EchoCue is an open-source, voice-following teleprompter for macOS. It floats below your camera, keeps the previous, current, and next cue visible, and advances as you speak—while staying out of supported screenshots and recordings.

## Features

- Native SwiftUI and AppKit; no Electron runtime
- Previous/current/next cue layout designed for eye contact
- English and Chinese script segmentation
- Live speech recognition with fuzzy, ordered-word matching
- Editable voice escape phrases for missed sentence endings
- Configurable global next-cue key that works even when speech recognition stops
- Resizable, movable, always-on-top overlay across Spaces
- Menu-bar controls and persistent appearance settings
- Best-effort capture exclusion with `NSWindow.sharingType = .none`

## Install

Download the latest macOS build from [Releases](https://github.com/KKW-21/EchoCue/releases), or build it locally:

```sh
git clone https://github.com/KKW-21/EchoCue.git
cd EchoCue
./build-app.sh
open dist/EchoCue.app
```

EchoCue requires macOS 13 or newer. On first launch, allow Microphone and Speech Recognition access. The global next-cue key uses the macOS hot-key system and does not require Input Monitoring access.

Release builds are ad-hoc signed rather than Apple-notarized. If Gatekeeper blocks the first launch, Control-click the app, choose **Open**, and confirm once.

## Use

1. Paste or import a script.
2. Click **Split & Load**.
3. Move the overlay below your camera.
4. Click **Start Listening** and begin speaking.

If recognition misses the end of a cue, say an editable skip phrase—`you know`, `you know what I mean`, `for example`, `next line`, `下一句`, or `换行`—or press the global next-cue key. It defaults to `Tab`, can be changed to Right Arrow or Space, and works whenever EchoCue is running—even when another app has focus or speech recognition has stopped. Because it is global, the selected key is reserved by EchoCue until you disable the shortcut or quit the app. Partial recognition updates trigger each spoken command only once.

## Privacy

EchoCue contains no analytics or third-party SDKs. Speech recognition runs on-device when the installed macOS speech recognizer supports it; otherwise Apple's Speech framework may use its online recognition service. Your script is stored locally in `UserDefaults`.

## Capture protection

When **Hide overlay from recordings** is enabled, EchoCue marks the overlay window as non-shareable. This works with macOS screenshots and capture tools that respect per-window sharing settings, but it is not a DRM or security boundary. Full-display recording tools and future macOS versions can behave differently. Always make a short test with your exact recorder and capture mode.

## Development

```sh
swift test
swift build
```

The app bundle is assembled and ad-hoc signed by `build-app.sh`.

## License

[MIT](LICENSE)

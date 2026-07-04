# Exbright

Exbright is a lightweight macOS menu bar app for controlling external display brightness with the standard brightness keys.

## Install

```sh
brew install --cask schroneko/exbright/exbright
```

Or download `Exbright-1.2.0.zip` from the releases page.

## Features

- Controls external display brightness from F1/F2 brightness keys
- Supports long-press key repeat
- Uses DDC/CI where available
- Uses MonitorControl-style combined brightness behavior for displays that need it
- Shows the native macOS brightness OSD
- Restores the saved brightness after launch and wake
- Provides a minimal menu bar UI

## Notes

Exbright currently focuses on external display brightness control. It does not include MonitorControl's settings UI, sliders, custom shortcuts, contrast controls, or update framework.

The app may require Accessibility permission for media key handling on some macOS configurations.

## Build

```sh
xcodebuild -project MonitorControl.xcodeproj \
  -scheme MonitorControl \
  -configuration Release \
  build
```

## License

Exbright is distributed under the MIT License.

This app is derived from MonitorControl, which is also distributed under the MIT License. The original license notice is preserved in `License.txt`.

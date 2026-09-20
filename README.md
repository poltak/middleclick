# MiddleClick

Simple macOS menu-bar app that turns a **3-finger trackpad click or tap** into a **middle mouse click**.

## What it does

- Runs as a standard `.app` (`LSUIElement` menu-bar utility).
- Recognizes a three-finger tap only when exactly three fingers arrive together,
  remain nearly stationary, and lift within the gesture time limit.
- Converts a physical three-finger press into middle-button down, drag, and up
  events, preserving the pointer location and modifier keys.
- Tracks each multitouch device independently and reconnects devices after
  sleep or connection changes.
- Pauses remapping when macOS Three Finger Drag is on. When three-finger Look
  Up is on, physical clicks continue to work while tap remapping is paused.
- Recovers from event-tap timeouts and permission changes without leaving the
  middle button held.
- Shows live input frame and output counters in the menu for troubleshooting.

## Build App Bundle

```bash
./scripts/build-app.sh
```

App bundle output:

```bash
dist/MiddleClick.app
```

## Run App

```bash
open dist/MiddleClick.app
```

For a stable app identity (recommended), install to `/Applications`:

```bash
./scripts/build-app.sh --install
open /Applications/MiddleClick.app
```

On first run, grant permissions when prompted.

Required permissions:

- `System Settings -> Privacy & Security -> Accessibility`
- Add/enable the exact app you run (recommended: `/Applications/MiddleClick.app`).

If middle-clicking does not work in some apps, also enable:

- `System Settings -> Privacy & Security -> Input Monitoring`
- Add/enable `MiddleClick.app`.

## Notes

- Uses a private Apple framework (`MultitouchSupport`), so this is not App Store safe.
- Keep the app running in the menu bar to keep remapping active.
- Turn off Three Finger Drag and three-finger Look Up in System Settings to use
  the three-finger middle-click gesture.
- Locally built apps use an ad-hoc signature with a stable designated
  requirement. Moving the app or changing its bundle identifier may still
  require Accessibility permission to be granted again.

## Tests

```bash
swift test
```

The tests cover valid staggered and held taps, swipes, raw touch states, extra
or delayed fingers, rapid independent taps, and physical-click consumption.

## GitHub Releases

Create a tag like `v1.2.3` and push it:

```bash
git tag v1.2.3
git push origin v1.2.3
```

The GitHub Actions workflow at `/Users/jon/Documents/github/middleclick/.github/workflows/release.yml` will:

- Build and sign `MiddleClick.app`
- Create `dist/MiddleClick.app.zip`
- Generate `dist/MiddleClick.app.zip.sha256`
- Create `dist/MiddleClick.dmg`
- Generate `dist/MiddleClick.dmg.sha256`
- Generate `dist/middleclick-poltak.rb` (Homebrew cask file)
- Publish all files to the GitHub Release

For local dry-runs of release packaging:

```bash
./scripts/release-build.sh v1.2.3 123
```

This local release build also produces a DMG (`dist/MiddleClick.dmg`) for direct downloads.

## Homebrew (Custom Tap)

Use a cask in your own tap, for example `homebrew-tap/Casks/middleclick.rb`.

Each release:

1. Copy the generated `/Users/jon/Documents/github/middleclick/dist/middleclick-poltak.rb` into your tap repo at `Casks/middleclick-poltak.rb`.
2. Commit and push in the tap repo.
3. Users can install with:

```bash
brew tap <your-user>/tap
brew install --cask middleclick-poltak
```

### One-command tap update

Use:

```bash
./scripts/publish-cask.sh vX.Y.Z
```

This script downloads `middleclick-poltak.rb` from the specified GitHub release, updates `poltak/homebrew-tap`, commits, and pushes.

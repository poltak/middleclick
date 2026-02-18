# MiddleClick

Simple macOS menu-bar app that turns a **3-finger trackpad click or tap** into a **middle mouse click**.

## What it does

- Runs as a standard `.app` (`LSUIElement` menu-bar utility).
- Adds a menu-bar item with:
- Enable/Disable remapping
- Open Accessibility Settings
- Quit
- Watches global left mouse down/up events.
- Tracks current trackpad finger count via `MultitouchSupport` (private framework).
- If finger count is exactly 3 on left-click down, or a quick 3-finger touch ends (tap gesture):
- Suppresses that left click.
- Emits a middle-button down/up pair at the same pointer location.

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

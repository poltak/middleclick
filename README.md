# MiddleClick

Simple macOS utility that turns a **3-finger trackpad click or tap** into a **middle mouse click**.

## What it does

- Watches global left mouse down/up events.
- Tracks current trackpad finger count via `MultitouchSupport` (private framework).
- If finger count is exactly 3 on left-click down, or a quick 3-finger touch ends (tap gesture):
- Suppresses that left click.
- Emits a middle-button down/up pair at the same pointer location.

## Build

```bash
swift build
```

Binary path:

```bash
.build/debug/MiddleClick
```

## Run

```bash
.build/debug/MiddleClick
```

On first run, macOS should prompt for permissions.

Required permissions:

- `System Settings -> Privacy & Security -> Accessibility`
- Add/enable your terminal app (or whichever app launches `MiddleClick`).

If middle-clicking does not work in some apps, also enable:

- `System Settings -> Privacy & Security -> Input Monitoring`

## Notes

- Uses a private Apple framework (`MultitouchSupport`), so this is not App Store safe.
- This utility must stay running to keep remapping active.

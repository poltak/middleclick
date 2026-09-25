# Gesture recording

Use the installed copy of MiddleClick to record an intermittent false
middle-click. Quit any other copy first. Open MiddleClick from its install
location, then follow these steps:

1. Check that MiddleClick is enabled. If macOS asks, allow Accessibility for
   this app.
2. Open the menu and choose **Start Gesture Recording**.
3. Reproduce the problem. The recorder keeps up to 30 seconds, 4,096 events,
   and 32 contacts per frame. The event limit can shorten the time span.
4. Choose **Stop and Save Recording…** from the menu. Save the JSON file and
   attach it to your bug report.

Recording is off until you start it. The trace stays in memory until you save
it or quit the app. If you cancel the save panel or the save fails, choose
**Save Recording…** to try again.

For a local build, run these commands from the repository root:

```bash
./scripts/build-app.sh
open dist/MiddleClick.app
```

## Trace data

The trace records normalized trackpad contact positions and states, scroll
data, click source, recognition decisions and scores, and the app build and
macOS versions. It does not record URLs, page content, or key data.

## Edge-contact rule

When exactly three contacts are active, the rule finds the closest pair. It
rejects the synthetic tap only when the closest pair is unique, and the
remaining contact is more than `0.30` normalized units from its nearest pair
member and within `0.01` normalized units of a trackpad edge. A tied closest
pair does not trigger the rule. Once triggered, the rule rejects the full
synthetic tap sequence until all contacts lift, even if the outlying contact
moves away from the edge.

These thresholds are heuristic normalized units, not physical distances. The
input source does not provide trackpad dimensions, so the rule does not adjust
for trackpad aspect ratio. A valid tap with widely spread fingers near an edge
may also be rejected. Physical three-finger clicks are unchanged.

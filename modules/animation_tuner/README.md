# Animation Tuner

Tier A IIMP module for visually editing the writable motion tokens in
`Appearance.animation`. It does not patch stock files, requires no runtime
capabilities, and restores startup values when disabled or unloaded.

## Installation

From the repository root, run:

```bash
iimod validate modules/animation_tuner/
iimod check modules/animation_tuner/
iimod install modules/animation_tuner/
```

Open the shell settings app with `Super+I` or the shortcut configured by the
shell. Go to **Modules**, enable **Animation Tuner**, and open its settings.
Reinstalling from the same source updates the module without removing saved values.

## Quick start

1. Select a token such as **Element move**.
2. Enable **Override this token**.
3. Edit duration, velocity, or the Bezier handles.
4. Compare the stock and draft motion in the Move, Resize, and Fade previews.
5. Click **Apply**. Bound consumers update immediately without a shell restart.

Use **Revert** to discard unapplied edits. **Reset token** removes the selected
override; clicking **Reset all token overrides** twice restores every stock token
without deleting Spring Lab values or custom presets.

## Features

- Search and edit the eight writable animation tokens currently exposed by stock
  `Appearance.animation`.
- Configure duration, velocity, and one-to-four-segment cubic Bezier curves.
- Drag graph handles, enter numeric values, or use arrow keys; `Shift` uses a
  larger keyboard step.
- Compare stock and draft values with real QML `NumberAnimation` previews.
- Save custom curve presets and apply verified stock presets.
- Set controlled token durations to zero with explicit reduced motion while
  retaining the saved values.
- Explore spring parameters with a real QML `SpringAnimation` preview.

## Token coverage

| Token | Duration/Bezier | Velocity | Delay |
|---|---:|---:|---:|
| `elementMove` | yes | yes | preview only |
| `elementMoveSmall` | yes | yes | preview only |
| `elementMoveEnter` | yes | yes | preview only |
| `elementMoveExit` | yes | yes | preview only |
| `elementMoveFast` | yes | yes | preview only |
| `elementResize` | yes | yes | preview only |
| `clickBounce` | yes | yes | preview only |
| `scroll` | yes | no current consumer | preview only |

## Limits and Spring Lab

Velocity is applied to shell consumers that read the token, but the fixed-distance
preview does not visualize it. Preview delay is an authoring aid only: a Tier A
module cannot add delay to stock animations that were instantiated before it loaded.

The host exposes no animation property named `precompute`. Qt evaluates Bezier
curves directly; spring convergence is controlled by mass, spring strength,
damping, epsilon, maximum velocity, and modulus. Spring Lab applies those values
to its preview and restarts it while they are edited.

Spring Lab remains preview-only. The current stock tree declares springs inline
and also references readonly `Appearance.animationCurves`; an insert-only Tier A
module cannot replace those expressions safely. For the same reason, Animation
Tuner does not replace animation factories or claim a partial global delay override.

Quickshell 0.2.1 exposes no documented system reduced-motion preference. The
module setting is therefore explicit and does not claim to follow an unavailable
system preference.

## Configuration and validation

The settings fragment writes only:

```text
~/.config/illogical-impulse/modules/animation_tuner.json
```

Animation Tuner stores a versioned motion document as a JSON string inside the
outer settings object:

```json
{
  "documentJson": "{\"schemaVersion\":1,\"reducedMotion\":false,\"overrides\":{},\"springLab\":{...},\"customPresets\":[]}"
}
```

Use the settings UI instead of editing the escaped string manually. Unknown
future token records survive a load/save cycle but are not applied until the
module recognizes the token. Malformed, nonfinite, or unsupported-schema data
restores startup motion values and is not applied.

Bezier validation rules:

- Lists use Qt's `[c1x,c1y,c2x,c2y,endX,endY,...]` format.
- The final endpoint is fixed at `(1,1)`.
- Segment endpoint x values are strictly increasing.
- Control-point x values stay inside their segment; control points may cross.
- Y values are limited to `-2..3`, preserving stock overshoot while rejecting
  unbounded input.

## Development

```bash
node --test modules/animation_tuner/tests/*.test.mjs
for file in modules/animation_tuner/*.qml; do qmlformat "$file" >/dev/null; done
iimod validate modules/animation_tuner/
iimod suggest modules/animation_tuner/
iimod check modules/animation_tuner/
iimod pack modules/animation_tuner/ --no-origin
```

Source/package verification and live installation are intentionally separate.

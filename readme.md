# Cat Hop — a one-button pounce runner for the Instinct 3 Solar

A Connect IQ **game app** (Monkey C) for the **Garmin Instinct 3 Solar**. A cat runs along the
ground; tap a button to make it **jump** over obstacles scrolling in from the right. Clear an
obstacle to score; clip one and the run ends. Everything is white on black, since the panel is a
1-bit MIP display with only two colors.

## How to play

- **START / Up / Down** — jump (any of the three works, so it's easy one-handed). You can only jump
  from the ground (no mid-air double jump).
- **BACK** — quit to the watch.
- States: **READY** ("TAP TO START") → **PLAYING** → **GAME OVER** (shows your score and best).
  Your best score is saved between runs. Speed ramps up as you score, but obstacles always stay
  clearable with a single well-timed jump.

Built only for the **Instinct 3 Solar 45mm** (`instinct3solar45mm`, 176×176, semi-octagon).
That one product id also covers the 50mm hardware. Uses the Garmin SDK — Connect IQ **9.2.0**,
device API level **6.0**.

## How it works (the 30-second tour)

1. `manifest.xml` declares the app as a `watch-app`, targets `instinct3solar45mm`, needs no
   permissions, and names the entry class (`CatHopApp`).
2. `CatHopApp.getInitialView()` returns a `CatHopView` **and** a `CatHopDelegate`.
3. `CatHopDelegate` (a `BehaviorDelegate`) maps the buttons: `onSelect`/`onNextPage`/`onPreviousPage`
   → jump, `onBack` → exit. Each press calls `CatHopView.onTap()`.
4. `CatHopView` (a `WatchUi.View`) owns a 20 Hz `Timer.Timer`. Each tick it calls
   `CatHopGame.tick()` then `WatchUi.requestUpdate()`; `onUpdate(dc)` draws the ground, obstacles,
   the cat, the live score in the top-right round sub-window (via `WatchUi.getSubscreen()`), and the
   READY/GAME-OVER text. **All physics lives in the game tick, never in `onUpdate`.**
5. `CatHopGame` is pure logic: the state machine, fixed-point grounded-jump physics (position/velocity
   in 1/16-px units — no Float in the hot loop), obstacle motion + recycling, AABB collision, scoring,
   a difficulty ramp, and the high score (persisted via `Application.Storage`, no permission needed).

### Fairness (why the numbers are what they are)

The jump's apex and air-time are fixed (a tap is a fixed impulse — the watch gives no press-duration).
Clearing the tallest obstacle requires the jump's "high-enough" window to cover the cat+obstacle
overlap span, which means the **scroll speed has a fair minimum** (slow scroll is actually the
*hardest* case). Obstacle spacing is therefore stored in travel-**ticks** rather than pixels, so the
pixel gap scales with speed and stays clearable as the game ramps up. The constants in
`CatHopGame.mc` were derived from the exact integer loop, so what you tune is what the watch runs.

## Display constraints (why it looks the way it does)

The Instinct 3 Solar is a transflective MIP panel: **2-color (black + white) only**, no grays, no
anti-aliasing, no alpha blending, and no burn-in. So the game uses bold solid shapes: a white cat and
white obstacles on black, each with a 1-px black outline so they never visually merge, and text on
small black plates so it stays legible. A full clear-and-redraw every frame is flicker-free on MIP.

## Build & run

Requires [Task](https://taskfile.dev). The first build auto-generates a signing key.

```sh
task key      # one-time: create developer_key.der
task build    # compile -> bin/CatHop.prg
task sim      # launch the Connect IQ simulator (leave it open)
task run      # push the app to the simulator
```

In the simulator, pick **Instinct 3 Solar 45mm**, then use the on-screen buttons (or the mapped
keyboard keys) — START/GPS, Up, or Down to jump, BACK to quit.

## Reused assets

The custom 1-bit bitmap font `NordicLabel` is kept from the original watch face and reused as-is for
all on-screen text — the sub-window score and the "CAT HOP" / "TAP TO START" / "GAME OVER" labels.
The other two fonts (`NordicHero`, `NordicSmall`) remain in `resources/fonts/` but are currently
unused. Regenerate via `task font` only if you change them.

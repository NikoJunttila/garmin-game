# Flappy Watch — a Flappy Bird–style game for the Instinct 3 Solar

A Connect IQ **game app** (Monkey C) for the **Garmin Instinct 3 Solar**. Tap a button to flap a
bird upward; gravity pulls it down. Fly through the gaps in scrolling pipes — passing one scores a
point. Touch a pipe, the ceiling, or the ground and it's game over. Everything is white on black,
since the panel is a 1-bit MIP display with only two colors.

## How to play

- **START / Up / Down** — flap (any of the three works, so it's easy one-handed).
- **BACK** — quit to the watch.
- States: **READY** ("PRESS START") → **PLAYING** → **GAME OVER** (shows your score and best).
  Your best score is saved between runs.

Built only for the **Instinct 3 Solar 45mm** (`instinct3solar45mm`, 176×176, semi-octagon).
That one product id also covers the 50mm hardware. Uses the Garmin SDK — Connect IQ **9.2.0**,
device API level **6.0**.

## How it works (the 30-second tour)

1. `manifest.xml` declares the app as a `watch-app`, targets `instinct3solar45mm`, needs no
   permissions, and names the entry class (`FlappyApp`).
2. `FlappyApp.getInitialView()` returns a `FlappyView` **and** a `FlappyDelegate`.
3. `FlappyDelegate` (a `BehaviorDelegate`) maps the buttons: `onSelect`/`onNextPage`/`onPreviousPage`
   → flap, `onBack` → exit. Each press calls `FlappyView.onTap()`.
4. `FlappyView` (a `WatchUi.View`) owns a 20 Hz `Timer.Timer`. Each tick it calls
   `FlappyGame.tick()` then `WatchUi.requestUpdate()`; `onUpdate(dc)` draws the bird, pipes, ground,
   the live score in the top-right round sub-window (via `WatchUi.getSubscreen()`), and the
   READY/GAME-OVER text. **All physics lives in the game tick, never in `onUpdate`.**
5. `FlappyGame` is pure logic: the state machine, fixed-point physics (position/velocity in
   1/16-px units — no Float in the hot loop), pipe motion + recycling, collision, scoring, and the
   high score (persisted via `Application.Storage`, no permission needed).

Tunables (difficulty, feel, layout) are the module-level `const`s at the top of `FlappyGame.mc`
(gravity, flap impulse, gap height, scroll speed, …) and `FlappyView.mc` (tick rate, text rows).

## Display constraints (why it looks the way it does)

The Instinct 3 Solar is a transflective MIP panel: **2-color (black + white) only**, no grays, no
anti-aliasing, no alpha blending, and no burn-in. So the game leans on bold solid shapes: white
pipes and a white bird on black, each with a 1-px black outline so they never visually merge, and
text drawn on small black plates so it stays legible over pipes. A full-screen clear-and-redraw
every frame is flicker-free on MIP.

## Build & run

Requires [Task](https://taskfile.dev). The first build auto-generates a signing key.

```sh
task key      # one-time: create developer_key.der
task build    # compile -> bin/FlappyWatch.prg
task sim      # launch the Connect IQ simulator (leave it open)
task run      # push the app to the simulator
```

In the simulator, pick **Instinct 3 Solar 45mm**, then use the on-screen buttons (or the mapped
keyboard keys) — START/GPS, Up, or Down to flap, BACK to quit.

## Reused assets

The custom 1-bit bitmap font `NordicLabel` is kept from the original watch face and reused as-is for
all on-screen text — the sub-window score and the "PRESS START" / "GAME OVER" / "BEST" labels. The
other two fonts (`NordicHero`, `NordicSmall`) remain in `resources/fonts/` but are currently unused.
Regenerate via `task font` only if you change them.

## Layout

```
manifest.xml              app declaration (id, type=watch-app, product, no permissions, min API)
monkey.jungle             build config (points at manifest.xml)
taskfile.yml              build/run tasks (key, build, sim, run, font)
source/
  FlappyApp.mc            Application.AppBase — returns [view, delegate]
  FlappyView.mc           WatchUi.View — owns the 20 Hz Timer, draws every frame in onUpdate()
  FlappyDelegate.mc       WatchUi.BehaviorDelegate — buttons -> flap / exit
  FlappyGame.mc           plain class — state machine + physics + pipes + collision + scoring + high score
resources/
  strings/strings.xml     app name ("Flappy Watch")
  drawables/              launcher icon (a monochrome bird SVG) + drawables.xml
  fonts/                  3 custom 1-bit bitmap fonts (NordicHero/Label/Small), regen via `task font`
tools/
  genfont.py              renders the bitmap fonts from TTFs (needs Pillow)
developer_key.der         personal signing key (generated, gitignored)
bin/                      build output (gitignored)
```

## How it works (the 30-second tour)

1. `manifest.xml` declares the app as a `watch-app`, targets `instinct3solar45mm`, requests no
   permissions (a game needs none; the high score uses `Application.Storage`), and names the entry
   class (`FlappyApp`).
2. `FlappyApp.getInitialView()` returns a `FlappyView` and a `FlappyDelegate`.
3. `FlappyDelegate` is a `WatchUi.BehaviorDelegate`. Per the user's choice, START/GPS (`onSelect`),
   Up (`onPreviousPage`), and Down (`onNextPage`) all flap; BACK (`onBack`) exits. Each calls
   `FlappyView.onTap()`, which forwards to `FlappyGame.onAction()` and requests a redraw so the flap
   feels instant.
4. `FlappyView` is a `WatchUi.View`. It owns a 20 Hz (50 ms) `Timer.Timer` started in `onShow` and
   stopped in `onHide`. Each tick: `FlappyGame.tick()` then `WatchUi.requestUpdate()`. Rendering
   happens only in `onUpdate(dc)`, which clears to black and draws white pipes, the bird, the ground,
   the live score in the top-right sub-window (see below), and the READY/GAME-OVER text from the
   game state. **Physics is never run in `onUpdate`** — keeping `tick()` the sole mutator means an
   extra system repaint can't double-step the simulation.
5. `FlappyGame` is pure logic (no Graphics/WatchUi). It holds the `STATE_READY/PLAYING/GAMEOVER`
   state machine; integer **fixed-point** physics (bird position/velocity in 1/16-px units — no
   Float in the per-tick loop); a fixed, recycled ring of `PIPE_COUNT` pipes (`[x, gapCy, scored]`,
   no per-frame allocation); axis-aligned box collision vs pipes/ceiling/ground; once-per-pipe
   scoring; and the high score loaded/saved via `Application.Storage` (key `"best"`). A short
   restart-lock after a crash stops the in-flight death press from instantly relaunching.

## Tuning

All gameplay/geometry knobs are the module-level `const`s at the top of `source/FlappyGame.mc`
(`GRAVITY`, `FLAP_VY`, `MAX_VY`, `GAP_H`, `PIPE_W`, `PIPE_SPACING`, `SCROLL_PX`, the gap-center
band, the bird position/size, the ground line). Tick rate and text-row positions live at the top of
`source/FlappyView.mc`. These consts are file-scope but globally visible, so `FlappyView` reads the
same geometry constants `FlappyGame` uses for collision — one source of truth.

## The top-right sub-window ("orange circle")

The Instinct 3 Solar has a distinctive small **round sub-window in the top-right corner** (the
orange-ringed circle on the device). It's part of the same 1-bit MIP panel, not a separate display —
just a region the platform designates for a complication. Get its on-screen rectangle at runtime with
`WatchUi.getSubscreen()`, which returns a `Graphics.BoundingBox` (`.x`, `.y`, `.width`, `.height` in
screen px) or `null` if unavailable. Its center sits at roughly **(144, 31)** on the 176×176 screen.

This game draws the **live score inside that circle** (`FlappyView.drawScore`): a black backing disc
sized to the region, then the white score number centered in it. `onLayout` caches the region (with a
(144, 31)/r=18 fallback if `getSubscreen()` returns null). The original "Nordic" watch face used this
same sub-window for heart rate, so it's a reliable, device-blessed spot for a small readout.

## Display constraints

The Instinct 3 Solar is a 1-bit MIP panel: black + white only, no grays/anti-aliasing/alpha, no
burn-in. Draw solid white shapes on black; give the bird and pipes a 1-px black outline so they
don't merge when overlapping, and put on-screen text on small black plates so it stays readable over
pipes. A full clear + redraw each frame is flicker-free on MIP.

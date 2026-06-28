## Layout

```
manifest.xml              app declaration (id, type=watch-app, product, no permissions, min API)
monkey.jungle             build config (points at manifest.xml)
taskfile.yml              build/run tasks (key, build, sim, run, font)
source/
  CatHopApp.mc            Application.AppBase — returns [view, delegate]
  CatHopView.mc           WatchUi.View — owns the 20 Hz Timer, draws every frame in onUpdate()
  CatHopDelegate.mc       WatchUi.BehaviorDelegate — buttons -> jump / exit
  CatHopGame.mc           plain class — state machine + grounded-jump physics + obstacles + collision + scoring + high score
resources/
  strings/strings.xml     app name ("Cat Hop")
  drawables/              launcher icon (a monochrome cat-face SVG) + drawables.xml
  fonts/                  3 custom 1-bit bitmap fonts (NordicHero/Label/Small); only NordicLabel is used now. regen via `task font`
tools/
  genfont.py              renders the bitmap fonts from TTFs (needs Pillow)
developer_key.der         personal signing key (generated, gitignored)
bin/                      build output (gitignored)
```

## What the game is

**Cat Hop** is a one-button Chrome-dino-style **pounce runner**: a cat runs at a fixed x on the
ground; a tap makes it jump; obstacles scroll in from the right; clear them to score, clip one and
the run ends. (It evolved from an earlier Flappy-Bird clone — the architecture and the sub-window
score were kept; the physics and obstacles were reworked.)

## How it works (the 30-second tour)

1. `manifest.xml` declares the app as a `watch-app`, targets `instinct3solar45mm`, requests no
   permissions (a game needs none; the high score uses `Application.Storage`), and names the entry
   class (`CatHopApp`).
2. `CatHopApp.getInitialView()` returns a `CatHopView` and a `CatHopDelegate`.
3. `CatHopDelegate` is a `WatchUi.BehaviorDelegate`. Per the user's choice, START/GPS (`onSelect`),
   Up (`onPreviousPage`), and Down (`onNextPage`) all jump; BACK (`onBack`) exits. Each calls
   `CatHopView.onTap()`, which forwards to `CatHopGame.onAction()` and requests a redraw.
4. `CatHopView` is a `WatchUi.View`. It owns a 20 Hz (50 ms) `Timer.Timer` started in `onShow` and
   stopped in `onHide`. Each tick: `CatHopGame.tick()` then `WatchUi.requestUpdate()`. Rendering
   happens only in `onUpdate(dc)`, which clears to black and draws the ground (with scrolling dashes),
   obstacles, the cat sprite, the sub-window score (see below), and READY/GAME-OVER text. **Physics
   is never run in `onUpdate`** — keeping `tick()` the sole mutator means an extra system repaint
   can't double-step the simulation.
5. `CatHopGame` is pure logic (no Graphics/WatchUi). It holds the `STATE_READY/PLAYING/GAMEOVER`
   state machine; integer **fixed-point** grounded-jump physics (cat feet position/velocity in
   1/16-px units — no Float in the per-tick loop; jump only while grounded, no double-jump); a fixed,
   recycled ring of `OBST_COUNT` obstacles (`[x, height, scored]`, no per-frame allocation); AABB
   collision (cat box vs obstacle boxes, no ceiling); once-per-obstacle scoring; a difficulty ramp;
   and the high score loaded/saved via `Application.Storage` (key `"best"`). A short restart-lock
   after a crash stops the in-flight death tap from instantly relaunching.

## Tuning & fairness

All gameplay/geometry knobs are the module-level `const`s at the top of `source/CatHopGame.mc`
(`GRAVITY`, `JUMP_VY`, `GROUND_Y`, cat box, `OBST_*`, `GAP_*_TICKS`, `SCROLL_START/CAP`, `RAMP_N`).
Tick rate and text-row positions live at the top of `source/CatHopView.mc`. These consts are
file-scope but globally visible, so the View reads the same geometry the Game uses for collision —
one source of truth.

**Fairness is load-bearing.** A tap is a fixed impulse (the watch exposes no press-duration), so the
jump apex/air-time are fixed. Clearing the tallest obstacle needs the jump's ~7-tick "high-enough"
window to cover the `CAT_W + OBST_W` overlap span, which forces a **minimum scroll speed** (slow
scroll is the *hardest* case — counterintuitive). So obstacle spacing is stored in travel-**ticks**,
not pixels: the pixel pitch = `ticks * scroll` auto-scales with the difficulty ramp and stays
clearable at every speed. The numbers were derived from the exact integer loop the watch runs, not a
continuous-time approximation — re-derive if you change `GRAVITY`/`JUMP_VY`/`SCROLL_*`/the cat box.

## The top-right sub-window ("orange circle")

The Instinct 3 Solar has a distinctive small **round sub-window in the top-right corner** (the
orange-ringed circle on the device). It's part of the same 1-bit MIP panel, not a separate display —
just a region the platform designates for a complication. Get its on-screen rectangle at runtime with
`WatchUi.getSubscreen()`, which returns a `Graphics.BoundingBox` (`.x`, `.y`, `.width`, `.height` in
screen px) or `null` if unavailable. Its center sits at roughly **(144, 31)** on the 176×176 screen.

This game draws the **live score inside that circle** (`CatHopView.drawScore`): a black backing disc
sized to the region, then the white score number centered in it. `onLayout` caches the region (with a
(144, 31)/r=18 fallback if `getSubscreen()` returns null). The original "Nordic" watch face used this
same sub-window for heart rate, so it's a reliable, device-blessed spot for a small readout.

## Display constraints

The Instinct 3 Solar is a 1-bit MIP panel: black + white only, no grays/anti-aliasing/alpha
(`alphaBlendingSupport=false`, `antiAliasedFontSupport=false`), no burn-in. Draw solid white shapes
on black; give the cat and obstacles a 1-px black outline so they don't merge when overlapping, and
put on-screen text on small black plates so it stays readable. `fillPolygon` IS supported on this
device (used for the cat's ears and tail). A full clear + redraw each frame is flicker-free on MIP.

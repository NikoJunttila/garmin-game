import Toybox.Lang;
import Toybox.Math;
import Toybox.Application.Storage;

// ---- Playfield geometry (px on the 176x176 panel). Single source of truth —
//      tune here, not inside the draw methods. These module-level consts are
//      shared with CatHopView (Monkey C file-scope consts are globally visible). ----
const SCREEN_W = 176;
const SCREEN_H = 176;

// Ground surface. Raised well above the semi-octagon's bottom corner chamfer
// (~y >= 154) so the cat and obstacles are always fully visible. The cat's feet
// and every obstacle's base sit on this line; the ground strip fills below it.
const GROUND_Y = 140;

// The cat runs at a fixed x (the world scrolls past it). Axis-aligned collision box.
const CAT_X = 40;        // left edge of the cat box
const CAT_W = 20;
const CAT_H = 18;        // grounded box = rows (GROUND_Y - CAT_H) .. GROUND_Y

// ---- Physics. Vertical position/velocity in 1/16-px fixed-point (SUBPX) so the
//      jump arc is smooth without any Float in the per-tick hot loop. Values are
//      per tick; the loop runs at 20 Hz (50ms). Derived from the exact integer
//      loop: apex ~30.6px, air-time 20 ticks (1.0s), feet >=26px high for 7 ticks. ----
const SUBPX = 16;
const GRAVITY = 10;       // velocity gained each tick (subpx/tick), added while airborne
const JUMP_VY = -104;     // a grounded tap SETS vy to this (snappy, can't stack)

// ---- Obstacles. A fixed ring of recycled blocks sitting on the ground. Each is
//      [x, height, scored]; the indices below name the slots. ----
const OBST_COUNT = 4;     // slots tracked; at most ~3 are ever on screen at once
const OBST_W = 14;        // obstacle width
const OBST_MIN_H = 12;    // shortest obstacle
const OBST_MAX_H = 26;    // tallest obstacle (a single well-timed jump just clears it)
const FIRST_SPAWN_X = 196;// first obstacle spawns here (off-right) -> ~1.36s of runway
const OX = 0;
const OH = 1;
const OSCORED = 2;

// Spacing is stored in TRAVEL-TICKS (not px) so the pixel pitch = ticks * scroll
// auto-scales with speed and stays fair as the game ramps up. GAP_MIN_TICKS (17) >
// the 14-tick land-and-re-jump trough, so consecutive obstacles are always clearable.
const GAP_MIN_TICKS = 17;
const GAP_MAX_TICKS = 26;

// ---- Difficulty ramp. Scroll speed grows with score. SCROLL_START=5 is the FAIR
//      MINIMUM: clearing the tallest obstacle needs the 7-tick high window to cover
//      the (CAT_W + OBST_W = 34px) danger span, i.e. 7*S >= 34 => S >= 5. Capped at 8
//      so the danger span never outruns the high window. ----
const SCROLL_START = 5;
const SCROLL_CAP = 8;
const RAMP_N = 8;         // +1 px/tick every 8 points

// Spacing of the moving ground dashes (purely cosmetic).
const GROUND_DASH = 12;

// ---- Game states ----
const STATE_READY = 0;
const STATE_PLAYING = 1;
const STATE_GAMEOVER = 2;

// After a crash, ignore the action button for this many ticks (~0.9s) so the
// in-flight "death tap" doesn't instantly relaunch a new run.
const RESTART_LOCK_TICKS = 18;

// Storage key for the persisted high score.
const KEY_BEST = "best";

// The whole game: state machine + grounded-jump physics + obstacle motion + collision
// + scoring + difficulty ramp. Pure logic — no Graphics/WatchUi here. CatHopView reads
// from it and draws; CatHopDelegate routes button presses into onAction().
class CatHopGame {

    private var mState as Number = STATE_READY;
    private var mFeetY as Number = GROUND_Y * SUBPX;  // subpx; the cat box BOTTOM
    private var mVy as Number = 0;                    // subpx/tick (negative = up)
    private var mGrounded as Boolean = true;
    private var mScroll as Number = SCROLL_START;     // px/tick the world moves left
    private var mScore as Number = 0;
    private var mBest as Number = 0;
    private var mGameOverTicks as Number = 0;
    private var mTickCount as Number = 0;             // drives the leg animation
    private var mGroundPhase as Number = 0;           // 0..GROUND_DASH-1, scrolls the dashes
    private var mObst as Array<Array<Number>>;        // OBST_COUNT arrays of [x, h, scored]

    function initialize() {
        mBest = loadBest();
        // Pre-allocate the obstacle ring once, then reset() positions them.
        mObst = new [OBST_COUNT] as Array<Array<Number>>;
        for (var i = 0; i < OBST_COUNT; i += 1) {
            mObst[i] = [0, 0, 0] as Array<Number>;
        }
        reset();
    }

    // ---- read-only accessors for the view ----
    function getState() as Number { return mState; }
    function getScore() as Number { return mScore; }
    function getBest() as Number { return mBest; }
    function getObstacles() as Array<Array<Number>> { return mObst; }
    function getFeetPx() as Number { return mFeetY / SUBPX; }
    function isGrounded() as Boolean { return mGrounded; }
    function getAnimPhase() as Number { return (mTickCount / 3) % 2; }  // ~6 Hz leg swap
    function getGroundOffset() as Number { return mGroundPhase; }
    function canRestart() as Boolean { return mGameOverTicks >= RESTART_LOCK_TICKS; }

    // Single input entry point. What a button press means depends on the state.
    function onAction() as Void {
        if (mState == STATE_READY) {
            start();
        } else if (mState == STATE_PLAYING) {
            if (mGrounded) {            // jump only from the ground (no double-jump / stacking)
                mVy = JUMP_VY;
                mGrounded = false;
            }
        } else { // GAMEOVER
            if (canRestart()) {
                reset();
            }
        }
    }

    // Advance the world one tick. Physics only runs while PLAYING; READY still ticks
    // so the cat's legs trot in place; GAMEOVER counts down the restart lock.
    function tick() as Void {
        if (mState == STATE_PLAYING) {
            stepPhysics();
        } else if (mState == STATE_READY) {
            mTickCount += 1;
        } else { // GAMEOVER
            mGameOverTicks += 1;
        }
    }

    // Back to the start screen: cat grounded, obstacles parked off the right edge.
    function reset() as Void {
        mState = STATE_READY;
        mFeetY = GROUND_Y * SUBPX;
        mVy = 0;
        mGrounded = true;
        mScroll = SCROLL_START;
        mGameOverTicks = 0;
        mTickCount = 0;
        mGroundPhase = 0;
        layoutObstacles();
    }

    // READY -> PLAYING. The cat begins grounded and running (no auto-jump).
    function start() as Void {
        mState = STATE_PLAYING;
        mFeetY = GROUND_Y * SUBPX;
        mVy = 0;
        mGrounded = true;
        mScore = 0;
        mScroll = SCROLL_START;
        mGroundPhase = 0;
        layoutObstacles();
    }

    // ---- internals ----------------------------------------------------------

    private function stepPhysics() as Void {
        // Difficulty ramp: faster with score, capped at the still-fair maximum.
        mScroll = SCROLL_START + mScore / RAMP_N;
        if (mScroll > SCROLL_CAP) { mScroll = SCROLL_CAP; }

        // Gravity + integrate; clamp to the ground on landing.
        mVy += GRAVITY;
        mFeetY += mVy;
        var rest = GROUND_Y * SUBPX;
        if (mFeetY >= rest) {
            mFeetY = rest;
            mVy = 0;
            mGrounded = true;
        }

        // Scroll obstacles left; recycle any that have fully exited on the left.
        for (var i = 0; i < OBST_COUNT; i += 1) {
            var p = mObst[i];
            p[OX] -= mScroll;
            if (p[OX] + OBST_W < 0) {
                recycle(p);
            }
        }

        // Collision ends the run immediately (no score awarded this tick).
        var feetPx = mFeetY / SUBPX;
        if (collides(feetPx)) {
            enterGameOver();
            return;
        }

        // Score once per obstacle, the instant its trailing edge clears the cat.
        for (var i = 0; i < OBST_COUNT; i += 1) {
            var p = mObst[i];
            if (p[OSCORED] == 0 && (p[OX] + OBST_W) < CAT_X) {
                p[OSCORED] = 1;
                mScore += 1;
            }
        }

        mGroundPhase = (mGroundPhase + mScroll) % GROUND_DASH;
        mTickCount += 1;
    }

    // True if the cat box overlaps any obstacle box. The cat bottom is never below the
    // ground, so a single "bottom dips into the obstacle" check is sufficient (and a
    // resting cat correctly dies on an un-cleared obstacle in its x-band).
    private function collides(feetPx as Number) as Boolean {
        var catBot = feetPx;
        var catLeft = CAT_X;
        var catRight = CAT_X + CAT_W;
        for (var i = 0; i < OBST_COUNT; i += 1) {
            var p = mObst[i];
            var ox = p[OX];
            if (catRight >= ox && catLeft <= ox + OBST_W) {   // horizontally overlapping
                var obTop = GROUND_Y - p[OH];
                if (catBot > obTop) {                          // feet level = just cleared (not a hit)
                    return true;
                }
            }
        }
        return false;
    }

    private function enterGameOver() as Void {
        mState = STATE_GAMEOVER;
        mGameOverTicks = 0;
        if (mScore > mBest) {
            mBest = mScore;
            saveBest(mBest);
        }
    }

    // Park the obstacles to the right, spaced by randomized travel-ticks.
    private function layoutObstacles() as Void {
        var x = FIRST_SPAWN_X;
        for (var i = 0; i < OBST_COUNT; i += 1) {
            var p = mObst[i];
            p[OX] = x;
            p[OH] = randHeight();
            p[OSCORED] = 0;
            x += randPitchPx();
        }
    }

    private function recycle(p as Array<Number>) as Void {
        p[OX] = rightmostX() + randPitchPx();
        p[OH] = randHeight();
        p[OSCORED] = 0;
    }

    private function rightmostX() as Number {
        var mx = mObst[0][OX];
        for (var i = 1; i < OBST_COUNT; i += 1) {
            if (mObst[i][OX] > mx) { mx = mObst[i][OX]; }
        }
        return mx;
    }

    // Pixel pitch between obstacles = randomized travel-ticks * current scroll speed,
    // so the gap stays fair (always land-and-re-jumpable) at every speed.
    private function randPitchPx() as Number {
        var spanT = GAP_MAX_TICKS - GAP_MIN_TICKS;
        var rt = Math.rand() % (spanT + 1);
        if (rt < 0) { rt = -rt; }
        return (GAP_MIN_TICKS + rt) * mScroll;
    }

    private function randHeight() as Number {
        var span = OBST_MAX_H - OBST_MIN_H;
        var r = Math.rand() % (span + 1);
        if (r < 0) { r = -r; }
        return OBST_MIN_H + r;
    }

    private function loadBest() as Number {
        var v = Storage.getValue(KEY_BEST);
        if (v == null) { return 0; }
        return v as Number;
    }

    private function saveBest(b as Number) as Void {
        Storage.setValue(KEY_BEST, b);
    }
}

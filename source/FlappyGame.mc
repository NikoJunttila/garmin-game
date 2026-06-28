import Toybox.Lang;
import Toybox.Math;
import Toybox.Application.Storage;

// ---- Playfield geometry (px on the 176x176 panel). Single source of truth —
//      tune here, not inside the draw methods. These module-level consts are
//      shared with FlappyView (Monkey C file-scope consts are globally visible). ----
const SCREEN_W = 176;
const SCREEN_H = 176;
const CEILING_Y = 0;     // hard top: collision if the bird's top crosses this
const GROUND_Y = 168;    // top of the ground strip; collision if the bird's bottom reaches it

// The bird sits at a fixed x (classic Flappy); the world scrolls past it.
const BIRD_X = 52;       // bird center x
const BIRD_R = 7;        // collision half-size (≈14px tall bird)

// ---- Physics. Position/velocity are kept in 1/16-px fixed-point units (SUBPX)
//      so motion is smooth without any Float math in the per-tick hot loop. All
//      values below are per tick (the loop runs at ~20 Hz / 50ms). Tune feel here. ----
const SUBPX = 16;
const GRAVITY = 5;        // velocity gained each tick (units/tick)
const FLAP_VY = -52;      // flap sets (not adds) vy to this — snappy, can't stack
const MAX_VY = 64;        // terminal fall speed (units/tick)
const START_Y = 88 * 16;  // bird starts at vertical center, in subpx

// ---- Obstacles. A fixed ring of recycled pipes (no per-frame allocation). Each
//      pipe is [x, gapCenterY, scored]; indices below name the slots. ----
const PIPE_COUNT = 3;     // max pipes tracked; at most 2 are ever visible at once
const PIPE_W = 22;        // pipe column width
const GAP_H = 62;         // vertical opening the bird flies through
const PIPE_SPACING = 96;  // horizontal distance between successive pipes
const SCROLL_PX = 2;      // pipes move left this many px/tick (40 px/s at 20 Hz)
const GAP_MIN_CY = 44;    // highest gap center (keeps the top stub visible)
const GAP_MAX_CY = 132;   // lowest gap center (keeps the bottom stub above the ground)
const PX = 0;
const PGCY = 1;
const PSCORED = 2;

// ---- Game states ----
const STATE_READY = 0;
const STATE_PLAYING = 1;
const STATE_GAMEOVER = 2;

// After a crash, ignore the action button for this many ticks (~0.7s) so the
// in-flight "death press" doesn't instantly relaunch a new game.
const RESTART_LOCK_TICKS = 18;

// Storage key for the persisted high score.
const KEY_BEST = "best";

// The whole game: state machine + physics + pipe motion + collision + scoring.
// Pure logic — no Graphics/WatchUi here. FlappyView reads from it and draws;
// FlappyDelegate routes button presses into onAction().
class FlappyGame {

    private var mState as Number = STATE_READY;
    private var mBirdY as Number = START_Y;   // subpx
    private var mVy as Number = 0;            // subpx/tick
    private var mPipes as Array<Array<Number>>;  // PIPE_COUNT arrays of [x, gapCy, scored]
    private var mScore as Number = 0;
    private var mBest as Number = 0;
    private var mGameOverTicks as Number = 0;
    private var mBobTick as Number = 0;       // drives the gentle READY-screen bob

    function initialize() {
        mBest = loadBest();
        // Pre-allocate the pipe ring once, then reset() positions them.
        mPipes = new [PIPE_COUNT] as Array<Array<Number>>;
        for (var i = 0; i < PIPE_COUNT; i += 1) {
            mPipes[i] = [0, 0, 0] as Array<Number>;
        }
        reset();
    }

    // ---- read-only accessors for the view ----
    function getState() as Number { return mState; }
    function getBirdYPx() as Number { return mBirdY / SUBPX; }
    function getPipes() as Array<Array<Number>> { return mPipes; }
    function getScore() as Number { return mScore; }
    function getBest() as Number { return mBest; }
    function canRestart() as Boolean { return mGameOverTicks >= RESTART_LOCK_TICKS; }

    // Single input entry point. What a button press means depends on the state.
    function onAction() as Void {
        if (mState == STATE_READY) {
            start();
        } else if (mState == STATE_PLAYING) {
            mVy = FLAP_VY;
        } else { // GAMEOVER
            if (canRestart()) {
                reset();
            }
        }
    }

    // Advance the world one tick. Physics only runs while PLAYING.
    function tick() as Void {
        if (mState == STATE_PLAYING) {
            stepPhysics();
        } else if (mState == STATE_READY) {
            stepBob();
        } else { // GAMEOVER
            mGameOverTicks += 1;
        }
    }

    // Back to the start screen: bird centered, pipes parked off the right edge.
    function reset() as Void {
        mState = STATE_READY;
        mBirdY = START_Y;
        mVy = 0;
        mGameOverTicks = 0;
        mBobTick = 0;
        layoutPipes();
    }

    // READY -> PLAYING. The launch press also counts as the first flap.
    function start() as Void {
        mState = STATE_PLAYING;
        mBirdY = START_Y;
        mVy = FLAP_VY;
        mScore = 0;
        layoutPipes();
    }

    // ---- internals ----------------------------------------------------------

    private function stepPhysics() as Void {
        // Gravity, capped to a terminal velocity, then integrate.
        mVy += GRAVITY;
        if (mVy > MAX_VY) { mVy = MAX_VY; }
        mBirdY += mVy;

        // Scroll pipes left; recycle any that have fully exited on the left.
        for (var i = 0; i < PIPE_COUNT; i += 1) {
            var p = mPipes[i];
            p[PX] -= SCROLL_PX;
            if (p[PX] + PIPE_W < 0) {
                p[PX] = rightmostX() + PIPE_SPACING;
                p[PGCY] = randGapCy();
                p[PSCORED] = 0;
            }
        }

        // Collision ends the game immediately (no score awarded this tick).
        var birdPy = mBirdY / SUBPX;
        if (collides(birdPy)) {
            enterGameOver();
            return;
        }

        // Score once per pipe, the instant its trailing edge clears the bird.
        for (var i = 0; i < PIPE_COUNT; i += 1) {
            var p = mPipes[i];
            if (p[PSCORED] == 0 && (p[PX] + PIPE_W) < BIRD_X) {
                p[PSCORED] = 1;
                mScore += 1;
            }
        }
    }

    // Gentle ±~2px hover on the READY screen so the bird looks alive.
    private function stepBob() as Void {
        mBobTick += 1;
        var phase = mBobTick % 40;           // 0..39
        var tri = (phase < 20) ? phase : (40 - phase); // 0..20..0 triangle wave
        mBirdY = START_Y + (tri - 10) * 4;   // ±40 subpx ≈ ±2.5px
    }

    // True if the bird's box hits the ceiling, the ground, or any pipe column.
    private function collides(birdPy as Number) as Boolean {
        var top = birdPy - BIRD_R;
        var bot = birdPy + BIRD_R;
        if (top <= CEILING_Y) { return true; }
        if (bot >= GROUND_Y) { return true; }

        var bl = BIRD_X - BIRD_R;
        var br = BIRD_X + BIRD_R;
        var half = GAP_H / 2;
        for (var i = 0; i < PIPE_COUNT; i += 1) {
            var p = mPipes[i];
            var px = p[PX];
            if (br >= px && bl <= px + PIPE_W) {           // horizontally overlapping this pipe
                var gapTop = p[PGCY] - half;
                var gapBot = p[PGCY] + half;
                if (top < gapTop || bot > gapBot) {        // not fully inside the gap
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

    // Park the pipes evenly, starting just off the right edge.
    private function layoutPipes() as Void {
        for (var i = 0; i < PIPE_COUNT; i += 1) {
            var p = mPipes[i];
            p[PX] = SCREEN_W + 20 + i * PIPE_SPACING;
            p[PGCY] = randGapCy();
            p[PSCORED] = 0;
        }
    }

    private function rightmostX() as Number {
        var mx = mPipes[0][PX];
        for (var i = 1; i < PIPE_COUNT; i += 1) {
            if (mPipes[i][PX] > mx) { mx = mPipes[i][PX]; }
        }
        return mx;
    }

    // A random gap center within the safe band. Math.rand() is a large Number; the
    // abs guard keeps the modulo result non-negative on every runtime.
    private function randGapCy() as Number {
        var span = GAP_MAX_CY - GAP_MIN_CY;
        var r = Math.rand() % (span + 1);
        if (r < 0) { r = -r; }
        return GAP_MIN_CY + r;
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

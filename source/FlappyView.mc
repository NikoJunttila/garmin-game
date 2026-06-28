import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// ---- View-only layout (text rows etc.). Gameplay/geometry consts live in
//      FlappyGame.mc and are shared globally. ----
const TICK_MS = 50;        // game loop period — 20 Hz (50ms is Garmin's min timer interval)

// The Instinct 3 Solar has a small round sub-window (the "orange circle") in the top-right
// corner. We draw the live score inside it via WatchUi.getSubscreen(); these are the fallback
// center/radius (screen px) used only if the runtime can't report the region.
const SUB_FALLBACK_CX = 144;
const SUB_FALLBACK_CY = 31;
const SUB_FALLBACK_R = 18;

const READY_TITLE_Y = 40;
const READY_HINT_Y = 112;
const READY_BEST_Y = 142;

const OVER_TITLE_Y = 42;
const OVER_SCORE_Y = 74;
const OVER_BEST_Y = 104;
const OVER_HINT_Y = 136;

// Half-height of the black text "plate" drawn behind centered labels.
const PLATE_HALF_LABEL = 15;

// The game view: owns the frame timer and draws every frame from the game state.
// Physics lives only in FlappyGame.tick() (called from onTick), never in onUpdate,
// so an extra system repaint can never double-step the simulation.
class FlappyView extends WatchUi.View {

    private var mGame as FlappyGame;
    private var mTimer as Timer.Timer?;

    private var mCx as Number = SCREEN_W / 2;

    // Cached top-right sub-window region (screen px), from WatchUi.getSubscreen().
    private var mHasSub as Boolean = false;
    private var mSubX as Number = 0;
    private var mSubY as Number = 0;
    private var mSubW as Number = 0;
    private var mSubH as Number = 0;

    // Custom 1-bit bitmap font (reused from the old face). If the load fails it stays
    // null and labelFont() falls back to a system font, so we always draw.
    private var mLabelFont as WatchUi.FontResource?;

    function initialize(game as FlappyGame) {
        View.initialize();
        mGame = game;
    }

    // Cache screen center and load the fonts once. No setLayout — the whole screen
    // is drawn in code.
    function onLayout(dc as Dc) as Void {
        mCx = dc.getWidth() / 2;
        mLabelFont = WatchUi.loadResource(Rez.Fonts.NordicLabel) as WatchUi.FontResource;

        // Locate the round sub-window so the score can live in it.
        var sub = WatchUi.getSubscreen();
        if (sub != null) {
            mHasSub = true;
            mSubX = sub.x;
            mSubY = sub.y;
            mSubW = sub.width;
            mSubH = sub.height;
        }
    }

    // Start the game loop when visible; always stop it when hidden so physics never
    // runs (and the battery never drains) in the background.
    function onShow() as Void {
        if (mTimer == null) {
            mTimer = new Timer.Timer();
        }
        mTimer.start(method(:onTick), TICK_MS, true);
    }

    function onHide() as Void {
        if (mTimer != null) {
            mTimer.stop();
            mTimer = null;
        }
    }

    // One game tick: advance the world, then ask for a redraw.
    function onTick() as Void {
        mGame.tick();
        WatchUi.requestUpdate();
    }

    // A button press (from the delegate). Apply it now and redraw immediately so
    // the flap feels instant, even between ticks.
    function onTap() as Void {
        mGame.onAction();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        // Opaque black field, then draw everything in white (1-bit MIP: no AA, no alpha).
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        drawPipes(dc);
        drawBird(dc);
        drawGround(dc);

        var state = mGame.getState();
        if (state == STATE_PLAYING) {
            drawScore(dc);
        } else if (state == STATE_READY) {
            drawReady(dc);
        } else {
            drawGameOver(dc);
        }
    }

    // ---- drawing helpers ----------------------------------------------------

    private function drawPipes(dc as Dc) as Void {
        var pipes = mGame.getPipes();
        var half = GAP_H / 2;
        for (var i = 0; i < PIPE_COUNT; i += 1) {
            var p = pipes[i];
            var px = p[PX];
            if (px > SCREEN_W || px + PIPE_W < 0) { continue; }   // off-screen (e.g. parked in READY)
            var gapTop = p[PGCY] - half;
            var gapBot = p[PGCY] + half;

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            if (gapTop > 0) { dc.fillRectangle(px, 0, PIPE_W, gapTop); }
            if (gapBot < GROUND_Y) { dc.fillRectangle(px, gapBot, PIPE_W, GROUND_Y - gapBot); }

            // 1px black outline so a white pipe edge never merges with the bird.
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            if (gapTop > 0) { dc.drawRectangle(px, 0, PIPE_W, gapTop); }
            if (gapBot < GROUND_Y) { dc.drawRectangle(px, gapBot, PIPE_W, GROUND_Y - gapBot); }
        }
    }

    // White body + black rim (so it reads against white pipes) + black eye + white beak.
    private function drawBird(dc as Dc) as Void {
        var by = mGame.getBirdYPx();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(BIRD_X, by, BIRD_R);
        dc.fillRectangle(BIRD_X + BIRD_R - 1, by - 1, 4, 3);   // beak nub

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(BIRD_X, by, BIRD_R);                     // rim
        dc.fillCircle(BIRD_X + 3, by - 2, 1);                  // eye
    }

    private function drawGround(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, GROUND_Y, SCREEN_W, SCREEN_H - GROUND_Y);
    }

    // Live score in the top-right round sub-window (the "orange circle"). A black
    // backing disc keeps the number readable when a pipe is scrolling through that corner.
    private function drawScore(dc as Dc) as Void {
        var cx; var cy; var r;
        if (mHasSub) {
            cx = mSubX + mSubW / 2;
            cy = mSubY + mSubH / 2;
            r = ((mSubW < mSubH) ? mSubW : mSubH) / 2;
        } else {
            cx = SUB_FALLBACK_CX;
            cy = SUB_FALLBACK_CY;
            r = SUB_FALLBACK_R;
        }
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, labelFont(), mGame.getScore().format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawReady(dc as Dc) as Void {
        drawPlate(dc, READY_TITLE_Y, "FLAPPY WATCH", labelFont(), PLATE_HALF_LABEL);
        drawPlate(dc, READY_HINT_Y, "PRESS START", labelFont(), PLATE_HALF_LABEL);
        if (mGame.getBest() > 0) {
            drawPlate(dc, READY_BEST_Y, "BEST " + mGame.getBest().format("%d"), labelFont(), PLATE_HALF_LABEL);
        }
    }

    private function drawGameOver(dc as Dc) as Void {
        drawPlate(dc, OVER_TITLE_Y, "GAME OVER", labelFont(), PLATE_HALF_LABEL);
        drawPlate(dc, OVER_SCORE_Y, "SCORE " + mGame.getScore().format("%d"), labelFont(), PLATE_HALF_LABEL);
        drawPlate(dc, OVER_BEST_Y, "BEST " + mGame.getBest().format("%d"), labelFont(), PLATE_HALF_LABEL);
        // Only invite a restart once the lock has expired, so the death press can't relaunch.
        if (mGame.canRestart()) {
            drawPlate(dc, OVER_HINT_Y, "PRESS START", labelFont(), PLATE_HALF_LABEL);
        }
    }

    // Centered white text on a black plate, so words stay legible over white pipes.
    private function drawPlate(dc as Dc, cy as Number, text as String, font as Graphics.FontType, halfH as Number) as Void {
        var w = dc.getTextWidthInPixels(text, font);
        var pad = 6;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(mCx - w / 2 - pad, cy - halfH, w + 2 * pad, halfH * 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(mCx, cy, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function labelFont() as Graphics.FontType {
        return (mLabelFont != null) ? mLabelFont : Graphics.FONT_XTINY;
    }
}

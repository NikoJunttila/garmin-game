import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// ---- View-only layout. Gameplay/geometry consts live in CatHopGame.mc and are
//      shared globally. ----
const TICK_MS = 50;        // game loop period — 20 Hz (50ms is Garmin's min timer interval)

// The Instinct 3 Solar has a small round sub-window (the "orange circle") in the top-right
// corner. We draw the live score inside it via WatchUi.getSubscreen(); these are the fallback
// center/radius (screen px) used only if the runtime can't report the region.
const SUB_FALLBACK_CX = 144;
const SUB_FALLBACK_CY = 31;
const SUB_FALLBACK_R = 18;

// Centered text rows, in the clear band between the top-right circle (ends ~y49)
// and the cat at the bottom (top ~y122).
const READY_TITLE_Y = 68;
const READY_HINT_Y = 98;

const OVER_TITLE_Y = 50;
const OVER_SCORE_Y = 80;
const OVER_BEST_Y = 108;
const OVER_HINT_Y = 136;

// Half-height of the black text "plate" drawn behind centered labels.
const PLATE_HALF_LABEL = 15;

// The game view: owns the frame timer and draws every frame from the game state.
// Physics lives only in CatHopGame.tick() (called from onTick), never in onUpdate,
// so an extra system repaint can never double-step the simulation.
class CatHopView extends WatchUi.View {

    private var mGame as CatHopGame;
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

    function initialize(game as CatHopGame) {
        View.initialize();
        mGame = game;
    }

    // Cache screen center, load the font, and locate the sub-window. No setLayout —
    // the whole screen is drawn in code.
    function onLayout(dc as Dc) as Void {
        mCx = dc.getWidth() / 2;
        mLabelFont = WatchUi.loadResource(Rez.Fonts.NordicLabel) as WatchUi.FontResource;

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
    // the jump feels instant, even between ticks.
    function onTap() as Void {
        mGame.onAction();
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        // Opaque black field, then draw everything in white (1-bit MIP: no AA, no alpha).
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        drawGround(dc);
        drawObstacles(dc);
        drawCat(dc);

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

    // White ground strip with scrolling black dashes for a sense of speed.
    private function drawGround(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(0, GROUND_Y, SCREEN_W, SCREEN_H - GROUND_Y);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        var off = mGame.getGroundOffset();
        for (var x = -off; x < SCREEN_W; x += GROUND_DASH) {
            dc.fillRectangle(x, GROUND_Y + 4, 6, 2);
        }
    }

    private function drawObstacles(dc as Dc) as Void {
        var obst = mGame.getObstacles();
        for (var i = 0; i < OBST_COUNT; i += 1) {
            var p = obst[i];
            var ox = p[OX];
            if (ox > SCREEN_W || ox + OBST_W < 0) { continue; }   // off-screen (e.g. parked in READY)
            var oh = p[OH];
            var oy = GROUND_Y - oh;

            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(ox, oy, OBST_W, oh);
            // 1px black outline so the white block never merges with the white cat.
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(1);
            dc.drawRectangle(ox, oy, OBST_W, oh);
        }
    }

    // Side-view cat facing right (toward oncoming obstacles): white silhouette with a
    // 1px black outline + eye so it reads against white obstacles. Legs animate while
    // grounded and tuck up when airborne (sells the pounce). Built up from the feet.
    private function drawCat(dc as Dc) as Void {
        var fx = CAT_X;
        var fy = mGame.getFeetPx();
        var top = fy - CAT_H;
        var grounded = mGame.isGrounded();

        // ---- white silhouette ----
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(fx + 2, top + 5, 14, 9);                 // torso
        dc.fillCircle(fx + 14, top + 6, 5);                        // head (front)
        dc.fillPolygon([[fx + 11, top + 2], [fx + 13, top - 3], [fx + 15, top + 2]]);  // ear
        dc.fillPolygon([[fx + 15, top + 2], [fx + 17, top - 3], [fx + 19, top + 2]]);  // ear
        dc.fillPolygon([[fx + 2, top + 7], [fx - 4, top + 1], [fx - 2, top + 8], [fx + 2, top + 11]]); // tail

        // ---- legs ----
        if (grounded) {
            if (mGame.getAnimPhase() == 0) {
                dc.fillRectangle(fx + 4, fy - 4, 3, 4);            // front leg fwd
                dc.fillRectangle(fx + 11, fy - 4, 3, 3);           // back leg back
            } else {
                dc.fillRectangle(fx + 5, fy - 4, 3, 3);
                dc.fillRectangle(fx + 12, fy - 4, 3, 4);
            }
        } else {
            dc.fillRectangle(fx + 6, fy - 3, 7, 3);                // tucked legs (airborne)
        }

        // ---- 1px black outline + features ----
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRectangle(fx + 2, top + 5, 14, 9);
        dc.drawCircle(fx + 14, top + 6, 5);
        dc.fillCircle(fx + 16, top + 5, 1);                        // eye
        dc.drawLine(fx + 18, top + 7, fx + 20, top + 7);           // muzzle hint
    }

    // Live score in the top-right round sub-window (the "orange circle"). A black
    // backing disc keeps the number readable when an obstacle is in that corner.
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
        drawPlate(dc, READY_TITLE_Y, "CAT HOP");
        drawPlate(dc, READY_HINT_Y, "TAP TO START");
        // (Best score is shown on the GAME OVER screen, to keep READY uncluttered.)
    }

    private function drawGameOver(dc as Dc) as Void {
        drawPlate(dc, OVER_TITLE_Y, "GAME OVER");
        drawPlate(dc, OVER_SCORE_Y, "SCORE " + mGame.getScore().format("%d"));
        drawPlate(dc, OVER_BEST_Y, "BEST " + mGame.getBest().format("%d"));
        // Only invite a restart once the lock has expired, so the death tap can't relaunch.
        if (mGame.canRestart()) {
            drawPlate(dc, OVER_HINT_Y, "TAP");
        }
    }

    // Centered white text on a black plate, so words stay legible over the scene.
    private function drawPlate(dc as Dc, cy as Number, text as String) as Void {
        var font = labelFont();
        var w = dc.getTextWidthInPixels(text, font);
        var pad = 6;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.fillRectangle(mCx - w / 2 - pad, cy - PLATE_HALF_LABEL, w + 2 * pad, PLATE_HALF_LABEL * 2);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(mCx, cy, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function labelFont() as Graphics.FontType {
        return (mLabelFont != null) ? mLabelFont : Graphics.FONT_XTINY;
    }
}

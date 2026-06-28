import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// The application object. Its one job is to hand back the initial view and its
// input delegate. The high score lives in Application.Storage and is persisted by
// the game the moment a run ends, so no save is needed here.
class CatHopApp extends Application.AppBase {

    private var mGame as CatHopGame?;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        // Vary the obstacle sequence per launch.
        Math.srand(System.getTimer());
    }

    function onStop(state as Dictionary?) as Void {
    }

    // The game view plus its button delegate.
    function getInitialView() as [Views] or [Views, InputDelegates] {
        mGame = new CatHopGame();
        var view = new CatHopView(mGame);
        var delegate = new CatHopDelegate(view);
        return [ view, delegate ];
    }
}

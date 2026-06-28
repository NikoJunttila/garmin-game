import Toybox.Lang;
import Toybox.WatchUi;

// Input handling. Per the user's choice, START/GPS, Up, and Down all flap (forgiving,
// one-handed friendly); BACK exits. We use the semantic BehaviorDelegate callbacks
// rather than raw key codes so the mapping stays correct across devices.
class FlappyDelegate extends WatchUi.BehaviorDelegate {

    private var mView as FlappyView;

    function initialize(view as FlappyView) {
        BehaviorDelegate.initialize();
        mView = view;
    }

    // START / GPS button.
    function onSelect() as Boolean {
        mView.onTap();
        return true;
    }

    // Down button.
    function onNextPage() as Boolean {
        mView.onTap();
        return true;
    }

    // Up button.
    function onPreviousPage() as Boolean {
        mView.onTap();
        return true;
    }

    // BACK / light button: let the system pop the view and exit to the watch face.
    function onBack() as Boolean {
        return false;
    }
}

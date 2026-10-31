import 'dart:ui';

/// What a two-finger touch on a phone or tablet does, decided once per gesture:
/// fingers spreading or closing zoom the view, fingers moving together scroll
/// the remote like a touchpad.
enum TwoFingerGesture { undecided, zoom, scroll }

/// Spread or pinch beyond this ratio is a zoom.
const double kTwoFingerZoomThreshold = 0.08;

/// Moving the fingers' midpoint this far (logical pixels) without zooming is a scroll.
const double kTwoFingerScrollThreshold = 12;

/// Logical pixels of finger movement per remote wheel step.
const double kTwoFingerScrollPixelsPerStep = 12;

TwoFingerGesture classifyTwoFingerGesture(double scale, Offset travel) {
  if ((scale - 1).abs() > kTwoFingerZoomThreshold) {
    return TwoFingerGesture.zoom;
  }
  if (travel.distance > kTwoFingerScrollThreshold) {
    return TwoFingerGesture.scroll;
  }
  return TwoFingerGesture.undecided;
}

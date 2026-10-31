import 'dart:math';
import 'dart:ui';

/// What a two-finger touch on a phone or tablet does, decided once per gesture:
/// fingers spreading or closing zoom the view, fingers moving together scroll
/// the remote like a touchpad.
enum TwoFingerGesture { undecided, zoom, scroll }

/// Typical distance between two fingertips on a phone, used to turn the scale
/// ratio into pixels of spread change (the exact span is not reported).
const double kTwoFingerAssumedSpan = 200;

/// Decide once the fingers have spread or moved this far (logical pixels).
const double kTwoFingerDecideDistance = 16;

/// Logical pixels of finger movement per remote wheel step.
const double kTwoFingerScrollPixelsPerStep = 12;

/// Real two-finger drags wobble in spread, and real pinches often move one
/// finger only (shifting the midpoint), so the larger of the two movements
/// decides rather than whichever crosses a threshold first.
TwoFingerGesture classifyTwoFingerGesture(double scale, Offset travel) {
  final spreadChange = (scale - 1).abs() * kTwoFingerAssumedSpan;
  final moved = travel.distance;
  if (max(spreadChange, moved) < kTwoFingerDecideDistance) {
    return TwoFingerGesture.undecided;
  }
  return spreadChange > moved ? TwoFingerGesture.zoom : TwoFingerGesture.scroll;
}

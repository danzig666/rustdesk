import 'dart:math';
import 'dart:ui';

/// What a two-finger touch on a phone or tablet does, decided once per gesture:
/// fingers spreading or closing zoom the view, fingers moving together scroll
/// the remote like a touchpad.
enum TwoFingerGesture { undecided, zoom, scroll }

/// Typical distance between two fingertips on a phone, used to turn the scale
/// ratio into pixels of spread change when finger positions are unknown.
const double kTwoFingerAssumedSpan = 200;

/// Decide once a finger (or the spread/midpoint) has moved this far, in logical pixels.
const double kTwoFingerDecideDistance = 16;

/// Logical pixels of finger movement per remote wheel step.
const double kTwoFingerScrollPixelsPerStep = 12;

/// Fallback when the individual finger positions are not known: the larger of
/// spread change and midpoint travel decides.
TwoFingerGesture classifyTwoFingerGesture(double scale, Offset travel) {
  final spreadChange = (scale - 1).abs() * kTwoFingerAssumedSpan;
  final moved = travel.distance;
  if (max(spreadChange, moved) < kTwoFingerDecideDistance) {
    return TwoFingerGesture.undecided;
  }
  return spreadChange > moved ? TwoFingerGesture.zoom : TwoFingerGesture.scroll;
}

/// Each finger must move at least this far for their directions to count.
const double kTwoFingerMinMoveForDirection = 6;

/// Directions within ~60° of each other count as "moving together".
const double kTwoFingerSameDirectionCos = 0.5;

/// Classify from where each finger started and where it is now, the way
/// touchpads do: both fingers moving the same way is a scroll; the distance
/// between them changing (even with one finger still) is a zoom. Unclear
/// movement waits, then scrolls.
TwoFingerGesture classifyTwoFingerMovement(
    Offset startA, Offset startB, Offset nowA, Offset nowB) {
  final dA = nowA - startA;
  final dB = nowB - startB;
  final moved = max(dA.distance, dB.distance);
  if (moved < kTwoFingerDecideDistance) {
    return TwoFingerGesture.undecided;
  }
  if (dA.distance >= kTwoFingerMinMoveForDirection &&
      dB.distance >= kTwoFingerMinMoveForDirection) {
    final cos = (dA.dx * dB.dx + dA.dy * dB.dy) / (dA.distance * dB.distance);
    if (cos > kTwoFingerSameDirectionCos) {
      return TwoFingerGesture.scroll;
    }
  }
  final spreadChange =
      ((nowA - nowB).distance - (startA - startB).distance).abs();
  if (spreadChange >= moved / 2) {
    return TwoFingerGesture.zoom;
  }
  return moved >= kTwoFingerDecideDistance * 2
      ? TwoFingerGesture.scroll
      : TwoFingerGesture.undecided;
}

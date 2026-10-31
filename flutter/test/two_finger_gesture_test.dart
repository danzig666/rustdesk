import 'package:flutter_hbb/common/widgets/two_finger_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const a = Offset(100, 300);
  const b = Offset(200, 300);

  group('with finger positions', () {
    test('both fingers moving the same way scroll', () {
      expect(
          classifyTwoFingerMovement(
              a, b, a + const Offset(0, 30), b + const Offset(0, 30)),
          TwoFingerGesture.scroll);
    });

    test('a scroll whose spacing changes a lot still scrolls', () {
      // One finger lags and drifts sideways: spacing changes 15 px of 30 moved.
      expect(
          classifyTwoFingerMovement(
              a, b, a + const Offset(-5, 30), b + const Offset(10, 20)),
          TwoFingerGesture.scroll);
    });

    test('fingers moving apart or together zoom', () {
      expect(
          classifyTwoFingerMovement(
              a, b, a - const Offset(20, 0), b + const Offset(20, 0)),
          TwoFingerGesture.zoom);
      expect(
          classifyTwoFingerMovement(
              a, b, a + const Offset(20, 5), b - const Offset(20, 5)),
          TwoFingerGesture.zoom);
    });

    test('a pinch moving only one finger zooms', () {
      expect(classifyTwoFingerMovement(a, b, a, b + const Offset(30, 0)),
          TwoFingerGesture.zoom);
    });

    test('a small wobble is not decided yet', () {
      expect(
          classifyTwoFingerMovement(
              a, b, a + const Offset(3, 4), b + const Offset(-2, 5)),
          TwoFingerGesture.undecided);
    });
  });

  group('fallback without finger positions', () {
    test('drag with spacing wobble scrolls, pinch zooms', () {
      expect(classifyTwoFingerGesture(1.1, const Offset(0, 40)),
          TwoFingerGesture.scroll);
      expect(classifyTwoFingerGesture(1.25, const Offset(0, 25)),
          TwoFingerGesture.zoom);
    });
  });
}

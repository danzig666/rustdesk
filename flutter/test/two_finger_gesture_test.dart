import 'package:flutter_hbb/common/widgets/two_finger_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fingers moving together scroll', () {
    expect(classifyTwoFingerGesture(1.02, const Offset(0, 30)),
        TwoFingerGesture.scroll);
  });

  test('a drag whose finger spacing wobbles still scrolls', () {
    expect(classifyTwoFingerGesture(1.1, const Offset(0, 40)),
        TwoFingerGesture.scroll);
    expect(classifyTwoFingerGesture(0.9, const Offset(5, -30)),
        TwoFingerGesture.scroll);
  });

  test('fingers spreading or pinching zoom', () {
    expect(classifyTwoFingerGesture(1.2, const Offset(0, 30)),
        TwoFingerGesture.zoom);
    expect(classifyTwoFingerGesture(0.85, Offset.zero), TwoFingerGesture.zoom);
  });

  test('a pinch moving only one finger zooms', () {
    // One finger moves 50 px apart: spread +25%, midpoint moves 25 px.
    expect(classifyTwoFingerGesture(1.25, const Offset(0, 25)),
        TwoFingerGesture.zoom);
  });

  test('a small wobble is not decided yet', () {
    expect(classifyTwoFingerGesture(1.01, const Offset(3, 4)),
        TwoFingerGesture.undecided);
  });
}

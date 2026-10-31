import 'package:flutter_hbb/common/widgets/two_finger_gesture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fingers moving together scroll', () {
    expect(classifyTwoFingerGesture(1.02, const Offset(0, 30)),
        TwoFingerGesture.scroll);
  });

  test('fingers spreading or pinching zoom', () {
    expect(classifyTwoFingerGesture(1.2, const Offset(0, 30)),
        TwoFingerGesture.zoom);
    expect(classifyTwoFingerGesture(0.85, Offset.zero), TwoFingerGesture.zoom);
  });

  test('a small wobble is not decided yet', () {
    expect(classifyTwoFingerGesture(1.01, const Offset(3, 4)),
        TwoFingerGesture.undecided);
  });
}

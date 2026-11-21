import 'package:flutter_hbb/common/widgets/extra_servers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the public server login error offers the public sign-in', () {
    expect(
        isPublicSignInError(
            'The public server requires users to log in before connecting'),
        isTrue);
    expect(isPublicSignInError('ID does not exist'), isFalse);
    expect(isPublicSignInError('Connection refused'), isFalse);
  });
}

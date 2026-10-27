import 'package:budget_buddy/services/cloud_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('data sealed with the password opens only with the same password', () async {
    final key = await CloudSync.deriveKey('u1', 'Sicher-2026!', iterations: 1000);
    final sealed = await CloudSync.seal(key, '{"transactions": 108}');
    expect(sealed, isNot(contains('transactions'))); // the server sees no content

    final same = await CloudSync.deriveKey('u1', 'Sicher-2026!', iterations: 1000);
    expect(await CloudSync.open(same, sealed), '{"transactions": 108}');

    final wrong = await CloudSync.deriveKey('u1', 'falsch', iterations: 1000);
    await expectLater(CloudSync.open(wrong, sealed), throwsA(anything));
    // the same password of another account gives another key
    final other = await CloudSync.deriveKey('u2', 'Sicher-2026!', iterations: 1000);
    await expectLater(CloudSync.open(other, sealed), throwsA(anything));
  });
}

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

  test('dirty local edits do not silently overwrite a newer cloud copy', () {
    expect(
      CloudSync.decide(dirty: true, localVersion: 2, remoteVersion: 5),
      VaultAction.conflict,
    );
    expect(
      CloudSync.decide(dirty: true, localVersion: 5, remoteVersion: 5),
      VaultAction.push,
    );
    expect(
      CloudSync.decide(dirty: true, localVersion: 5, remoteVersion: 4),
      VaultAction.push,
    );
    expect(
      CloudSync.decide(dirty: false, localVersion: 2, remoteVersion: 5),
      VaultAction.apply,
    );
    expect(
      CloudSync.decide(dirty: false, localVersion: 5, remoteVersion: null),
      VaultAction.push,
    );
    expect(
      CloudSync.decide(dirty: false, localVersion: 5, remoteVersion: 5),
      VaultAction.noop,
    );
  });

  test('conflict means the UI must choose — never silent apply on start', () {
    // documents the contract: start() sets conflict.value; keepDevice/keepCloud resolve it
    expect(
      CloudSync.decide(dirty: true, localVersion: 1, remoteVersion: 9),
      VaultAction.conflict,
    );
  });
}

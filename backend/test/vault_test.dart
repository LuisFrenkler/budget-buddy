import 'dart:io';

import 'package:test/test.dart';

import 'package:budget_buddy_backend/accounts.dart';
import 'package:budget_buddy_backend/vault.dart';

void main() {
  test('stores sealed copies with a rising version and deletes them', () async {
    final dir = Directory.systemTemp.createTempSync('bb_vault');
    final vault = Vault(dir.path);
    expect(await vault.get('u1'), isNull);
    expect(await vault.put('u1', 'sealed-1', expectedVersion: 0), 1);
    expect(await vault.put('u1', 'sealed-2', expectedVersion: 1), 2);
    expect((await vault.get('u1'))!['data'], 'sealed-2');
    expect(await vault.get('u2'), isNull); // one account never sees another's
    await expectLater(vault.put('u1', {'not': 'text'}, expectedVersion: 2), throwsA(isA<AuthError>()));
    // stale device must not overwrite a newer copy
    await expectLater(
      vault.put('u1', 'stale', expectedVersion: 1),
      throwsA(isA<AuthError>().having((e) => e.status, 'status', 409)),
    );
    expect(await vault.put('u1', 'sealed-3', expectedVersion: 2), 3);
    await vault.delete('u1');
    expect(await vault.get('u1'), isNull);
    dir.deleteSync(recursive: true);
  });
}

import 'dart:io';

import 'package:test/test.dart';

import 'package:budget_buddy_backend/accounts.dart';
import 'package:budget_buddy_backend/vault.dart';

void main() {
  test('stores sealed copies with a rising version and deletes them', () async {
    final dir = Directory.systemTemp.createTempSync('bb_vault');
    final vault = Vault(dir.path);
    expect(await vault.get('u1'), isNull);
    expect(await vault.put('u1', 'sealed-1'), 1);
    expect(await vault.put('u1', 'sealed-2'), 2);
    expect((await vault.get('u1'))!['data'], 'sealed-2');
    expect(await vault.get('u2'), isNull); // one account never sees another's
    await expectLater(vault.put('u1', {'not': 'text'}), throwsA(isA<AuthError>()));
    await vault.delete('u1');
    expect(await vault.get('u1'), isNull);
    dir.deleteSync(recursive: true);
  });
}

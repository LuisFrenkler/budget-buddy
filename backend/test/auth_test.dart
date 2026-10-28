import 'dart:convert';
import 'dart:io';

import 'package:budget_buddy_backend/accounts.dart';
import 'package:budget_buddy_backend/totp.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  // 6-digit form of the RFC 6238 SHA-1 vectors (the RFC prints 8 digits).
  const secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  final vectors = <int, String>{
    59: '287082',
    1111111109: '081804',
    1111111111: '050471',
    1234567890: '005924',
    2000000000: '279037',
    20000000000: '353130',
  };

  test('TOTP matches the RFC 6238 vectors and rejects a code outside the window', () {
    for (final entry in vectors.entries) {
      final time = DateTime.fromMillisecondsSinceEpoch(entry.key * 1000, isUtc: true);
      expect(Totp.code(secret, time), entry.value, reason: 't=${entry.key}');
      expect(Totp.matchingStep(secret, entry.value, now: time), isNotNull);
    }
    final at = DateTime.fromMillisecondsSinceEpoch(1111111111 * 1000, isUtc: true);
    expect(Totp.matchingStep(secret, Totp.code(secret, at), now: at.add(const Duration(seconds: 30))), isNotNull);
    expect(Totp.matchingStep(secret, Totp.code(secret, at), now: at.add(const Duration(seconds: 90))), isNull);
    expect(Totp.matchingStep(secret, '000000', now: at), isNull);
    expect(Totp.matchingStep(secret, '12 34 56', now: at), isNull);

    final fresh = Totp.randomSecret();
    final now = DateTime.utc(2026, 6, 1, 12);
    expect(Totp.matchingStep(fresh, Totp.code(fresh, now), now: now), isNotNull);
  });

  test('login without 2FA still returns a token; with 2FA it waits for a fresh code', () async {
    final accounts = await _accounts('flow');
    const mail = 'ada@example.com';
    const password = 'correct-horse';
    final created = await accounts.register(email: mail, password: password, name: 'Ada', device: 'Android');
    expect(created['token'], isA<String>());
    expect(created['user']['totp'], isFalse);
    expect(accounts.userFor(created['token'] as String)?['email'], mail);

    final again = await accounts.login(email: mail, password: password, device: 'iPhone oder iPad');
    expect(again.containsKey('needsTotp'), isFalse);
    expect(again['token'], isA<String>());

    final t0 = DateTime.utc(2026, 6, 1, 12);
    final setup = await accounts.beginTotp(created['user']['id'] as String, password);
    final totpSecret = setup['secret'] as String;
    expect(setup['uri'], startsWith('otpauth://totp/'));
    expect('${setup['uri']}'.contains(totpSecret), isTrue);

    final enrolled = await accounts.confirmTotp(
      created['user']['id'] as String,
      Totp.code(totpSecret, t0),
      keepToken: created['token'] as String,
      now: t0,
    );
    expect(enrolled['totp'], isTrue);
    expect('$enrolled'.contains(totpSecret), isFalse);
    // the other device never passed the new factor
    expect(accounts.userFor(again['token'] as String), isNull);
    expect(accounts.userFor(created['token'] as String), isNotNull);

    final pending = await accounts.login(email: mail, password: password, device: 'Android');
    expect(pending['needsTotp'], isTrue);
    expect(pending.containsKey('token'), isFalse);

    await expectLater(
      accounts.loginTotp(challenge: pending['challenge'] as String, code: Totp.code(totpSecret, t0), now: t0),
      throwsA(isA<AuthError>().having((e) => e.message, 'message', 'Dieser Code wurde schon benutzt.')),
    );
    final signedIn = await accounts.loginTotp(
      challenge: pending['challenge'] as String,
      code: Totp.code(totpSecret, t0.add(const Duration(seconds: 30))),
      device: 'Android\n<script>',
      now: t0.add(const Duration(seconds: 30)),
    );
    expect(signedIn['token'], isA<String>());
    expect(signedIn['user']['totp'], isTrue);
    expect('${signedIn['user']}'.contains(totpSecret), isFalse);

    final list = accounts.sessions(created['user']['id'] as String, currentToken: signedIn['token'] as String);
    expect(list.where((s) => s['current'] == true), hasLength(1));
    expect(list.firstWhere((s) => s['current'] == true)['device'], 'Android <script>');
    final other = list.firstWhere((s) => s['current'] != true);
    await accounts.revokeSession(created['user']['id'] as String, other['id'] as String);
    expect(accounts.userFor(created['token'] as String), isNull);
    expect(accounts.userFor(signedIn['token'] as String), isNotNull);

    await expectLater(
      accounts.login(email: mail, password: 'nope-nope'),
      throwsA(isA<AuthError>().having((e) => e.message, 'message', 'E-Mail oder Passwort ist falsch.')),
    );
    await expectLater(
      accounts.login(email: 'nobody@example.com', password: password),
      throwsA(isA<AuthError>().having((e) => e.message, 'message', 'E-Mail oder Passwort ist falsch.')),
    );

    final t1 = t0.add(const Duration(minutes: 2));
    await accounts.disableTotp(created['user']['id'] as String, password, Totp.code(totpSecret, t1), now: t1);
    final plain = await accounts.login(email: mail, password: password);
    expect(plain['token'], isA<String>());
    expect(plain.containsKey('needsTotp'), isFalse);
  });

  test('five wrong codes burn the challenge and lock further codes for a few minutes', () async {
    final accounts = await _accounts('burn');
    final created = await accounts.register(email: 'bea@example.com', password: 'correct-horse', name: 'Bea');
    final id = created['user']['id'] as String;
    final t0 = DateTime.utc(2026, 6, 1, 12);
    final setup = await accounts.beginTotp(id, 'correct-horse');
    await accounts.confirmTotp(id, Totp.code(setup['secret'] as String, t0), keepToken: created['token'] as String, now: t0);

    final pending = await accounts.login(email: 'bea@example.com', password: 'correct-horse');
    for (var i = 0; i < 4; i++) {
      await expectLater(
        accounts.loginTotp(challenge: pending['challenge'] as String, code: '000000', now: t0.add(const Duration(minutes: 5))),
        throwsA(isA<AuthError>().having((e) => e.status, 'status', 401)),
      );
    }
    await expectLater(
      accounts.loginTotp(challenge: pending['challenge'] as String, code: '000000', now: t0.add(const Duration(minutes: 5))),
      throwsA(isA<AuthError>().having((e) => e.status, 'status', 401)),
    );
    await expectLater(
      accounts.loginTotp(challenge: pending['challenge'] as String, code: Totp.code(setup['secret'] as String, t0.add(const Duration(minutes: 5)))),
      throwsA(isA<AuthError>().having((e) => e.status, 'status', 401)),
    );
    await expectLater(
      accounts.login(email: 'bea@example.com', password: 'correct-horse'),
      throwsA(isA<AuthError>().having((e) => e.status, 'status', 429)),
    );
  });

  test('sessions saved before this version can be listed and revoked', () async {
    final dir = Directory.systemTemp.createTempSync('bb_auth_old');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/accounts.json');
    const token = 'legacy-token-value';
    final digest = sha256.convert(utf8.encode(token)).toString();
    await file.writeAsString(jsonEncode({
      'users': {
        'u1': {'id': 'u1', 'email': 'a@b.co', 'name': 'A', 'hash': 'x', 'createdAt': '2020-01-01T00:00:00.000'},
      },
      'tokens': {
        digest: {'user': 'u1', 'expires': '2099-01-01T00:00:00.000'},
      },
    }));
    final accounts = Accounts(file);
    await accounts.load();
    final list = accounts.sessions('u1', currentToken: token);
    expect(list, hasLength(1));
    expect(list.single['current'], isTrue);
    expect('${list.single['id']}', isNotEmpty);
    expect(list.single['id'], isNot(token));
    expect(list.single['id'], isNot(digest));
    expect(accounts.userFor(token)?['id'], 'u1');

    await accounts.logoutAll('u1');
    expect(accounts.userFor(token), isNull);
    final reloaded = Accounts(file);
    await reloaded.load();
    expect(reloaded.userFor(token), isNull);
  });
}

Future<Accounts> _accounts(String name) async {
  final dir = Directory.systemTemp.createTempSync('bb_auth_$name');
  addTearDown(() => dir.deleteSync(recursive: true));
  final accounts = Accounts(File('${dir.path}/accounts.json'));
  await accounts.load();
  return accounts;
}

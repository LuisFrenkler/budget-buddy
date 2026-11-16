import 'dart:io';

import 'package:test/test.dart';

import '../lib/growth.dart';

void main() {
  late Directory dir;
  late Growth g;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('growth');
    g = Growth(File('${dir.path}/growth.json'));
  });

  tearDown(() => dir.delete(recursive: true));

  test('the front of the waitlist goes first, with language and friends', () async {
    await g.join('a@x.de');
    final b = await g.join('b@x.de', lang: 'en');
    await g.join('c@x.de');
    await g.join('d@x.de', ref: b['code'] as String);
    final front = g.front(2);
    expect(front.first['email'], 'b@x.de');
    expect(front.first['lang'], 'en');
    expect(front.first['friends'], 1);
    expect(front.length, 2);
  });

  test('joining gives a place in order and a code', () async {
    final a = await g.join('a@x.de');
    final b = await g.join('b@x.de');
    expect(a['position'], 1);
    expect(b['position'], 2);
    expect(b['total'], 2);
    expect((a['code'] as String).length, 6);
  });

  test('the same email gets its place back, not a second one', () async {
    final a = await g.join('A@x.de ');
    final again = await g.join('a@x.de');
    expect(again['code'], a['code']);
    expect(again['already'], true);
    expect(again['total'], 1);
  });

  test('each friend moves you up, past people who joined earlier', () async {
    for (var i = 0; i < 8; i++) {
      await g.join('early$i@x.de');
    }
    final me = await g.join('me@x.de');
    expect(me['position'], 9);
    await g.join('friend@x.de', ref: me['code'] as String);
    expect(g.status(me['code'] as String)['position'], 4);
    expect(g.status(me['code'] as String)['friends'], 1);
  });

  test('an unknown ref is ignored', () async {
    final a = await g.join('a@x.de', ref: 'NOPE00');
    expect(a['friends'], 0);
  });

  test('a bad email is refused', () async {
    expect(() => g.join('kein-at'), throwsA(isA<GrowthError>()));
  });

  test('app users have a code; new accounts credit it, capped reward', () async {
    final code = await g.codeFor('u1');
    expect(await g.codeFor('u1'), code);
    for (final n in ['u2', 'u3', 'u4', 'u5']) {
      await g.credit(code, n);
    }
    await g.credit(code, 'u2'); // same person twice counts once
    await g.credit(code, 'u1'); // nobody credits themselves
    final inv = g.invites('u1', code, 'https://x/?ref=$code');
    expect(inv['friends'], 4);
    expect(inv['bonusQuestions'], Growth.rewardedFriends * Growth.bonusPerFriend);
  });

  test('state survives a restart', () async {
    final a = await g.join('a@x.de');
    await g.join('b@x.de', ref: a['code'] as String);
    final again = Growth(File('${dir.path}/growth.json'));
    await again.load();
    expect(again.status(a['code'] as String)['friends'], 1);
    expect((await again.join('c@x.de'))['position'], 3);
  });

  group('guest quota', () {
    test('three questions per device and day', () {
      final q = GuestQuota();
      final now = DateTime(2026, 11, 13, 10);
      for (var i = 0; i < 3; i++) {
        q.take('device-123', '1.2.3.4', now: now);
      }
      expect(q.left('device-123', now: now), 0);
      expect(() => q.take('device-123', '1.2.3.4', now: now), throwsA(isA<GrowthError>()));
      // a new day starts fresh
      expect(q.left('device-123', now: now.add(const Duration(days: 1))), 3);
    });

    test('new device ids from one address hit the address cap', () {
      final q = GuestQuota(perDevice: 3, perIp: 5);
      final now = DateTime(2026, 11, 13);
      for (var i = 0; i < 5; i++) {
        q.take('device-00$i', '9.9.9.9', now: now);
      }
      expect(() => q.take('device-new1', '9.9.9.9', now: now), throwsA(isA<GrowthError>()));
    });

    test('a missing device id is refused', () {
      expect(() => GuestQuota().take('', '1.1.1.1'), throwsA(isA<GrowthError>()));
    });
  });
}

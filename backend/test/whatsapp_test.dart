import 'dart:io';

import 'package:budget_buddy_backend/accounts.dart';
import 'package:budget_buddy_backend/whatsapp.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late List<String> sent;

  WhatsApp open({String token = 'test-token', String phoneId = '99', String verifyToken = 'verify-me'}) {
    final log = <String>[];
    sent = log;
    return WhatsApp(
      token: token,
      phoneId: phoneId,
      verifyToken: verifyToken,
      store: File('${dir.path}/wa.json'),
      sender: (uri, headers, body) async {
        log.add(body);
        return 200;
      },
    );
  }

  setUp(() => dir = Directory.systemTemp.createTempSync('bb-wa'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('verify returns the challenge only for the right token', () {
    final wa = open();
    expect(wa.verify('subscribe', 'verify-me', 'abc_12'), 'abc_12');
    expect(wa.verify('subscribe', 'nope', 'abc_12'), isNull);
    expect(wa.verify('subscribe', 'verify-me', 'bad challenge'), isNull);
    expect(open(token: '').verify('subscribe', 'verify-me', 'abc'), isNull);
  });

  test('link stores a hash, unlink forgets it, Hilfe echoes only while opted in', () async {
    final wa = open();
    await wa.link('u1', '+49 170-1234567');
    final disk = File('${dir.path}/wa.json').readAsStringSync();
    expect(disk.contains('491701234567'), isFalse);
    expect(disk.contains('+49'), isFalse);
    expect(wa.optedIn('u1'), isTrue);

    await wa.receive({
      'entry': [
        {
          'changes': [
            {
              'value': {
                'messages': [
                  {'from': '491701234567', 'type': 'text', 'text': {'body': 'Hilfe'}},
                ]
              }
            }
          ]
        }
      ]
    });
    expect(sent, hasLength(1));
    expect(sent.single.contains('Wochenbericht'), isTrue);
    expect(sent.single.contains('491701234567'), isTrue);

    sent.clear();
    await wa.receive({
      'entry': [
        {
          'changes': [
            {
              'value': {
                'messages': [
                  {'from': '491701234567', 'type': 'text', 'text': {'body': 'Hallo'}}
                ]
              }
            }
          ]
        }
      ]
    });
    expect(sent, isEmpty);

    await wa.receive({
      'entry': [
        {
          'changes': [
            {
              'value': {
                'messages': [
                  {'from': '491701234567', 'type': 'text', 'text': {'body': 'Stop'}}
                ]
              }
            }
          ]
        }
      ]
    });
    expect(wa.optedIn('u1'), isFalse);
    expect(sent, hasLength(1));
    expect(sent.single.contains('keine weiteren'), isTrue);

    sent.clear();
    expect(wa.optedIn('u1'), isFalse);
    await wa.receive({
      'entry': [
        {
          'changes': [
            {
              'value': {
                'messages': [
                  {'from': '491701234567', 'type': 'text', 'text': {'body': 'Hilfe?'}}
                ]
              }
            }
          ]
        }
      ]
    });
    expect(sent, isEmpty);
    await wa.link('u1', '+491701234567');
    await wa.unlink('u1');
    expect(wa.optedIn('u1'), isFalse);
  });

  test('Hilfe without opt-in and a weekly summary never call Meta', () async {
    final wa = open();
    await wa.receive({
      'entry': [
        {
          'changes': [
            {
              'value': {
                'messages': [
                  {'from': '491511234567', 'type': 'text', 'text': {'body': 'Hilfe'}}
                ]
              }
            }
          ]
        }
      ]
    });
    expect(sent, isEmpty);

    await wa.link('u1', '+491511234567');
    expect(await wa.sendWeeklySummary(userId: 'u1', phone: '+491511234567'), isFalse);
    expect(await wa.sendWeeklySummary(userId: 'other', phone: '+491511234567'), isFalse);
    expect(sent, isEmpty);
    expect(await open(token: '').sendWeeklySummary(userId: 'u1', phone: '+491511234567'), isFalse);
  });

  test('a bad number is refused', () async {
    final wa = open();
    await expectLater(wa.link('u1', '01701234567'), throwsA(isA<AuthError>()));
    expect(wa.optedIn('u1'), isFalse);
  });

  test('Hilfe echo stops after three in an hour', () async {
    final wa = open();
    await wa.link('u1', '+491701234567');
    final body = {
      'entry': [
        {
          'changes': [
            {
              'value': {
                'messages': [
                  {'from': '491701234567', 'type': 'text', 'text': {'body': 'Hilfe'}}
                ]
              }
            }
          ]
        }
      ]
    };
    for (var i = 0; i < 3; i++) {
      await wa.receive(body);
    }
    expect(sent, hasLength(3));
    await wa.receive(body);
    expect(sent, hasLength(3));
  });
}

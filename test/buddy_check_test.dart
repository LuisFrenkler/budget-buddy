import 'dart:convert';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_check.dart';
import 'package:budget_buddy/services/buddy_service.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _sse(List<Map<String, dynamic>> events) => events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();

Map<String, dynamic> _text(String t) => {
      'step': {
        'content': [
          {'type': 'text', 'text': t}
        ],
        'stop': 'end_turn',
        'tools': [],
      }
    };

void main() {
  group('which amounts hold up', () {
    final data = [
      {'summe': 638.72, 'kategorien': [{'name': 'Lebensmittel', 'betrag': 412.5}]},
      {'kontostand': 1240.0, 'fixkosten': 820.0},
    ];
    List<double> loose(String a, {String lang = 'de'}) =>
        BuddyCheck.loose(a, data: data, texts: const ['Kann ich mir 800 € Urlaub leisten?'], lang: lang);

    test('looked-up, rounded and asked amounts are fine', () {
      expect(loose('Du hast **638,72 €** ausgegeben, rund 640 €, davon 412,50 € für Lebensmittel.'), isEmpty);
      expect(loose('Für die 800 € Urlaub reicht es.'), isEmpty);
    });

    test('a sum, a difference and a year are fine too', () {
      // 1.240 − 820 = 420 left, 820 × 12 = 9.840 a year
      expect(loose('Nach den Fixkosten bleiben 420 €, im Jahr sind das 9.840 € Fixkosten.'), isEmpty);
    });

    test('an amount from nowhere is caught, in both languages', () {
      expect(loose('Du hast 712,40 € ausgegeben.'), [712.40]);
      expect(loose('You spent €712.40 this month.', lang: 'en'), [712.40]);
      expect(loose('You spent €638.72, about €640.', lang: 'en'), isEmpty);
    });

    test('percentages are not checked, only euros', () {
      expect(loose('Spar 15 % davon.'), isEmpty);
    });
  });

  group('in the agent loop', () {
    final tools = BuddyTools(
      tx: [
        Transaction(
            id: 'a', amountCents: 4550, category: 'Lebensmittel', date: DateTime(2026, 11, 3), isIncome: false, note: 'Rewe'),
      ],
      snapshot: const {},
      now: DateTime(2026, 11, 14),
    );
    setUp(() {
      BuddyService.useAgent(true);
      BuddyService.tools = () => tools;
    });

    test('a made-up amount goes back once and the checked answer replaces it', () async {
      final sent = <Map<String, dynamic>>[];
      BuddyService.client = () => MockClient.streaming((req, body) async {
            sent.add(jsonDecode(await body.bytesToString()) as Map<String, dynamic>);
            final events = sent.length == 1
                ? [
                    {'t': 'Du hast **99,99 €** für Lebensmittel ausgegeben.'},
                    _text('Du hast **99,99 €** für Lebensmittel ausgegeben.'),
                  ]
                : [
                    {'t': 'Du hast **45,50 €** für Lebensmittel ausgegeben.'},
                    _text('Du hast **45,50 €** für Lebensmittel ausgegeben.'),
                  ];
            return http.StreamedResponse(Stream.value(utf8.encode(_sse(events))), 200);
          });
      final pieces = await BuddyService.ask([const ChatMessage(true, 'Wie viel für Essen?')], live: true).toList();
      expect(pieces, contains(BuddyService.restart));
      expect(pieces.sublist(pieces.indexOf(BuddyService.restart) + 1).join(), contains('45,50 €'));
      expect(sent.length, 2);
      final note = (sent[1]['messages'] as List).last['content'] as String;
      expect(note, contains('99.99'));
      expect(BuddyService.lastCorrected, isTrue);
    });

    test('an answer whose amounts hold up is not checked again', () async {
      var calls = 0;
      BuddyService.client = () => MockClient.streaming((req, body) async {
            calls++;
            return http.StreamedResponse(
                Stream.value(utf8.encode(_sse([
                  {'t': 'Kurz und gut.'},
                  _text('Kurz und gut.'),
                ]))),
                200);
          });
      final text = await BuddyService.ask([const ChatMessage(true, 'Hallo')], live: true).join();
      expect(text, 'Kurz und gut.');
      expect(calls, 1);
      expect(BuddyService.lastCorrected, isFalse);
    });
  });
}

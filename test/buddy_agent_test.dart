import 'dart:convert';
import 'dart:io';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/services/buddy_service.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _sse(List<Map<String, dynamic>> events) => events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();

void main() {
  final tools = BuddyTools(
    tx: [
      Transaction(
          id: 'a', amountCents: 4550, category: 'Lebensmittel', date: DateTime(2026, 11, 3), isIncome: false, note: 'Rewe'),
      Transaction(
          id: 'b', amountCents: 1280, category: 'Lebensmittel', date: DateTime(2026, 11, 4), isIncome: false, note: 'Edeka'),
    ],
    snapshot: const {},
    now: DateTime(2026, 11, 14),
  );

  setUp(() {
    BuddyService.useAgent(true);
    BuddyService.tools = () => tools;
  });

  test('runs the tools Claude asks for on the device and streams the answer', () async {
    final sent = <Map<String, dynamic>>[];
    BuddyService.client = () => MockClient.streaming((req, body) async {
          final payload = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          sent.add(payload);
          final events = sent.length == 1
              ? [
                  {
                    'step': {
                      'content': [
                        {'type': 'tool_use', 'id': 'tu1', 'name': 'ausgaben', 'input': {'von': '2026-11-01', 'bis': '2026-11-14'}}
                      ],
                      'stop': 'tool_use',
                      'tools': [
                        {'id': 'tu1', 'name': 'ausgaben', 'input': {'von': '2026-11-01', 'bis': '2026-11-14'}, 'zeigt': 'deine Ausgaben'}
                      ],
                    }
                  },
                  {'done': true},
                ]
              : [
                  {'t': '**58,30 €** '},
                  {'t': 'für Lebensmittel.'},
                  {
                    'step': {
                      'content': [
                        {'type': 'text', 'text': '**58,30 €** für Lebensmittel.'}
                      ],
                      'stop': 'end_turn',
                      'tools': [],
                    }
                  },
                  {'done': true},
                ];
          return http.StreamedResponse(Stream.value(utf8.encode(_sse(events))), 200);
        });

    final text = await BuddyService.ask([const ChatMessage(true, 'Was gebe ich für Essen aus?')], live: true).join();

    expect(text, '**58,30 €** für Lebensmittel.');
    expect(sent.length, 2);
    // the second step carries Claude's tool call and the result computed here
    final turns = sent[1]['messages'] as List;
    expect(turns[1]['content'][0]['type'], 'tool_use');
    final result = jsonDecode(turns[2]['content'][0]['content'] as String) as Map;
    expect(result['summe'], 58.30);
    expect(turns[2]['content'][0]['tool_use_id'], 'tu1');
    expect(sent[1]['last'], isFalse);
    expect(BuddyService.activity.value, isNull);
  });

  test('stops after the last step even if Claude keeps asking for tools', () async {
    var calls = 0;
    final lastFlags = <bool>[];
    BuddyService.client = () => MockClient.streaming((req, body) async {
          calls++;
          final payload = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
          lastFlags.add(payload['last'] == true);
          final events = [
            {
              'step': {
                'content': [
                  {'type': 'tool_use', 'id': 'x$calls', 'name': 'konten', 'input': {}}
                ],
                'stop': 'tool_use',
                'tools': [
                  {'id': 'x$calls', 'name': 'konten', 'input': {}}
                ],
              }
            },
          ];
          return http.StreamedResponse(Stream.value(utf8.encode(_sse(events))), 200);
        });
    await BuddyService.ask([const ChatMessage(true, 'Hallo')], live: true).join();
    expect(calls, BuddyService.maxSteps);
    expect(lastFlags.last, isTrue);
    expect(lastFlags.where((l) => l).length, 1);
  });

  test('a server error reaches the chat as an error', () async {
    BuddyService.client = () => MockClient.streaming((req, body) async {
          return http.StreamedResponse(Stream.value(utf8.encode(_sse([
            {'error': 'Tageslimit für Buddy erreicht.'}
          ]))), 200);
        });
    expect(BuddyService.ask([const ChatMessage(true, 'Hallo')], live: true).join(), throwsA(contains('Tageslimit')));
  });

  test('the tools the server offers are the tools the app runs', () {
    final server = File('backend/lib/agent.dart').readAsStringSync();
    final offered = RegExp(r"'name': '([a-z_]+)'").allMatches(server).map((m) => m.group(1)).toSet();
    expect(offered, BuddyTools.names);
  });
}

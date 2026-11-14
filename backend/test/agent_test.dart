import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../lib/agent.dart';
import '../lib/ai.dart';

// a Claude stream as server-sent events
String _sse(List<Map<String, dynamic>> events) => events.map((e) => 'data: ${jsonEncode(e)}\n\n').join();

void main() {
  group('step', () {
    test('streams text, rebuilds thinking and tool calls, reports the stop reason', () async {
      late Map<String, dynamic> sent;
      final agent = BuddyAgent('key', client: () => MockClient.streaming((req, body) async {
            sent = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            final stream = _sse([
              {'type': 'message_start', 'message': {}},
              {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'thinking', 'thinking': ''}},
              {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'thinking_delta', 'thinking': 'Erst Ausgaben '}},
              {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'thinking_delta', 'thinking': 'holen.'}},
              {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'signature_delta', 'signature': 'sig'}},
              {'type': 'content_block_stop', 'index': 0},
              {'type': 'content_block_start', 'index': 1, 'content_block': {'type': 'tool_use', 'id': 'tu1', 'name': 'ausgaben', 'input': {}}},
              {'type': 'content_block_delta', 'index': 1, 'delta': {'type': 'input_json_delta', 'partial_json': '{"von":"2026-11-01",'}},
              {'type': 'content_block_delta', 'index': 1, 'delta': {'type': 'input_json_delta', 'partial_json': '"bis":"2026-11-14"}'}},
              {'type': 'content_block_stop', 'index': 1},
              {'type': 'message_delta', 'delta': {'stop_reason': 'tool_use'}},
              {'type': 'message_stop'},
            ]);
            return http.StreamedResponse(Stream.value(utf8.encode(stream)), 200);
          }));

      final events = await agent.step([
        {'role': 'user', 'content': 'Wie viel habe ich diesen Monat ausgegeben?'}
      ]).toList();

      final done = events.last as AgentDone;
      expect(done.stopReason, 'tool_use');
      expect(done.model, 'claude-haiku-5-5');
      expect(done.content.first, {'type': 'thinking', 'thinking': 'Erst Ausgaben holen.', 'signature': 'sig'});
      expect(done.toolCalls.single['input'], {'von': '2026-11-01', 'bis': '2026-11-14'});
      // the request carries the tools, the cached prompt and today's context
      expect((sent['tools'] as List).length, BuddyAgent.tools.length);
      expect(sent['system'][0]['cache_control'], {'type': 'ephemeral'});
      expect(sent['system'][1]['text'], startsWith('Heute ist '));
      expect(sent.containsKey('tool_choice'), isFalse);
    });

    test('text pieces arrive as they come', () async {
      final agent = BuddyAgent('key', client: () => MockClient.streaming((req, body) async {
            final stream = _sse([
              {'type': 'content_block_start', 'index': 0, 'content_block': {'type': 'text', 'text': ''}},
              {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': '**312 €** '}},
              {'type': 'content_block_delta', 'index': 0, 'delta': {'type': 'text_delta', 'text': 'diesen Monat.'}},
              {'type': 'content_block_stop', 'index': 0},
              {'type': 'message_delta', 'delta': {'stop_reason': 'end_turn'}},
            ]);
            return http.StreamedResponse(Stream.value(utf8.encode(stream)), 200);
          }));
      final events = await agent.step([
        {'role': 'user', 'content': 'Ausgaben?'}
      ], lastStep: true).toList();
      expect(events.whereType<AgentText>().map((e) => e.text).join(), '**312 €** diesen Monat.');
      final done = events.last as AgentDone;
      expect(done.stopReason, 'end_turn');
      expect(done.content.single, {'type': 'text', 'text': '**312 €** diesen Monat.'});
    });

    test('the last step may not call tools', () async {
      late Map<String, dynamic> sent;
      final agent = BuddyAgent('key', client: () => MockClient.streaming((req, body) async {
            sent = jsonDecode(await body.bytesToString()) as Map<String, dynamic>;
            return http.StreamedResponse(Stream.value(utf8.encode(_sse([]))), 200);
          }));
      await agent.step([
        {'role': 'user', 'content': 'x'}
      ], lastStep: true).toList();
      expect(sent['tool_choice'], {'type': 'none'});
    });
  });

  group('gemini', () {
    test('the conversation keeps tool names, signatures and results', () {
      final contents = BuddyAgent.geminiContents([
        {'role': 'user', 'content': 'Wie viel für Essen?'},
        {
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': 'g1', 'name': 'ausgaben', 'input': {'von': '2026-11-01'}, 'gemini_signature': 'sig'}
          ]
        },
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'g1', 'content': '{"summe": 58.3}'}
          ]
        },
      ]);
      expect(contents[1]['role'], 'model');
      expect(contents[1]['parts'][0], {
        'functionCall': {'name': 'ausgaben', 'args': {'von': '2026-11-01'}},
        'thoughtSignature': 'sig',
      });
      expect(contents[2]['parts'][0]['functionResponse'], {
        'name': 'ausgaben',
        'response': {'summe': 58.3}
      });
    });

    test('tools without fields have no parameters, others a Gemini schema', () {
      final decl = BuddyAgent.geminiTools.single['function_declarations'] as List;
      final konten = decl.firstWhere((d) => d['name'] == 'konten') as Map;
      expect(konten.containsKey('parameters'), isFalse);
      final ausgaben = decl.firstWhere((d) => d['name'] == 'ausgaben') as Map;
      expect(ausgaben['parameters']['type'], 'OBJECT');
      expect(ausgaben['parameters']['properties']['von']['type'], 'STRING');
    });

    test('a step on Gemini asks for tools the same way', () async {
      late Map<String, dynamic> sent;
      final agent = BuddyAgent('', gemini: Ai('', geminiKey: 'g'), client: () => MockClient((req) async {
            sent = jsonDecode(req.body) as Map<String, dynamic>;
            return http.Response(
                jsonEncode({
                  'candidates': [
                    {
                      'content': {
                        'parts': [
                          {'text': 'nachdenken', 'thought': true},
                          {
                            'functionCall': {'name': 'konten', 'args': {}},
                            'thoughtSignature': 'abc'
                          }
                        ]
                      }
                    }
                  ]
                }),
                200);
          }));
      expect(agent.enabled, isTrue);
      final events = await agent.step([
        {'role': 'user', 'content': 'Kontostand?'}
      ]).toList();
      final done = events.single as AgentDone;
      expect(done.stopReason, 'tool_use');
      expect(done.toolCalls.single['name'], 'konten');
      expect(done.toolCalls.single['gemini_signature'], 'abc');
      expect(sent['tool_config']['function_calling_config']['mode'], 'AUTO');
      expect(sent['system_instruction']['parts'][0]['text'], contains('Werkzeuge'));
    });
  });

  group('model choice', () {
    final agent = BuddyAgent('key');
    test('quick questions stay on the fast model', () {
      expect(agent.pickModel([
        {'role': 'user', 'content': 'Wie viel habe ich für Essen ausgegeben?'}
      ]), agent.fastModel);
    });
    test('affordability and plans go to the strong model', () {
      expect(agent.pickModel([
        {'role': 'user', 'content': 'Kann ich mir eine Wohnung für 900 € leisten?'}
      ]), agent.strongModel);
    });
    test('later steps of one answer keep the model of the question', () {
      final messages = [
        {'role': 'user', 'content': 'Mach mir einen Plan fürs nächste Jahr'},
        {
          'role': 'assistant',
          'content': [
            {'type': 'tool_use', 'id': 'a', 'name': 'konten', 'input': {}}
          ]
        },
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 'a', 'content': '{}'}
          ]
        },
      ];
      expect(agent.pickModel(messages), agent.strongModel);
      expect(BuddyAgent.startsAnswer(messages), isFalse);
      expect(BuddyAgent.startsAnswer(messages.sublist(0, 1)), isTrue);
    });
  });

  group('clean', () {
    test('keeps assistant blocks as sent and drops what does not belong', () {
      final out = BuddyAgent.clean([
        {'role': 'user', 'content': 'Hallo'},
        {
          'role': 'assistant',
          'content': [
            {'type': 'thinking', 'thinking': 'x', 'signature': 's'},
            {'type': 'tool_use', 'id': 't', 'name': 'konten', 'input': {}},
            {'type': 'image', 'source': {}},
          ]
        },
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 't', 'content': {'kontostand': 12.5}},
            {'type': 'tool_use', 'id': 'fake', 'name': 'konten', 'input': {}},
          ]
        },
        'kaputt',
      ]);
      expect(out.length, 3);
      expect((out[1]['content'] as List).length, 2);
      expect((out[2]['content'] as List).single['content'], '{"kontostand":12.5}');
    });

    test('a conversation never opens with tool results', () {
      final out = BuddyAgent.clean([
        {
          'role': 'user',
          'content': [
            {'type': 'tool_result', 'tool_use_id': 't', 'content': '{}'}
          ]
        },
        {'role': 'user', 'content': 'Und jetzt?'},
      ]);
      expect(out.single['content'], 'Und jetzt?');
    });
  });

  test('context carries the date, memories and the life stage', () {
    final text = BuddyAgent.contextText({
      'name': 'Luis',
      'erinnerungen': ['Gehalt kommt am 28.'],
      'lebenslage': {'name': 'Erster Job'},
    });
    expect(text, contains('Heute ist'));
    expect(text, contains('Luis'));
    expect(text, contains('- Gehalt kommt am 28.'));
    expect(text, contains('Erster Job'));
  });

  test('every tool has a German description, a schema and a line for the app', () {
    for (final t in BuddyAgent.tools) {
      expect(t['description'], isNotEmpty);
      expect(t['input_schema']['type'], 'object');
      expect(BuddyAgent.activity[t['name']], isNotNull, reason: '${t['name']}');
    }
    expect(BuddyAgent.tools.last['cache_control'], isNotNull);
  });
}

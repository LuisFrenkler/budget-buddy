import 'package:test/test.dart';

import 'package:budget_buddy_backend/agent.dart';
import 'package:budget_buddy_backend/ai.dart';

void main() {
  test('a JSON schema becomes Gemini\'s response schema', () {
    final s = Ai.geminiSchema({
      'type': 'object',
      'additionalProperties': false,
      'required': ['amount', 'kind'],
      'properties': {
        'amount': {'type': ['number', 'null'], 'description': 'Euro'},
        'kind': {'type': 'string', 'enum': ['a', 'b']},
        'date': {'type': 'string', 'format': 'date'},
        'list': {
          'type': 'array',
          'items': {'type': 'object', 'properties': {'x': {'type': 'boolean'}}}
        },
      },
    });
    expect(s['type'], 'OBJECT');
    expect(s.containsKey('additionalProperties'), isFalse);
    expect(s['required'], ['amount', 'kind']);
    expect(s['properties']['amount'], {'type': 'NUMBER', 'nullable': true, 'description': 'Euro'});
    expect(s['properties']['kind']['enum'], ['a', 'b']);
    expect((s['properties']['date'] as Map).containsKey('format'), isFalse);
    expect(s['properties']['list']['items']['properties']['x']['type'], 'BOOLEAN');
  });

  test('number enums move into the description, Gemini rejects them otherwise', () {
    final s = Ai.geminiSchema({
      'type': 'object',
      'properties': {
        'steuerklasse': {'type': 'integer', 'enum': [1, 2, 3, 4]},
        'monat': {'type': 'integer', 'description': 'Monat', 'enum': [1, 2]},
      },
    });
    expect(s['properties']['steuerklasse'], {'type': 'INTEGER', 'description': 'Erlaubt: 1, 2, 3, 4'});
    expect(s['properties']['monat']['description'], 'Monat (Erlaubt: 1, 2)');
  });

  test('every agent tool is valid for Gemini: enums only on strings', () {
    void check(Object? node, String path) {
      if (node is Map) {
        final e = node['enum'];
        if (e is List) {
          expect(node['type'], 'STRING', reason: path);
          expect(e.every((v) => v is String), isTrue, reason: path);
        }
        node.forEach((k, v) => check(v, '$path.$k'));
      } else if (node is List) {
        for (var i = 0; i < node.length; i++) {
          check(node[i], '$path[$i]');
        }
      }
    }

    check(BuddyAgent.geminiTools, 'tools');
  });

  test('photos and text become Gemini parts; answers are read, blocked ones refused', () {
    final parts = Ai.geminiParts([
      {'type': 'image', 'source': {'type': 'base64', 'media_type': 'image/png', 'data': 'QUJD'}},
      {'type': 'text', 'text': 'Kassenbon'},
    ]);
    expect(parts.first, {'inline_data': {'mime_type': 'image/png', 'data': 'QUJD'}});
    expect(parts.last, {'text': 'Kassenbon'});

    expect(
        Ai.geminiText({
          'candidates': [
            {'content': {'parts': [{'text': 'Hal'}, {'text': 'lo'}]}, 'finishReason': 'STOP'}
          ]
        }),
        'Hallo');
    expect(() => Ai.geminiText({'candidates': [{'finishReason': 'SAFETY'}]}), throwsA(isA<AiError>()));
    expect(() => Ai.geminiText({'promptFeedback': {'blockReason': 'SAFETY'}}), throwsA(isA<AiError>()));
  });

  test('without any key the AI is off; with only a Gemini key it runs on Gemini', () {
    expect(Ai('').enabled, isFalse);
    final g = Ai('', geminiKey: 'k');
    expect(g.enabled, isTrue);
    expect(g.name, 'Gemini (gemini-3.5-flash)');
    expect(Ai('sk', geminiKey: 'k').name, 'Claude');
  });
}

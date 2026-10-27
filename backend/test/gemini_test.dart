import 'package:test/test.dart';

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
    expect(g.name, 'Gemini (gemini-2.5-flash)');
    expect(Ai('sk', geminiKey: 'k').name, 'Claude');
  });
}

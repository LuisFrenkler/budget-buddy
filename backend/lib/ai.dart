// AI features through the Claude API (raw HTTP; there is no official Dart
// SDK). The key stays on this server: set ANTHROPIC_API_KEY.
//
// - chat:    "Buddy", a finance coach that answers from a summary of the
//            user's finances, streamed word by word
// - parse:   one line of text ("Döner 8,50 gestern") -> a booking
// - receipt: a photo of a receipt -> a booking
//
// Requests use Claude Opus 5.5 with server-side refusal fallbacks
// (`fallbacks: "default"`), and check the stop reason before reading text.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AiError implements Exception {
  final String message;
  const AiError(this.message);
  @override
  String toString() => message;
}

class Ai {
  static const _url = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-opus-5-5';

  final String apiKey;
  Ai(this.apiKey);

  bool get enabled => apiKey.isNotEmpty;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2026-10-21',
        'anthropic-beta': 'server-side-fallback-2026-07-01',
      };

  // the stable part of every chat request, kept first so it can be cached
  static const _chatSystem = '''
Du bist Buddy, der Finanzcoach in der App BudgetBuddy. Du sprichst Deutsch, duzt,
bist warm, direkt und konkret, wie ein guter Freund, der sich mit Geld auskennt.

Du bekommst eine Zusammenfassung der Finanzen der Person als JSON (Beträge in Euro).
Antworte nur auf Basis dieser Daten und rechne nach, bevor du Zahlen nennst. Wenn etwas
in den Daten fehlt, sag das kurz, statt zu raten.

Form: kurz und gut lesbar auf dem Handy. Höchstens etwa 120 Wörter. Nutze **fett** für
die wichtigste Zahl und kurze Aufzählungen mit "- ". Keine Überschriften, keine Tabellen.
Schließe, wenn es passt, mit einem konkreten nächsten Schritt.

Grenzen: keine Empfehlungen für einzelne Wertpapiere und keine Steuer- oder Rechtsberatung;
allgemeine Prinzipien (Notgroschen, Streuung, Kosten) sind in Ordnung.''';

  // streams Buddy's answer as text pieces
  Stream<String> chat({required Map<String, dynamic> finances, required List<Map<String, dynamic>> history}) async* {
    if (!enabled) throw const AiError('KI ist auf dem Server nicht eingerichtet.');
    // the snapshot goes into the first user turn, so the system prompt stays cacheable
    final messages = <Map<String, dynamic>>[];
    // every turn is paid again with each question: a long chat keeps its
    // first question (it carries the finances) and the latest 20 turns
    if (history.length > 21) {
      var tail = history.sublist(history.length - 20);
      if (tail.first['role'] != 'assistant') tail = tail.sublist(1);
      history = [history.first, ...tail];
    }
    for (int i = 0; i < history.length; i++) {
      final m = history[i];
      final role = m['role'] == 'assistant' ? 'assistant' : 'user';
      var text = '${m['text'] ?? ''}';
      if (text.length > 4000) text = text.substring(0, 4000);
      if (i == 0 && role == 'user') {
        text = 'Meine Finanzen (Stand heute):\n${jsonEncode(finances)}\n\nMeine Frage: $text';
      }
      messages.add({'role': role, 'content': text});
    }

    final req = http.Request('POST', Uri.parse(_url))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': _model,
        'max_tokens': 4000,
        'stream': true,
        'fallbacks': 'default',
        // chat answers are short; moderate thinking keeps them quick but careful
        'output_config': {'effort': 'medium'},
        'system': [
          {'type': 'text', 'text': _chatSystem, 'cache_control': {'type': 'ephemeral'}},
        ],
        'messages': messages,
      });

    final client = http.Client();
    try {
      final res = await client.send(req);
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw AiError(_apiError(res.statusCode, body));
      }
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final event = jsonDecode(line.substring(6)) as Map<String, dynamic>;
        switch (event['type']) {
          case 'content_block_delta':
            final delta = event['delta'] as Map<String, dynamic>;
            if (delta['type'] == 'text_delta') yield delta['text'] as String;
          case 'message_delta':
            if (event['delta']?['stop_reason'] == 'refusal') {
              throw const AiError('Dazu kann Buddy leider nichts sagen.');
            }
          case 'error':
            throw AiError('${event['error']?['message'] ?? 'Fehler der KI'}');
        }
      }
    } finally {
      client.close();
    }
  }

  // the shape of a booking that parse and receipt both return
  static Map<String, dynamic> _bookingSchema(List<String> categories) => {
        'type': 'object',
        'additionalProperties': false,
        'required': ['amount', 'isIncome', 'category', 'note', 'date'],
        'properties': {
          'amount': {'type': 'number', 'description': 'Betrag in Euro, positiv'},
          'isIncome': {'type': 'boolean'},
          'category': {'type': 'string', 'enum': categories},
          'note': {'type': 'string', 'description': 'kurzer Titel, z. B. Händlername'},
          'date': {'type': 'string', 'format': 'date'},
        },
      };

  Future<Map<String, dynamic>> _booking(List<Map<String, dynamic>> content, List<String> categories) async {
    if (!enabled) throw const AiError('KI ist auf dem Server nicht eingerichtet.');
    final res = await http
        .post(Uri.parse(_url),
            headers: _headers,
            body: jsonEncode({
              'model': _model,
              'max_tokens': 2000,
              'fallbacks': 'default',
              // a simple extraction: little thinking needed
              'output_config': {
                'effort': 'low',
                'format': {'type': 'json_schema', 'schema': _bookingSchema(categories)},
              },
              'messages': [
                {'role': 'user', 'content': content}
              ],
            }))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw AiError(_apiError(res.statusCode, res.body));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (body['stop_reason'] == 'refusal') throw const AiError('Das konnte die KI nicht auslesen.');
    final text = [
      for (final b in (body['content'] as List))
        if (b['type'] == 'text') b['text']
    ].join();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  Future<Map<String, dynamic>> parse(String text, List<String> categories) => _booking([
        {
          'type': 'text',
          'text': 'Heute ist ${_today()}. Mach aus dieser Notiz eine Buchung für eine deutsche Finanz-App. '
              'Relative Angaben wie "gestern" beziehen sich auf heute. Ohne Datum: heute. '
              'Ohne Hinweis auf Einnahme ist es eine Ausgabe.\n\nNotiz: $text',
        }
      ], categories);

  Future<Map<String, dynamic>> receipt(String base64Image, String mediaType, List<String> categories) => _booking([
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Image},
        },
        {
          'type': 'text',
          'text': 'Heute ist ${_today()}. Lies diesen Kassenbon oder diese Rechnung: Gesamtbetrag (Summe, '
              'nicht Einzelposten), Händler als Titel, Kaufdatum (sonst heute) und die passende Kategorie. '
              'Es ist eine Ausgabe.',
        },
      ], categories);

  static String _apiError(int status, String body) {
    if (status == 401) return 'Der KI-Schlüssel des Servers ist ungültig.';
    if (status == 429) return 'Die KI ist gerade ausgelastet. Bitte gleich noch einmal.';
    if (status >= 500) return 'Die KI ist kurz nicht erreichbar.';
    try {
      return 'KI-Fehler: ${(jsonDecode(body) as Map)['error']?['message']}';
    } catch (_) {
      return 'KI-Fehler $status';
    }
  }
}

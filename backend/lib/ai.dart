// AI features through the Claude API (raw HTTP; there is no official Dart
// SDK). The key stays on this server: set ANTHROPIC_API_KEY. Without it a
// GEMINI_API_KEY (Google AI Studio, free tier with daily limits) runs the
// same prompts on Gemini Flash.
//
// - chat:    "Buddy", a finance coach that answers from a summary of the
//            user's finances, streamed word by word
// - parse:   one line of text ("Döner 8,50 gestern") -> a booking
// - receipt: a photo of a receipt -> a booking
//
// Requests use Claude Haiku 5.5 (about 0.1 cent a question) and check the
// stop reason before reading text; Haiku has no server-side refusal fallback.
// Haiku thinks by default, so max_tokens leaves room for it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class AiError implements Exception {
  final String message;
  const AiError(this.message);
  @override
  String toString() => message;
}

class Ai {
  static const _url = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-haiku-5-5';
  static const _gemini = 'https://generativelanguage.googleapis.com/v1beta/models';

  final String apiKey;
  final String geminiKey;
  final String geminiModel;
  Ai(this.apiKey, {this.geminiKey = '', String geminiModel = ''})
      : geminiModel = geminiModel.isEmpty ? 'gemini-3.5-flash' : geminiModel;

  // Claude when its key is set, otherwise Gemini
  bool get _claude => apiKey.isNotEmpty;
  bool get enabled => _claude || geminiKey.isNotEmpty;
  String get name => _claude ? 'Claude' : 'Gemini ($geminiModel)';
  // who answers, so the app can say whom the data goes to
  String get provider => _claude ? 'anthropic' : 'google';

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2026-10-21',
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

    if (!_claude) {
      yield* _geminiStream(messages);
      return;
    }
    final req = http.Request('POST', Uri.parse(_url))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': _model,
        'max_tokens': 8000,
        'stream': true,
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

  Future<Map<String, dynamic>> _booking(List<Map<String, dynamic>> content, List<String> categories) =>
      _structured(content, _bookingSchema(categories));

  // one request whose answer is JSON in the given shape
  Future<Map<String, dynamic>> _structured(List<Map<String, dynamic>> content, Map<String, dynamic> schema) async {
    if (!enabled) throw const AiError('KI ist auf dem Server nicht eingerichtet.');
    if (!_claude) return _geminiJson(content, schema);
    final res = await http
        .post(Uri.parse(_url),
            headers: _headers,
            body: jsonEncode({
              'model': _model,
              'max_tokens': 4000,
              // a simple extraction: little thinking needed
              'output_config': {
                'effort': 'low',
                'format': {'type': 'json_schema', 'schema': schema},
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

  // What happened, in the user's words or on a photo (receipt, bank
  // screenshot, broker confirmation) -> the entries it means for their
  // accounts and depots, plus one sentence back. Nothing is stored here: the
  // app shows each entry and the user confirms it.
  static Map<String, dynamic> _entriesSchema() {
    Map<String, dynamic> maybe(String type, [String? description]) =>
        {'type': [type, 'null'], if (description != null) 'description': description};
    return {
      'type': 'object',
      'additionalProperties': false,
      'required': ['reply', 'entries'],
      'properties': {
        'reply': {'type': 'string', 'description': 'ein, zwei Sätze an den Nutzer, was du erkannt hast'},
        'entries': {
          'type': 'array',
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'required': [
              'type', 'amount', 'isIncome', 'category', 'note', 'date', 'account', 'toAccount',
              'name', 'symbol', 'shares', 'price', 'depot',
            ],
            'properties': {
              'type': {'type': 'string', 'enum': ['booking', 'transfer', 'buy', 'sell']},
              'amount': maybe('number', 'Euro, positiv; bei booking und transfer'),
              'isIncome': maybe('boolean', 'nur bei booking'),
              'category': maybe('string', 'nur bei booking, eine der Kategorien'),
              'note': maybe('string', 'kurzer Titel, z. B. Händler'),
              'date': maybe('string', 'YYYY-MM-DD'),
              'account': maybe('string', 'id des Kontos, von dem das Geld kommt bzw. auf dem gebucht wird'),
              'toAccount': maybe('string', 'nur bei transfer: id des Zielkontos'),
              'name': maybe('string', 'nur bei buy/sell: Name des Wertpapiers oder Coins'),
              'symbol': maybe('string', 'nur bei buy/sell: Ticker, z. B. AAPL, SAP.DE, BTC'),
              'shares': maybe('number', 'nur bei buy/sell: Stückzahl'),
              'price': maybe('number', 'nur bei buy/sell: Kurs je Stück in Euro'),
              'depot': maybe('string', 'nur bei buy/sell: Name des Depots'),
            },
          },
        },
      },
    };
  }

  Future<Map<String, dynamic>> entries({
    required String text,
    String? base64Image,
    String mediaType = 'image/jpeg',
    required List<String> categories,
    required List<Map<String, dynamic>> accounts,
    required List<String> depots,
  }) async {
    if (!enabled) throw const AiError('KI ist auf dem Server nicht eingerichtet.');
    final accountList = [for (final a in accounts) '- ${a['id']}: ${a['name']} (${a['kind']})'].join('\n');
    final prompt = 'Heute ist ${_today()}. Du bist Buddy in einer deutschen Finanz-App. Der Nutzer erzählt, '
        'was passiert ist, oder schickt ein Foto. Mach daraus Einträge für seine Konten und Depots.\n\n'
        'Seine Konten:\n$accountList\n'
        'Seine Depots: ${depots.isEmpty ? 'noch keins' : depots.join(', ')}\n'
        'Kategorien: ${categories.join(', ')}\n\n'
        'Regeln: Ein Einkauf, eine Rechnung oder ein Gehalt ist ein booking. Geld zwischen zwei seiner Konten '
        'ist ein transfer. Ein Wertpapier- oder Krypto-Kauf ist buy, ein Verkauf sell, mit Stückzahl und Kurs; '
        'das Geld kommt vom genannten Konto, sonst account null. Ohne genanntes Konto: account null. '
        'Relative Angaben wie "gestern" beziehen sich auf heute, ohne Datum heute. Auf einem Kassenbon zählt '
        'der Gesamtbetrag. Erfinde nichts: Wenn nichts zu buchen ist, gib keine Einträge zurück und beantworte '
        'die Nachricht kurz. Die Antwort sagt in ein, zwei Sätzen, was du erkannt hast. Schreib nicht, dass du '
        'etwas eingetragen oder erfasst hast: Der Nutzer sieht die Einträge und bestätigt jeden selbst.\n\n'
        'Nachricht: ${text.isEmpty ? '(nur ein Foto)' : text}';
    return _structured([
      if (base64Image != null && base64Image.isNotEmpty)
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': mediaType, 'data': base64Image},
        },
      {'type': 'text', 'text': prompt},
    ], _entriesSchema());
  }

  // --- Gemini (Google AI Studio) ---

  Map<String, String> get _geminiHeaders => {'Content-Type': 'application/json', 'x-goog-api-key': geminiKey};

  // Gemini's free models are often busy for a moment (503, 429): wait,
  // try again, then try the other current Flash model
  List<String> get _geminiModels => {geminiModel, 'gemini-3.5-flash', 'gemini-3.8-flash', 'gemini-3.7-flash'}.toList();

  // a model whose quota ran out rests until Google says it is back
  static final _resting = <String, DateTime>{};

  Future<http.StreamedResponse> _geminiSend(String action, Map<String, dynamic> body, {required http.Client client}) async {
    final now = DateTime.now();
    final models = [for (final m in _geminiModels) if (!(_resting[m]?.isAfter(now) ?? false)) m];
    // the free tier allows a few requests a day per model: when all rest, Buddy answers offline
    if (models.isEmpty) throw const AiError(quotaMessage);
    final tries = [for (final m in models) ...[m, m]];
    // the app waits about a minute; a slow model must not use it all up
    final deadline = now.add(const Duration(seconds: 55));
    for (var i = 0; i < tries.length; i++) {
      if (_resting[tries[i]]?.isAfter(DateTime.now()) ?? false) continue;
      final last = i == tries.length - 1 || DateTime.now().isAfter(deadline);
      final req = http.Request('POST', Uri.parse('$_gemini/${tries[i]}:$action'))
        ..headers.addAll(_geminiHeaders)
        ..body = jsonEncode(body);
      final http.StreamedResponse res;
      try {
        res = await client.send(req).timeout(Duration(seconds: last ? 30 : 20));
      } on TimeoutException {
        stderr.writeln('gemini ${tries[i]}: no answer in time');
        if (last) throw const AiError('Die KI ist gerade ausgelastet. Bitte gleich noch einmal.');
        continue;
      }
      if (res.statusCode == 200) return res;
      final text = await res.stream.bytesToString();
      stderr.writeln('gemini ${tries[i]}: HTTP ${res.statusCode}');
      if (res.statusCode == 429) {
        // a used-up quota names when it comes back ("retryDelay": "45214s")
        final wait = int.tryParse(RegExp(r'"retryDelay":\s*"(\d+)s"').firstMatch(text)?.group(1) ?? '') ?? 60;
        _resting[tries[i]] = DateTime.now().add(Duration(seconds: wait));
      } else if (res.statusCode != 503) {
        throw AiError(_apiError(res.statusCode, text));
      }
      if (last) break;
      await Future<void>.delayed(Duration(milliseconds: 800 * (i % 2 + 1)));
    }
    throw const AiError(quotaMessage);
  }

  // the app falls back to its offline answers on this message
  static const quotaMessage = 'Die KI ist gerade ausgelastet. Bitte gleich noch einmal.';

  // Claude's content blocks as Gemini parts
  static List<Map<String, dynamic>> geminiParts(List<Map<String, dynamic>> content) => [
        for (final b in content)
          if (b['type'] == 'image')
            {
              'inline_data': {'mime_type': b['source']['media_type'], 'data': b['source']['data']}
            }
          else
            {'text': '${b['text'] ?? ''}'},
      ];

  // a JSON schema as Gemini's response schema: upper-case types, "nullable"
  // instead of a null type, no additionalProperties or formats
  static Map<String, dynamic> geminiSchema(Map<String, dynamic> schema) {
    final out = <String, dynamic>{};
    final type = schema['type'];
    if (type is List) {
      out['type'] = '${type.firstWhere((t) => t != 'null')}'.toUpperCase();
      if (type.contains('null')) out['nullable'] = true;
    } else if (type != null) {
      out['type'] = '$type'.toUpperCase();
    }
    if (schema['description'] != null) out['description'] = schema['description'];
    if (schema['enum'] != null) out['enum'] = schema['enum'];
    if (schema['required'] != null) out['required'] = schema['required'];
    final props = schema['properties'] as Map?;
    if (props != null) {
      out['properties'] = {for (final e in props.entries) e.key: geminiSchema((e.value as Map).cast<String, dynamic>())};
    }
    if (schema['items'] != null) out['items'] = geminiSchema((schema['items'] as Map).cast<String, dynamic>());
    return out;
  }

  // the text of a Gemini answer; a blocked answer says so
  static String geminiText(Map<String, dynamic> body) {
    final candidates = (body['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) throw const AiError('Dazu kann Buddy leider nichts sagen.');
    final c = candidates.first as Map;
    if (c['finishReason'] == 'SAFETY' || c['finishReason'] == 'PROHIBITED_CONTENT') {
      throw const AiError('Dazu kann Buddy leider nichts sagen.');
    }
    return [for (final p in ((c['content'] as Map?)?['parts'] as List?) ?? const []) (p as Map)['text'] ?? ''].join();
  }

  Future<Map<String, dynamic>> _geminiJson(List<Map<String, dynamic>> content, Map<String, dynamic> schema) async {
    final client = http.Client();
    try {
      final res = await http.Response.fromStream(await _geminiSend('generateContent', {
        'contents': [
          {'role': 'user', 'parts': geminiParts(content)}
        ],
        'generationConfig': {'responseMimeType': 'application/json', 'responseSchema': geminiSchema(schema)},
      }, client: client));
      if (res.statusCode != 200) throw AiError(_apiError(res.statusCode, res.body));
      return jsonDecode(geminiText(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>)) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  Stream<String> _geminiStream(List<Map<String, dynamic>> messages) async* {
    final body = {
        'systemInstruction': {
          'parts': [
            {'text': _chatSystem}
          ]
        },
        'contents': [
          for (final m in messages)
            {
              'role': m['role'] == 'assistant' ? 'model' : 'user',
              'parts': [
                {'text': m['content']}
              ],
            }
        ],
      };
    final client = http.Client();
    try {
      final res = await _geminiSend('streamGenerateContent?alt=sse', body, client: client);
      if (res.statusCode != 200) throw AiError(_apiError(res.statusCode, await res.stream.bytesToString()));
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final piece = geminiText(jsonDecode(line.substring(6)) as Map<String, dynamic>);
        if (piece.isNotEmpty) yield piece;
      }
    } finally {
      client.close();
    }
  }

  static String _apiError(int status, String body) {
    if (status == 401) return 'Der KI-Schlüssel des Servers ist ungültig.';
    if (status == 429 || status == 503) return 'Die KI ist gerade ausgelastet. Bitte gleich noch einmal.';
    if (status >= 500) return 'Die KI ist kurz nicht erreichbar.';
    try {
      return 'KI-Fehler: ${(jsonDecode(body) as Map)['error']?['message']}';
    } catch (_) {
      return 'KI-Fehler $status';
    }
  }
}

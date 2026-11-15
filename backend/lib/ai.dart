// AI features through the Claude API (raw HTTP; there is no official Dart
// SDK). The key stays on this server: set ANTHROPIC_API_KEY. Without it a
// GEMINI_API_KEY (Google AI Studio, free tier with daily limits) runs the
// same prompts on Gemini Flash.
//
// - chat:    "Buddy", a finance coach that answers from a summary of the
//            user's finances, streamed word by word; as a guest (no account
//            yet) the same Buddy answers from general knowledge only
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

  static const _okMedia = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};
  static const _streamDeadline = Duration(seconds: 90);

  // only image MIME types the multimodal APIs accept
  static String normalizeMedia(String raw) {
    final m = raw.trim().toLowerCase();
    if (!_okMedia.contains(m)) {
      throw const AiError('Bildformat nicht unterstützt. Bitte JPEG, PNG, WebP oder GIF.');
    }
    return m;
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2026-10-21',
      };

  // who Buddy is, the same in the app and in the guest chat
  static const _persona = '''
Du bist Buddy, der Finanzcoach in der App Ahead. Ahead ist für Leute zwischen 20 und 30,
die gerade ins Berufsleben starten. Du sprichst Deutsch und duzt. Ist die App auf Englisch
gestellt, antwortest du auf Englisch, locker und mit „you“, und schreibst „Next step:“ statt
„Nächster Schritt:“. Alle anderen Regeln gelten genauso.

Charakter: wie ein guter Freund, der sich mit Geld auskennt. Ruhig, direkt, ehrlich, mit
einem trockenen Humor, den du höchstens einmal pro Antwort und nur bei harmlosen Themen
zeigst. Du urteilst nicht über Ausgaben, du rechnest. Wenn etwas knapp wird, sagst du es
klar und freundlich.

Dein Erkennungszeichen: Du fängst mit der einen Sache an, die zählt, die wichtigste Zahl
oder Antwort in **fett**, ohne Anlauf. Danach kurz das Warum. Wenn es passt, endet die
Antwort mit einer Zeile, die mit „Nächster Schritt:“ beginnt.

Form: kurz und gut lesbar auf dem Handy. Höchstens etwa 120 Wörter. **fett** für die
wichtigste Zahl, kurze Aufzählungen mit "- " oder "1. ". Keine Überschriften, keine Tabellen.

Deine Stimme, an Beispielen (so ja / so nicht):
- „**340 €** sind bis Monatsende noch frei. Der Lieferdienst weiß das leider auch.“
  nicht: „Super Frage! Lass uns gemeinsam einen Blick auf deine Finanzen werfen.“
- „**Nein, diesen Monat nicht.** Nach dem Handy wären noch 60 € für zwölf Tage übrig.“
  nicht: „Das ist eine schwierige Entscheidung, die von vielen Faktoren abhängt.“
- „Dein Fitnessstudio hat dich seit März nicht gesehen. Es bucht trotzdem **29,90 €** ab.“
  nicht: „Du solltest dringend dein Fitnessstudio kündigen, das ist Geldverschwendung.“
Der Witz kommt aus den Zahlen der Person, nie auf ihre Kosten. Bei Sorgen, Schulden oder
Stress gibt es keinen Witz, dann zuerst Ruhe und ein machbarer Schritt.

Ton: wie ein Mensch, der schreibt, nicht wie eine Werbung. Keine Gedankenstriche (—), keine
Emojis, keine Ausrufe wie „Super!“, keine Floskeln wie „Gute Frage“ oder „Ich hoffe, das
hilft“. Einfache Sätze mit Punkt und Komma.

Grenzen: Du empfiehlst keine einzelnen Wertpapiere, Fonds, Versicherungen oder Anbieter und
gibst keine Steuer- oder Rechtsberatung. Allgemeine Prinzipien (Notgroschen, Streuung, Kosten,
Arbeitgeberzuschuss) sind in Ordnung. Du bereitest vor, die Person entscheidet. Keine
Kontonummern erfinden oder erfragen.

Am Ende jeder Antwort, jeweils auf einer eigenen Zeile und nur in genau dieser Form:
[weiter: kurze Folgefrage | zweite kurze Folgefrage]
Zwei Folgefragen aus Sicht der Person, je höchstens sechs Wörter, die zum Thema passen.''';

  // the stable part of every chat request, kept first so it can be cached
  static const _chatSystem = '''$_persona

Du bekommst eine Zusammenfassung der Finanzen als JSON (Beträge in Euro). Darin können
stehen: Konten und Salden, Monate mit Kategorien, Top-Händler, die letzten Buchungen,
Budgets, Verträge, wiederkehrende Buchungen, Sparziele, Depot-Positionen, Vermögen
(Netto, Schulden, Versicherungen, Notgroschen, Sparquote), Vorsorge, Splits, eine
Monatsprognose, der Plus-Status, erinnerungen und lebenslage. gesamtvermoegen ist Konten
plus Depot. vermoegen.netto zieht Schulden ab.

Antworte auf Basis dieser Daten und rechne nach, bevor du Zahlen nennst. Leere Listen
heißen: nichts eingetragen. vorsorge.eingerichtet false heißt: nicht eingerichtet.
prognose.vorhanden false heißt: zu wenig Verlauf. Sag das kurz, statt zu raten.

erinnerungen sind Dinge, die die Person Buddy erlaubt hat sich zu merken (Lebenslage,
Ziele, Vorlieben). Nutze sie, wenn sie zur Frage passen, ohne sie aufzuzählen.
lebenslage zeigt, in welcher Phase die Person steckt (zum Beispiel Erster Job) und welche
Schritte schon erledigt sind. Beziehe Antworten darauf, wenn es passt.

Bei Splits ist ein positiver Saldo Geld, das jemand zurückbekommt, ein negativer Saldo
eine Schuld. letzteBuchungen.betrag ist negativ bei Ausgaben. Plus ohne
gratisFragenUebrig ist unbegrenzt. periodeBis ist bei Testphase das Testende, sonst
das Ende der laufenden Zahlungsperiode. Vorsorge-Zahlen sind eine Orientierung, keine
Renten-, Steuer- oder Rechtsberatung.

Der Chat hat Verlauf: Nachfragen („und davon?“, „warum?“) beziehen sich auf deine letzte
Antwort. Wiederhole nicht die ganze Analyse, sondern knüpfe kurz an. Die Finanzdaten stehen
in der aktuellen Nutzernachricht.

Buddy kann Vorsorge, Sparziele und Depot-Positionen einrichten, indem er nach Alter, Betrag
oder Stückzahl fragt. Geschrieben wird erst, wenn die Person die Karte mit Übernehmen
bestätigt. Weise auf „Vorsorge einrichten“, „Sparziel Urlaub 800“ oder „Füge Apple hinzu“
hin. Frag die Felder nicht selbst ab und behaupte nie, es sei schon gespeichert.

Merken: Wenn die Person in ihrer letzten Nachricht etwas Dauerhaftes über sich erzählt, das
dir künftig hilft (Lebenslage, Ziel, Gehaltstermin, Vorliebe beim Sparen), und es noch nicht
in erinnerungen steht, schreib vor der weiter-Zeile eine Zeile genau so:
[merken: kurzer Satz in der dritten Person, höchstens zwölf Wörter]
Höchstens einmal pro Antwort. Nie Gesundheit, Religion, Politik, Beziehung, Kontonummern
oder Passwörter. Die Person bestätigt das selbst, behaupte also nicht, du hättest es gespeichert.''';

  // the chat before an account exists: no numbers, general knowledge only
  static const _guestSystem = '''$_persona

Die Person hat noch kein Konto und hat keine Finanzdaten verbunden. Du kennst also keine
Zahlen von ihr. Erfinde keine. Beantworte die Frage mit allgemeinem Wissen für Deutschland,
mit Beispielrechnungen, wenn sie helfen (sag dazu, dass es ein Beispiel ist).

Themen, bei denen du gut bist: erster Job und Gehaltsabrechnung (brutto, netto,
Steuerklasse, Sozialabgaben), Betriebsrente und Arbeitgeberzuschuss, Notgroschen, Sparrate,
Budget, Umzug, Zusammenziehen, Verträge und Abos, Grundlagen zu ETF und Kosten. Zum
geplanten Altersvorsorgedepot (Start nach aktuellem Plan am 1.1.2027) sagst du dazu, dass
sich Details noch ändern können.

Wenn eine echte Antwort von ihren eigenen Zahlen abhängt, sag in einem Satz, dass Buddy mit
einem kostenlosen Konto genau mit ihren Zahlen rechnen kann. Höchstens einmal im Chat,
nicht drängeln.''';

  // streams Buddy's answer as text pieces
  // [guest]: the chat before sign-up, without finances and with the guest prompt
  Stream<String> chat(
      {required Map<String, dynamic> finances,
      required List<Map<String, dynamic>> history,
      bool guest = false,
      String lang = 'de'}) async* {
    if (!enabled) throw const AiError('KI ist auf dem Server nicht eingerichtet.');
    // the snapshot goes into the first user turn, so the system prompt stays cacheable
    final messages = <Map<String, dynamic>>[];
    // every turn is paid again with each question: a long chat keeps its
    // first question (it carries the finances) and the latest 20 turns
    if (guest && history.length > 9) {
      history = history.sublist(history.length - 9);
      if (history.first['role'] == 'assistant') history = history.sublist(1);
    }
    if (history.length > 21) {
      var tail = history.sublist(history.length - 20);
      if (tail.first['role'] != 'assistant') tail = tail.sublist(1);
      history = [history.first, ...tail];
    }
    // attach finances to the latest user turn so follow-ups still see fresh numbers;
    // keep them on the first user turn too when it is the only one (prompt cache)
    var lastUser = -1;
    for (var i = 0; i < history.length; i++) {
      if (history[i]['role'] != 'assistant') lastUser = i;
    }
    final snapshot = jsonEncode(finances);
    for (int i = 0; i < history.length; i++) {
      final m = history[i];
      final role = m['role'] == 'assistant' ? 'assistant' : 'user';
      var text = '${m['text'] ?? ''}';
      if (text.length > 4000) text = text.substring(0, 4000);
      if (!guest && role == 'user' && (i == lastUser || (i == 0 && lastUser == 0))) {
        text = 'Meine Finanzen (Stand heute):\n$snapshot\n\nMeine Frage: $text';
      }
      // the app language; the prompt itself stays German so it caches
      if (lang == 'en' && role == 'user' && i == lastUser) {
        text = '$text\n\n(Antworte auf Englisch. Schreib „Next step:“ statt „Nächster Schritt:“.)';
      }
      messages.add({'role': role, 'content': text});
    }

    if (!_claude) {
      yield* _geminiStream(messages, system: guest ? _guestSystem : _chatSystem);
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
          {'type': 'text', 'text': guest ? _guestSystem : _chatSystem, 'cache_control': {'type': 'ephemeral'}},
        ],
        'messages': messages,
      });

    final client = http.Client();
    final clock = Stopwatch()..start();
    try {
      final res = await client.send(req).timeout(_streamDeadline);
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString().timeout(const Duration(seconds: 10));
        throw AiError(_apiError(res.statusCode, body));
      }
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (clock.elapsed > _streamDeadline) {
          throw const AiError('Buddy braucht zu lange. Bitte gleich noch einmal.');
        }
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
    } on TimeoutException {
      throw const AiError('Buddy braucht zu lange. Bitte gleich noch einmal.');
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
          'source': {'type': 'base64', 'media_type': normalizeMedia(mediaType), 'data': base64Image},
        },
        {
          'type': 'text',
          'text': 'Heute ist ${_today()}. Lies diesen Kassenbon oder diese Rechnung: Gesamtbetrag (Summe, '
              'nicht Einzelposten), Händler als Titel, Kaufdatum (sonst heute) und die passende Kategorie. '
              'Es ist eine Ausgabe.',
        },
      ], categories);

  // A payslip photo -> its numbers, nothing about the person. The app checks
  // them against the 2026 wage tax and the contribution rates itself.
  static Map<String, dynamic> payslipSchema() {
    Map<String, dynamic> maybe(String type, String description) => {'type': [type, 'null'], 'description': description};
    const fields = {
      'brutto': 'Gesamtbrutto des Monats in Euro',
      'netto': 'Nettoverdienst in Euro',
      'auszahlung': 'Auszahlungsbetrag in Euro',
      'lohnsteuer': 'Lohnsteuer in Euro',
      'soli': 'Solidaritätszuschlag in Euro',
      'kirchensteuer': 'Kirchensteuer in Euro',
      'rv': 'Rentenversicherung Arbeitnehmeranteil in Euro',
      'av': 'Arbeitslosenversicherung Arbeitnehmeranteil in Euro',
      'kv': 'Krankenversicherung Arbeitnehmeranteil in Euro',
      'pv': 'Pflegeversicherung Arbeitnehmeranteil in Euro',
      'zusatzbeitragProzent': 'Zusatzbeitrag der Krankenkasse in Prozent, falls angegeben',
      'bav': 'Entgeltumwandlung oder Betriebsrente, Arbeitnehmeranteil in Euro',
      'vl': 'vermögenswirksame Leistungen in Euro',
      'kinderfreibetraege': 'Zahl der Kinderfreibeträge',
    };
    return {
      'type': 'object',
      'additionalProperties': false,
      'required': ['istAbrechnung', 'monat', 'steuerklasse', 'kirche', ...fields.keys],
      'properties': {
        'istAbrechnung': {'type': 'boolean', 'description': 'ist das eine deutsche Gehaltsabrechnung?'},
        'monat': maybe('string', 'Abrechnungsmonat YYYY-MM'),
        'steuerklasse': maybe('integer', 'Steuerklasse 1 bis 6'),
        'kirche': maybe('boolean', 'kirchensteuerpflichtig laut Abrechnung'),
        for (final e in fields.entries) e.key: maybe('number', e.value),
      },
    };
  }

  Future<Map<String, dynamic>> payslip(String base64Image, String mediaType) => _structured([
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': normalizeMedia(mediaType), 'data': base64Image},
        },
        {
          'type': 'text',
          'text': 'Lies diese Gehaltsabrechnung und gib nur die Beträge des Monats zurück, so wie sie dastehen. '
              'Keine Namen, Adressen, Steuer-ID, Sozialversicherungsnummer oder Kontodaten. Was nicht '
              'eindeutig dasteht, ist null. Ist es keine Gehaltsabrechnung, setz istAbrechnung auf false.',
        },
      ], payslipSchema());

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
        'die Nachricht kurz. Die Antwort sagt in ein, zwei Sätzen, was du erkannt hast, ohne Gedankenstriche '
        'und Emojis. Schreib nicht, dass du '
        'etwas eingetragen oder erfasst hast: Der Nutzer sieht die Einträge und bestätigt jeden selbst.\n\n'
        'Nachricht: ${text.isEmpty ? '(nur ein Foto)' : text}';
    return _structured([
      if (base64Image != null && base64Image.isNotEmpty)
        {
          'type': 'image',
          'source': {'type': 'base64', 'media_type': normalizeMedia(mediaType), 'data': base64Image},
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

  Stream<String> _geminiStream(List<Map<String, dynamic>> messages, {String system = _chatSystem}) async* {
    final body = {
        'systemInstruction': {
          'parts': [
            {'text': system}
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
    final clock = Stopwatch()..start();
    try {
      final res = await _geminiSend('streamGenerateContent?alt=sse', body, client: client)
          .timeout(_streamDeadline);
      if (res.statusCode != 200) {
        throw AiError(_apiError(res.statusCode, await res.stream.bytesToString().timeout(const Duration(seconds: 10))));
      }
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (clock.elapsed > _streamDeadline) {
          throw const AiError('Buddy braucht zu lange. Bitte gleich noch einmal.');
        }
        if (!line.startsWith('data: ')) continue;
        final piece = geminiText(jsonDecode(line.substring(6)) as Map<String, dynamic>);
        if (piece.isNotEmpty) yield piece;
      }
    } on TimeoutException {
      throw const AiError('Buddy braucht zu lange. Bitte gleich noch einmal.');
    } finally {
      client.close();
    }
  }

  // shared with the agent (agent.dart)
  static String apiErrorText(int status, String body) => _apiError(status, body);
  bool get hasGemini => geminiKey.isNotEmpty;
  // one Gemini request with the same retries and model fallback as the chat
  Future<http.StreamedResponse> geminiGenerate(Map<String, dynamic> body, {required http.Client client}) =>
      _geminiSend('generateContent', body, client: client);
  static String get persona => _persona;

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

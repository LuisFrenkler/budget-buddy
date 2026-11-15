// Buddy before sign-up. The first message has to be useful without an
// account and without a bank link: a few real AI answers per device and day
// (general knowledge, nothing about the person's money), then the offline
// answers for life stages and money words.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'backend_service.dart';
import 'glossary.dart';
import 'life_stages.dart';
import '../l10n/l10n.dart';
import 'local_buddy.dart';

class GuestBuddy {
  static const perDay = 3;
  // a random id for the guest quota; not personal, stays on the device
  static const deviceKey = 'deviceId';
  static const usedKey = 'guestUsed';

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static String get deviceId {
    final box = _box;
    final have = box?.get(deviceKey) as String?;
    if (have != null && have.length >= 16) return have;
    final r = math.Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final id = List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
    box?.put(deviceKey, id);
    return id;
  }

  static String _today(DateTime now) => now.toIso8601String().substring(0, 10);

  // what this device used today (the server counts too; this keeps the UI honest offline)
  static int left({DateTime? now}) {
    final raw = _box?.get(usedKey);
    final day = _today(now ?? DateTime.now());
    if (raw is Map && raw['day'] == day) return math.max(0, perDay - ((raw['n'] as int?) ?? 0));
    return perDay;
  }

  static Future<void> _setLeft(int left, {DateTime? now}) async =>
      _box?.put(usedKey, {'day': _today(now ?? DateTime.now()), 'n': perDay - left.clamp(0, perDay)});

  static bool? _live;
  static http.Client? _liveClient;
  static int _askGen = 0;

  static void cancelAsk() {
    _askGen++;
    final c = _liveClient;
    _liveClient = null;
    try {
      c?.close();
    } catch (_) {}
  }

  static Future<bool> live() async {
    if (_live != null) return _live!;
    try {
      final res = await http.get(Uri.parse('${BackendService.base}/health')).timeout(const Duration(seconds: 4));
      _live = res.statusCode == 200 && (jsonDecode(res.body) as Map)['guest'] == true;
    } catch (_) {
      return false; // ask again next time
    }
    return _live!;
  }

  // the answer, piece by piece; throws a readable message when it fails
  static Stream<String> ask(List<({bool fromUser, String text})> history) async* {
    final gen = ++_askGen;
    final req = http.Request('POST', Uri.parse('${BackendService.base}/ai/guest'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'device': deviceId,
        'lang': L10n.lang.value,
        'history': [
          for (final m in history.length > 9 ? history.sublist(history.length - 9) : history)
            {'role': m.fromUser ? 'user' : 'assistant', 'text': m.text}
        ],
      });
    final conn = http.Client();
    _liveClient = conn;
    try {
      final res = await conn.send(req).timeout(const Duration(seconds: 30));
      if (gen != _askGen) return;
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        if (res.statusCode == 429) await _setLeft(0);
        String msg;
        try {
          msg = '${(jsonDecode(body) as Map)['error']}';
        } catch (_) {
          msg = tr('Buddy ist gerade nicht erreichbar.');
        }
        throw msg;
      }
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (gen != _askGen) return;
        if (!line.startsWith('data: ')) continue;
        final event = jsonDecode(line.substring(6)) as Map<String, dynamic>;
        if (event['left'] is int) await _setLeft(event['left'] as int);
        if (event['t'] != null) yield event['t'] as String;
        if (event['error'] != null) throw '${event['error']}';
      }
    } finally {
      if (identical(_liveClient, conn)) _liveClient = null;
      conn.close();
    }
  }

  // without the AI: life stage steps and money words, otherwise an honest note
  static String offline(String question) {
    final net = LocalBuddy.netAnswer(question.toLowerCase());
    if (net != null) return net;
    final q = question.toLowerCase();
    // "What is a tax class?" asks for the word, not for the payslip step
    final term = _term(q);
    final asksWord = RegExp(r'^(was (ist|sind|bedeutet|heißt|heisst)|erklär|what( i|\x27)s|what are|what does|explain|define)\b')
        .hasMatch(q.trim());
    if (asksWord && term != null) return _termAnswer(term);
    final step = LifeStages.stepFor(question);
    if (step != null) return step.offline;
    if (term != null) return _termAnswer(term);
    return tr('Die KI ist ohne Konto gerade nicht da. Offline gehen Erster Job, Umzug, Zusammenziehen und Begriffe wie ETF oder Steuerklasse.\n\nNächster Schritt: Mit einem kostenlosen Konto rechne ich mit deinen Zahlen.');
  }

  static GlossaryTerm? _term(String q) {
    for (final t in Glossary.terms) {
      final words = t.words.map((w) => w.toLowerCase());
      if (words.any((w) => RegExp('(^|[^a-zäöüß])${RegExp.escape(w)}([^a-zäöüß]|\$)').hasMatch(q))) return t;
    }
    return null;
  }

  static String _termAnswer(GlossaryTerm t) => tr(
      '**{x}**: {y}\n\nNächster Schritt: Mit einem kostenlosen Konto rechne ich das mit deinen eigenen Zahlen durch.',
      {'x': t.term, 'y': t.text});
}

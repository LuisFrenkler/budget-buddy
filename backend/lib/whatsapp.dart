// WhatsApp Cloud API (Meta). The phone number is never stored: only an
// HMAC of the E.164 digits, keyed with WHATSAPP_TOKEN. Nothing is sent
// unless that user opted in. Without the three env vars every call no-ops.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'accounts.dart';
import 'json_store.dart';
import 'net.dart';
import 'rate_limit.dart';

typedef WaSender = Future<int> Function(Uri uri, Map<String, String> headers, String body);

class WhatsApp {
  final String token;
  final String phoneId;
  final String verifyToken;
  final File store;
  final WaSender? sender;

  final _links = <String, Map<String, dynamic>>{}; // userId -> {hash, optIn, at}
  // static Hilfe reply only; key is the hash, so the number is not kept
  final _echoLimit = RateLimit(3, const Duration(hours: 1));

  WhatsApp({
    required this.token,
    required this.phoneId,
    required this.verifyToken,
    required this.store,
    this.sender,
  });

  bool get configured => token.isNotEmpty && phoneId.isNotEmpty && verifyToken.isNotEmpty;

  static const helpReply =
      'BudgetBuddy: Freigabe ist aktiv. Du bekommst nur Wochenbericht, Budget-Warnung oder Split-Erinnerung. Kein Spam. Abmelden: schreib Stop, oder schalte es in der App unter Mitteilungen aus.';

  static const stopReply =
      'BudgetBuddy: WhatsApp ist aus. Es kommen keine weiteren Nachrichten. Einschalten kannst du es wieder in der App unter Mitteilungen.';

  static const linkInstructions =
      'Deine Freigabe ist gespeichert. Die Nummer liegt nur als Hash auf dem Server, nicht im Klartext. '
      'Schreib in WhatsApp „Hilfe“ an die BudgetBuddy-Nummer aus der Meta Business Suite — du bekommst eine kurze Bestätigung, sonst nichts. '
      'Solange der Schalter an ist, sind nur diese Nachrichten möglich: Wochenbericht, Budget-Warnung, Split-Erinnerung. '
      'Kein Spam, keine Werbung. Abmelden: Schalter aus, oder in WhatsApp „Stop“ schreiben.';

  Future<void> load() async {
    if (!await store.exists()) return;
    try {
      final map = jsonDecode(await store.readAsString());
      if (map is! Map) return;
      map.forEach((k, v) {
        if (k is String && v is Map) _links[k] = v.cast<String, dynamic>();
      });
    } catch (_) {
      stderr.writeln('whatsapp store unreadable, starting empty');
    }
  }

  bool optedIn(String userId) => _links[userId]?['optIn'] == true;

  // Meta's hub.challenge, or null when the verify token does not match
  String? verify(String? mode, String? given, String? challenge) {
    if (!configured || mode != 'subscribe' || challenge == null) return null;
    if (challenge.isEmpty || challenge.length > 128 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(challenge)) {
      return null;
    }
    if (!_same(given ?? '', verifyToken)) return null;
    return challenge;
  }

  Future<void> link(String userId, String phone) async {
    if (!configured) throw const AuthError(503, 'WhatsApp ist auf diesem Server noch nicht eingerichtet.');
    final raw = phone.trim();
    if (!raw.startsWith('+')) {
      throw const AuthError(400, 'Bitte die Nummer im internationalen Format angeben, z. B. +491701234567.');
    }
    final d = digits(raw);
    if (d == null) {
      throw const AuthError(400, 'Bitte die Nummer im internationalen Format angeben, z. B. +491701234567.');
    }
    _links[userId] = {'hash': _hash(d), 'optIn': true, 'at': DateTime.now().toUtc().toIso8601String()};
    await _save();
  }

  Future<void> unlink(String userId) async {
    if (_links.remove(userId) != null) await _save();
  }

  // Logs inbound texts. Echoes „Hilfe“ only for an opted-in number, at most
  // three times an hour. „Stop“ removes the opt-in. Status callbacks are ignored.
  // shortcut: POST is not signed with the Meta app secret. A forged webhook
  // can trigger the static Hilfe reply. Verify X-Hub-Signature-256 before
  // any template send or a wider rollout.
  Future<void> receive(Map<String, dynamic> body) async {
    final texts = _texts(body);
    if (texts.isEmpty) return;
    var echoed = 0;
    for (final m in texts) {
      final d = digits(m.$1);
      if (!configured || d == null) continue;
      if (_isStop(m.$2)) {
        if (await _drop(d) && await _sendText(d, stopReply)) echoed++;
        continue;
      }
      if (!_isHilfe(m.$2) || !_known(d)) continue;
      final key = _hash(d);
      if (_echoLimit.blocked(key)) continue;
      _echoLimit.hit(key);
      if (await _sendText(d, helpReply)) echoed++;
    }
    stdout.writeln('whatsapp in texts=${texts.length} echoed=$echoed');
  }

  // Template weekly_summary (de). No-ops without credentials or opt-in.
  // shortcut: does not POST. Meta must approve the template first; the
  // caller passes the number because we only keep the hash.
  Future<bool> sendWeeklySummary({required String userId, required String phone}) async {
    if (!configured) return false;
    final d = digits(phone);
    if (d == null || !_owns(userId, d)) return false;
    return false;
  }

  // E.164 digits, no plus. Null when it is not 8–15 digits or starts with 0.
  static String? digits(String raw) {
    final d = raw.trim().replaceAll(RegExp(r'\D'), '');
    if (d.length < 8 || d.length > 15 || d.startsWith('0')) return null;
    return d;
  }

  String _hash(String d) => Hmac(sha256, utf8.encode(token)).convert(utf8.encode(d)).toString();

  bool _owns(String userId, String d) {
    final link = _links[userId];
    return link != null && link['optIn'] == true && link['hash'] == _hash(d);
  }

  bool _known(String d) {
    final h = _hash(d);
    for (final link in _links.values) {
      if (link['optIn'] == true && link['hash'] == h) return true;
    }
    return false;
  }

  static bool _isHilfe(String text) {
    final t = text.trim().toLowerCase();
    return t == 'hilfe' || t == 'hilfe!' || t == 'hilfe?';
  }

  static bool _isStop(String text) {
    final t = text.trim().toLowerCase();
    return t == 'stop' || t == 'stopp' || t == 'abbestellen';
  }

  Future<bool> _drop(String d) async {
    final h = _hash(d);
    final before = _links.length;
    _links.removeWhere((_, link) => link['hash'] == h);
    if (_links.length == before) return false;
    await _save();
    return true;
  }

  // (from, text) for text messages only
  List<(String, String)> _texts(Map<String, dynamic> body) {
    final out = <(String, String)>[];
    final entries = body['entry'];
    if (entries is! List) return out;
    for (final entry in entries) {
      if (entry is! Map) continue;
      final changes = entry['changes'];
      if (changes is! List) continue;
      for (final change in changes) {
        if (change is! Map) continue;
        final value = change['value'];
        if (value is! Map) continue;
        final messages = value['messages'];
        if (messages is! List) continue;
        for (final message in messages) {
          if (message is! Map || message['type'] != 'text') continue;
          final text = message['text'];
          if (text is! Map) continue;
          out.add(('${message['from'] ?? ''}', '${text['body'] ?? ''}'));
        }
      }
    }
    return out;
  }

  Future<bool> _sendText(String to, String reply) async {
    final payload = jsonEncode({
      'messaging_product': 'whatsapp',
      'to': to,
      'type': 'text',
      'text': {'preview_url': false, 'body': reply},
    });
    final uri = Uri.parse('https://graph.facebook.com/v21.0/$phoneId/messages');
    final headers = {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'};
    try {
      final status = sender != null
          ? await sender!(uri, headers, payload)
          : (await net.post(uri, headers: headers, body: payload)).statusCode;
      if (status < 200 || status >= 300) {
        stderr.writeln('whatsapp echo failed status=$status');
        return false;
      }
      return true;
    } catch (_) {
      stderr.writeln('whatsapp echo failed');
      return false;
    }
  }

  Future<void> _save() => writeJsonAtomic(store, _links);

  static bool _same(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

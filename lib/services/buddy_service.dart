// Buddy, the AI finance coach. Uses Claude through the BudgetBuddy server
// when the user is signed in and the server has AI configured; otherwise the
// offline answers of LocalBuddy and the offline QuickParser.
import 'money_accounts.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../utils/theme.dart';
import 'account_service.dart';
import 'backend_service.dart';
import 'db.dart';
import 'finance_snapshot.dart';
import 'local_buddy.dart';
import 'quick_parser.dart';

class ChatMessage {
  final bool fromUser;
  final String text;
  const ChatMessage(this.fromUser, this.text);
}

class BuddyService {
  static bool? _serverAi;
  // who answers on the server: 'anthropic', or 'google' (Gemini, free tier)
  static String provider = 'anthropic';

  // true when answers come from Claude, false for offline answers
  static Future<bool> live() async {
    if (AccountService.current.value == null) return false;
    if (_serverAi != null) return _serverAi!;
    try {
      final res = await http.get(Uri.parse('${BackendService.base}/health')).timeout(const Duration(seconds: 4));
      final health = jsonDecode(res.body) as Map;
      _serverAi = res.statusCode == 200 && health['ai'] == true;
      provider = '${health['aiProvider'] ?? 'anthropic'}';
    } catch (_) {
      return false; // offline now; ask again next time
    }
    return _serverAi!;
  }

  static FinanceSnapshot snapshot() => FinanceSnapshot.build(
        tx: DB.getTx(),
        openingCents: MoneyAccounts.openingTotal,
        budgets: DB.getBudgets(),
        holdings: DB.getHoldings(),
      );

  // Buddy's answer to the last user message, piece by piece
  static Stream<String> ask(List<ChatMessage> history, {required bool live}) async* {
    if (!live) {
      // offline: the answer is ready at once; hand it out in small pieces so
      // it reads like the live one
      final text = LocalBuddy.answer(history.last.text, snapshot());
      for (final word in RegExp(r'\S+\s*').allMatches(text)) {
        await Future.delayed(const Duration(milliseconds: 18));
        yield word.group(0)!;
      }
      return;
    }

    final req = http.Request('POST', Uri.parse('${BackendService.base}/ai/chat'))
      ..headers.addAll({'Content-Type': 'application/json', ...BackendService.authHeaders})
      ..body = jsonEncode({
        'finances': snapshot().toJson(),
        'history': [
          for (final m in history) {'role': m.fromUser ? 'user' : 'assistant', 'text': m.text}
        ],
      });
    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw _error(body, res.statusCode);
      }
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final event = jsonDecode(line.substring(6)) as Map<String, dynamic>;
        if (event['t'] != null) yield event['t'] as String;
        if (event['error'] != null) throw '${event['error']}';
      }
    } finally {
      client.close();
    }
  }

  static List<String> get _categories => <String>{
        for (final c in Categories.expense) c['name']!,
        for (final c in Categories.income) c['name']!,
      }.toList();

  // a quick note -> booking; Claude when live, otherwise the offline parser
  static Future<ParsedBooking?> parse(String text) async {
    final local = QuickParser.parse(text);
    if (!await live()) return local;
    try {
      final res = await http
          .post(Uri.parse('${BackendService.base}/ai/parse'),
              headers: {'Content-Type': 'application/json', ...BackendService.authHeaders},
              body: jsonEncode({'text': text, 'categories': _categories}))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return local;
      return _booking((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['booking'] as Map) ?? local;
    } catch (_) {
      return local;
    }
  }

  // a photo of a receipt -> booking (needs the AI)
  static Future<ParsedBooking> receipt(Uint8List bytes, String mediaType) async {
    if (!await live()) {
      throw AccountService.current.value == null
          ? 'Belege scannen geht mit einem kostenlosen Konto.'
          : 'Belege scannen braucht die KI auf dem Server.';
    }
    final res = await http
        .post(Uri.parse('${BackendService.base}/ai/receipt'),
            headers: {'Content-Type': 'application/json', ...BackendService.authHeaders},
            body: jsonEncode({'image': base64Encode(bytes), 'mediaType': mediaType, 'categories': _categories}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw _error(res.body, res.statusCode);
    final booking = _booking((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['booking'] as Map);
    if (booking == null) throw 'Auf dem Bild habe ich keinen Betrag gefunden.';
    return booking;
  }

  static ParsedBooking? _booking(Map b) {
    final amount = (b['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return null;
    final date = DateTime.tryParse('${b['date']}') ?? DateTime.now();
    return ParsedBooking(
      (amount * 100).round(),
      b['isIncome'] == true,
      '${b['category'] ?? 'Sonstiges'}',
      '${b['note'] ?? ''}'.trim(),
      DateTime(date.year, date.month, date.day, 12),
    );
  }

  static String _error(String body, int status) {
    try {
      return '${(jsonDecode(body) as Map)['error']}';
    } catch (_) {
      return 'Buddy ist gerade nicht erreichbar ($status).';
    }
  }
}

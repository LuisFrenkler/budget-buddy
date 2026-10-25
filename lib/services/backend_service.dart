// Talks to the BudgetBuddy backend (backend/server.dart) which proxies
// GoCardless (bank) and Parqet (depot). The base URL can be overridden with
// --dart-define=BACKEND_URL=... ; it defaults to the local dev server.
import 'dart:convert';
import 'package:http/http.dart' as http;

class Bank {
  final String id;
  final String name;
  const Bank(this.id, this.name);
}

class BankTransaction {
  final DateTime date;
  final int amountCents; // signed: positive = income, negative = expense
  final String description;
  const BankTransaction(this.date, this.amountCents, this.description);
}

class ParqetPosition {
  final String name;
  final double shares;
  final int valueCents;
  const ParqetPosition(this.name, this.shares, this.valueCents);
}

class BackendService {
  static const base = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8090');

  static Future<bool> isUp() async {
    try {
      final res = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$base$path'));
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw body['error'] ?? 'Fehler ${res.statusCode}';
    return body;
  }

  // --- bank (GoCardless) ---

  static Future<List<Bank>> institutions({String country = 'DE'}) async {
    final body = await _get('/gc/institutions?country=$country');
    return [for (final b in (body['institutions'] as List)) Bank(b['id'], b['name'])];
  }

  static Future<({String requisitionId, String link})> createRequisition(
      String institutionId, String redirect) async {
    final res = await http.post(
      Uri.parse('$base/gc/requisition'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'institutionId': institutionId, 'redirect': redirect}),
    );
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) throw body['error'] ?? 'Fehler ${res.statusCode}';
    return (requisitionId: body['requisitionId'] as String, link: body['link'] as String);
  }

  static Future<List<BankTransaction>> transactions(String requisitionId) async {
    final body = await _get('/gc/transactions?requisitionId=$requisitionId');
    final out = <BankTransaction>[];
    for (final t in (body['transactions'] as List)) {
      final date = DateTime.tryParse('${t['date']}') ?? DateTime.now();
      out.add(BankTransaction(
        DateTime(date.year, date.month, date.day),
        (t['amountCents'] as num).toInt(),
        '${t['description'] ?? ''}',
      ));
    }
    return out;
  }

  // --- depot (Parqet) ---

  static Future<List<ParqetPosition>> parqetPortfolio({String? id}) async {
    final body = await _get('/parqet/portfolio${id != null ? '?id=$id' : ''}');
    return [
      for (final h in (body['holdings'] as List))
        ParqetPosition('${h['name']}', (h['shares'] as num).toDouble(), (h['valueCents'] as num).toInt())
    ];
  }
}

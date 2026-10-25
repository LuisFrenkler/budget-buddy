// Talks to the BudgetBuddy backend (backend/server.dart) which links real
// banks through Enable Banking (PSD2) and the depot through Parqet. The base
// URL can be overridden with --dart-define=BACKEND_URL=... ; it defaults to
// the local dev server.
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'account_service.dart';

class Bank {
  final String id;
  final String name;
  final String? logo;
  const Bank(this.id, this.name, {this.logo});
}

class BankTransaction {
  final String id;
  final DateTime date;
  final int amountCents; // signed: positive = income, negative = expense
  final String counterparty;
  final String purpose;
  const BankTransaction(this.id, this.date, this.amountCents, this.counterparty, this.purpose);
}

class BankLink {
  final String status; // pending, linked, failed or unknown
  final String? bank;
  final String? iban;
  final DateTime? validUntil;
  final String? error;
  const BankLink(this.status, {this.bank, this.iban, this.validUntil, this.error});
}

class ParqetPosition {
  final String name;
  final double shares;
  final int valueCents;
  const ParqetPosition(this.name, this.shares, this.valueCents);
}

class BackendService {
  static const base = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8090');

  // null when the server is not reachable, otherwise 'live' or 'demo'
  static Future<String?> bankMode() async {
    try {
      final res = await http.get(Uri.parse('$base/health')).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return null;
      return (jsonDecode(res.body) as Map)['bank'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> get authHeaders => _auth;

  static Map<String, String> get _auth =>
      AccountService.token == null ? {} : {'Authorization': 'Bearer ${AccountService.token}'};

  static Map<String, dynamic> _decode(http.Response res) {
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    if (res.statusCode != 200) throw body['error'] ?? 'Fehler ${res.statusCode}';
    return body;
  }

  static Future<Map<String, dynamic>> _get(String path) async =>
      _decode(await http.get(Uri.parse('$base$path'), headers: _auth).timeout(const Duration(seconds: 60)));

  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async => _decode(await http.post(
        Uri.parse('$base$path'),
        headers: {'Content-Type': 'application/json', ..._auth},
        body: jsonEncode(body),
      ));

  // --- bank ---

  static Future<List<Bank>> institutions({String country = 'DE'}) async {
    final body = await _get('/bank/institutions?country=$country');
    return [
      for (final b in (body['institutions'] as List)) Bank('${b['id']}', '${b['name']}', logo: b['logo'] as String?)
    ];
  }

  // starts the consent flow; returns the token identifying this link and the
  // page the user has to open to log in at the bank
  static Future<({String state, String link})> connect(String institutionId) async {
    final body = await _post('/bank/connect', {'institution': institutionId, 'country': 'DE'});
    return (state: body['state'] as String, link: body['link'] as String);
  }

  static Future<BankLink> status(String state) async {
    final body = await _get('/bank/status?state=$state');
    final accounts = (body['accounts'] as List?) ?? const [];
    return BankLink(
      '${body['status']}',
      bank: body['bank'] as String?,
      iban: accounts.isNotEmpty ? accounts.first['iban'] as String? : null,
      validUntil: DateTime.tryParse('${body['validUntil']}'),
      error: body['error'] as String?,
    );
  }

  static Future<({int balanceCents, List<BankTransaction> transactions})> sync(String state, {int days = 90}) async {
    final body = await _get('/bank/sync?state=$state&days=$days');
    final out = <BankTransaction>[];
    for (final t in (body['transactions'] as List)) {
      final date = DateTime.tryParse('${t['date']}');
      if (date == null) continue;
      out.add(BankTransaction(
        '${t['id']}',
        DateTime(date.year, date.month, date.day, 12),
        (t['amountCents'] as num).toInt(),
        '${t['counterparty'] ?? ''}',
        '${t['purpose'] ?? ''}',
      ));
    }
    return (balanceCents: (body['balanceCents'] as num).toInt(), transactions: out);
  }

  static Future<void> disconnect(String state) => _post('/bank/disconnect', {'state': state});

  // --- depot (Parqet) ---

  static Future<List<ParqetPosition>> parqetPortfolio({String? id}) async {
    final body = await _get('/parqet/portfolio${id != null ? '?id=$id' : ''}');
    return [
      for (final h in (body['holdings'] as List))
        ParqetPosition('${h['name']}', (h['shares'] as num).toDouble(), (h['valueCents'] as num).toInt())
    ];
  }
}

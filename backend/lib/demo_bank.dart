// A pretend bank so the whole connect-and-sync flow can be tried without any
// credentials. Its consent page is served by this server and clearly marked
// as a demo; the data is generated, never real.
//
// Transactions are generated per calendar day from a seed derived from the
// date, so syncing twice returns the same bookings and new days add new ones.
import 'dart:math' as math;

import 'bank_provider.dart';

class DemoBank implements BankProvider {
  // where the consent page of this server lives, e.g. http://localhost:8090
  final String serverUrl;
  DemoBank(this.serverUrl);

  static const _startBalance = 184250; // cents, 90 days ago

  @override
  String get mode => 'demo';

  @override
  Future<List<Map<String, dynamic>>> institutions(String country) async => [
        for (final name in const [
          'Sparkasse',
          'Volksbank Raiffeisenbank',
          'Deutsche Bank',
          'Commerzbank',
          'Postbank',
          'ING',
          'DKB',
          'comdirect',
          'Consorsbank',
          'N26',
          'C24 Bank',
          'Trade Republic',
          'Scalable Capital',
        ])
          {'id': name, 'name': name, 'logo': null}
      ];

  @override
  Future<String> startAuth({
    required String institution,
    required String country,
    required String state,
    required String redirectUrl,
  }) async =>
      '$serverUrl/bank/demo-consent?state=${Uri.encodeQueryComponent(state)}'
      '&bank=${Uri.encodeQueryComponent(institution)}';

  @override
  Future<BankSession> createSession(String code) async => BankSession(
        'demo-$code',
        const [
          BankAccount('demo-giro', iban: 'DE89370400440532013000', name: 'Girokonto'),
          // a second account, so every account showing on its own can be tried
          BankAccount('demo-tagesgeld', iban: 'DE02120300000000202051', name: 'Tagesgeld'),
        ],
        DateTime.now().add(const Duration(days: 180)),
      );

  @override
  Future<int> balance(String accountUid) async {
    final from = _today().subtract(const Duration(days: 90));
    var sum = accountUid == 'demo-tagesgeld' ? 520000 : _startBalance;
    for (final t in await transactions(accountUid, from)) {
      sum += t.amountCents;
    }
    return sum;
  }

  @override
  Future<List<BankTx>> transactions(String accountUid, DateTime from) async {
    final today = _today();
    final out = <BankTx>[];
    for (var d = DateTime(from.year, from.month, from.day); !d.isAfter(today); d = DateTime(d.year, d.month, d.day + 1)) {
      out.addAll(accountUid == 'demo-tagesgeld' ? _savingsDay(d) : _day(d));
    }
    return out;
  }

  @override
  Future<void> endSession(String sessionId) async {}

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  // the savings account: monthly interest and the standing order from the giro account
  List<BankTx> _savingsDay(DateTime d) => [
        if (d.day == 2) BankTx('demo-tg-${d.year}${d.month}-zins', d, 1250, 'Demo-Bank', 'Zinsgutschrift'),
        if (d.day == 2) BankTx('demo-tg-${d.year}${d.month}-dauer', d, 20000, 'Max Mustermann', 'Dauerauftrag Sparen'),
      ];

  // [counterparty, purpose, min euros, max euros]
  static const _everyday = [
    ['REWE Markt GmbH', 'REWE SAGT DANKE', 12, 78],
    ['Lidl Dienstleistung', 'Lidl sagt Danke', 8, 55],
    ['EDEKA', 'EDEKA Center', 10, 64],
    ['dm-drogerie markt', 'dm Filiale', 6, 32],
    ['Lieferando.de', 'Bestellung Lieferando', 14, 38],
    ['Starbucks', 'Kartenzahlung', 4, 9],
    ['Shell Deutschland', 'Tankstelle', 45, 80],
    ['Amazon EU S.a.r.l.', 'Amazon.de Bestellung', 9, 70],
    ['DB Vertrieb GmbH', 'DB Fahrkarte', 19, 89],
    ['Zalando SE', 'Zalando Bestellung', 25, 110],
    ['Apotheke am Markt', 'Kartenzahlung', 5, 28],
  ];

  List<BankTx> _day(DateTime d) {
    final out = <BankTx>[];
    String id(int i) => 'demo-${d.year}${d.month}${d.day}-$i';
    void add(int i, int cents, String party, String purpose) => out.add(BankTx(id(i), d, cents, party, purpose));

    // fixed monthly bookings
    if (d.day == 1) add(0, 312480, 'Musterfirma GmbH', 'Gehalt ${d.month}/${d.year}');
    if (d.day == 2) add(7, -20000, 'Max Mustermann', 'Dauerauftrag Sparen');
    if (d.day == 3) add(1, -89000, 'Hausverwaltung Becker', 'Miete inkl. NK');
    if (d.day == 4) add(2, -5800, 'Deutsche Bahn', 'Deutschlandticket Abo');
    if (d.day == 12) add(3, -1399, 'Netflix International B.V.', 'Netflix Abo');
    if (d.day == 15) add(4, -1099, 'Spotify AB', 'Spotify Premium');
    if (d.day == 20) add(5, -4200, 'Vodafone GmbH', 'Mobilfunk Rechnung');
    if (d.day == 28) add(6, -25000, 'Trade Republic Bank', 'Sparplan Einzahlung');

    // a few everyday card payments
    final rnd = math.Random(d.year * 10000 + d.month * 100 + d.day);
    final count = rnd.nextInt(3); // 0 to 2 per day
    for (int i = 0; i < count; i++) {
      final e = _everyday[rnd.nextInt(_everyday.length)];
      final min = e[2] as int, max = e[3] as int;
      final cents = ((min + rnd.nextDouble() * (max - min)) * 100).round();
      add(10 + i, -cents, e[0] as String, e[1] as String);
    }
    return out;
  }
}

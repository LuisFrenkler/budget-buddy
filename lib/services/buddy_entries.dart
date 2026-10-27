// What the user tells Buddy happened ("200 € aufs Tagesgeld", "10 Apple zu
// 180 € gekauft", a photo of a receipt) as entries for their accounts and
// depots. Buddy only proposes them; each is applied when the user confirms.
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/holding.dart';
import '../models/money_account.dart';
import '../models/transaction.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/transfer_sheet.dart';
import 'backend_service.dart';
import 'db.dart';
import 'depot_sync.dart';
import 'money_accounts.dart';
import 'price_service.dart';
import 'quick_parser.dart';

class BuddyEntry {
  final String type; // booking, transfer, buy, sell
  final int cents; // booking and transfer
  final bool isIncome;
  final String category;
  final String note;
  final DateTime date;
  final String? account; // where the money comes from or is booked; null = main
  final String? toAccount; // transfer only
  final String name; // buy and sell
  final String symbol;
  final double shares;
  final double price; // euros per share
  final String? depot;

  const BuddyEntry({
    required this.type,
    this.cents = 0,
    this.isIncome = false,
    this.category = 'Sonstiges',
    this.note = '',
    required this.date,
    this.account,
    this.toAccount,
    this.name = '',
    this.symbol = '',
    this.shares = 0,
    this.price = 0,
    this.depot,
  });

  // from the server's answer; unknown accounts and categories fall back
  static BuddyEntry? fromJson(Map m, {DateTime? today}) {
    final type = '${m['type']}';
    final known = {for (final a in MoneyAccounts.all) a.id};
    // 'main' stays: for a purchase it says the money came from the main account
    String? acc(Object? id) => id is String && known.contains(id) ? id : null;
    final categories = {for (final c in [...Categories.expense, ...Categories.income]) c['name']};
    final category = '${m['category'] ?? ''}';
    final entry = BuddyEntry(
      type: type,
      cents: (((m['amount'] as num?) ?? 0) * 100).round().abs(),
      isIncome: m['isIncome'] == true,
      category: categories.contains(category) ? category : 'Sonstiges',
      note: '${m['note'] ?? ''}'.trim(),
      date: DateTime.tryParse('${m['date']}') ?? today ?? DateTime.now(),
      account: acc(m['account']),
      toAccount: acc(m['toAccount']),
      name: '${m['name'] ?? ''}'.trim(),
      symbol: '${m['symbol'] ?? ''}'.trim().toUpperCase(),
      shares: ((m['shares'] as num?) ?? 0).toDouble().abs(),
      price: ((m['price'] as num?) ?? 0).toDouble().abs(),
      depot: (m['depot'] as String?)?.trim().isEmpty == true ? null : (m['depot'] as String?)?.trim(),
    );
    return entry.valid ? entry : null;
  }

  bool get valid => switch (type) {
        'booking' => cents > 0,
        'transfer' => cents > 0 && toAccount != null && (account ?? MoneyAccount.main) != toAccount,
        'buy' || 'sell' => shares > 0 && (name.isNotEmpty || symbol.isNotEmpty),
        _ => false,
      };

  String _accountName(String? id) => (MoneyAccounts.byId(id) ?? MoneyAccounts.main).name;

  // one line for the card
  String get summary => switch (type) {
        'booking' => '${isIncome ? '+' : '−'}${Money.raw(cents)} · ${note.isEmpty ? category : note} · ${_accountName(account)}',
        'transfer' => '${Money.raw(cents)} von ${_accountName(account)} nach ${_accountName(toAccount)}',
        'buy' => '${_shares()} ${name.isEmpty ? symbol : name} gekauft${price > 0 ? ' zu ${Money.raw((price * 100).round())}' : ''}'
            '${account != null ? ' · von ${_accountName(account)}' : ''}',
        _ => '${_shares()} ${name.isEmpty ? symbol : name} verkauft${price > 0 ? ' zu ${Money.raw((price * 100).round())}' : ''}',
      };

  String get title => switch (type) {
        'booking' => isIncome ? 'Einnahme' : 'Ausgabe',
        'transfer' => 'Umbuchung',
        'buy' => 'Kauf im Depot${depot != null ? ' $depot' : ''}',
        _ => 'Verkauf im Depot${depot != null ? ' $depot' : ''}',
      };

  String _shares() => shares == shares.roundToDouble() ? '${shares.round()}' : shares.toString().replaceAll('.', ',');
}

class BuddyEntries {
  static const _uuid = Uuid();

  // a message that tells of something that happened rather than asks:
  // an amount and a doing word ("gekauft", "überwiesen", "bezahlt" …)
  static bool looksLikeEvent(String text) {
    final t = text.toLowerCase();
    if (t.trim().endsWith('?')) return false;
    final amount = RegExp(r'\d').hasMatch(t);
    final verb = RegExp(r'gekauft|verkauft|überwiesen|ueberwiesen|bezahlt|gezahlt|ausgegeben|bekommen|erhalten|'
            r'eingezahlt|abgehoben|umgebucht|geschickt|eingekauft|getankt|kostete|gekostet|zurückbekommen')
        .hasMatch(t);
    return amount && verb;
  }

  static List<String> get _categories => <String>{
        for (final c in Categories.expense) c['name']!,
        for (final c in Categories.income) c['name']!,
      }.toList();

  // what the AI makes of a message or photo
  static Future<({String reply, List<BuddyEntry> entries})> read(String text,
      {Uint8List? image, String mediaType = 'image/jpeg'}) async {
    final res = await http
        .post(Uri.parse('${BackendService.base}/ai/entries'),
            headers: {'Content-Type': 'application/json', ...BackendService.authHeaders},
            body: jsonEncode({
              'text': text,
              if (image != null) 'image': base64Encode(image),
              'mediaType': mediaType,
              'categories': _categories,
              'accounts': [for (final a in MoneyAccounts.all) {'id': a.id, 'name': a.name, 'kind': a.kind}],
              'depots': {for (final h in DB.getHoldings()) if (h.depot != null && h.depot!.isNotEmpty) h.depot!}.toList(),
            }))
        .timeout(const Duration(seconds: 70));
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    if (res.statusCode != 200) throw body['error'] ?? 'Buddy konnte das gerade nicht lesen.';
    return (
      reply: '${body['reply'] ?? ''}',
      entries: [
        for (final e in (body['entries'] as List? ?? const []))
          if (e is Map)
            if (BuddyEntry.fromJson(e) case final entry?) entry,
      ],
    );
  }

  // without the AI: a simple booking the offline parser understands
  static BuddyEntry? offline(String text) {
    final b = QuickParser.parse(text);
    if (b == null) return null;
    return BuddyEntry(
        type: 'booking', cents: b.cents, isIncome: b.isIncome, category: b.category, note: b.note, date: b.date);
  }

  static Holding? _position(BuddyEntry e) {
    final key = e.symbol.isNotEmpty ? e.symbol : e.name.toLowerCase();
    for (final h in DB.getHoldings()) {
      final same = e.symbol.isNotEmpty ? h.symbol.toUpperCase() == key : h.name.toLowerCase() == key;
      if (same && (e.depot == null || h.depot == null || h.depot == e.depot)) return h;
    }
    return null;
  }

  // stores the entry; returns what was done, in a few words
  static Future<String> apply(BuddyEntry e) async {
    String? acc(String? id) => id == null || id == MoneyAccount.main ? null : id;
    switch (e.type) {
      case 'booking':
        await DB.addTx(Transaction(
            id: _uuid.v4(), amountCents: e.cents, category: e.category, date: e.date, isIncome: e.isIncome,
            note: e.note.isEmpty ? null : e.note, accountId: acc(e.account)));
        await DB.checkBadges();
        return 'Gebucht';
      case 'transfer':
        final from = MoneyAccounts.byId(e.account) ?? MoneyAccounts.main;
        final to = MoneyAccounts.byId(e.toAccount)!;
        for (final t in transferBookings(from: from, to: to, cents: e.cents, date: e.date)) {
          await DB.addTx(t);
        }
        return 'Umgebucht';
      default:
        final buy = e.type == 'buy';
        final cents = (e.shares * e.price * 100).round();
        final label = e.name.isEmpty ? e.symbol : e.name;
        final existing = _position(e);
        // a linked depot takes its positions from Parqet; editing them here would be undone
        final synced = existing != null && existing.id.startsWith(DepotSync.prefix);
        if (!synced) {
          if (buy) {
            final old = existing;
            final shares = (old?.shares ?? 0) + e.shares;
            final buyPrice = old == null || shares == 0
                ? (e.price * 100).round()
                : ((old.shares * old.buyPriceCents + e.shares * e.price * 100) / shares).round();
            await DB.addHolding(Holding(
              id: old?.id ?? _uuid.v4(),
              name: old?.name ?? label,
              symbol: old?.symbol ?? e.symbol,
              type: old?.type ?? (PriceService.isKnownCoin(e.symbol) ? 'Krypto' : 'Aktie'),
              shares: shares,
              buyPriceCents: buyPrice,
              currentPriceCents: old?.currentPriceCents ?? (e.price * 100).round(),
              priceAt: old?.priceAt,
              unitEur: old?.unitEur,
              depot: old?.depot ?? e.depot,
            ));
          } else if (existing != null) {
            final left = existing.shares - e.shares;
            if (left <= 1e-9) {
              await DB.deleteHolding(existing.id);
            } else {
              await DB.addHolding(Holding(
                id: existing.id, name: existing.name, symbol: existing.symbol, type: existing.type, shares: left,
                buyPriceCents: existing.buyPriceCents, currentPriceCents: existing.currentPriceCents,
                priceAt: existing.priceAt, unitEur: existing.unitEur, depot: existing.depot));
            }
          }
        }
        // the money for it moved between the account and the depot: no spending
        if (e.account != null && cents > 0) {
          await DB.addTx(Transaction(
              id: _uuid.v4(), amountCents: cents, category: Categories.transfer, date: e.date, isIncome: !buy,
              note: '${buy ? 'Kauf' : 'Verkauf'} $label', accountId: acc(e.account)));
        }
        if (synced) return 'Konto gebucht · das Depot kommt über Parqet';
        return buy ? 'Im Depot' : (existing == null ? 'Position nicht gefunden' : 'Aus dem Depot');
    }
  }
}

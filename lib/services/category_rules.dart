// Categories that learn: once a merchant is moved to another category, all
// its bookings follow, today and in the future (bank sync, quick entry).
import 'package:hive/hive.dart';
import '../models/transaction.dart';
import '../utils/merchant.dart';
import 'categorizer.dart';
import 'db.dart';
import '../utils/theme.dart';

class CategoryRules {
  // stable across "REWE SAGT DANKE 1234" vs "REWE Markt GmbH"
  static String _key(String name) => Merchant.key(name);

  static String _rule(String name, bool isIncome) => '${isIncome ? '+' : '-'}${_key(name)}';

  static Map<String, String> get all {
    if (!Hive.isBoxOpen('settings')) return const {};
    return Map<String, String>.from(Hive.box('settings').get('categoryRules') as Map? ?? const {});
  }

  // most recently booked category of this kind (manual entry default)
  static String? lastUsed({required bool isIncome, bool refund = false}) {
    for (final t in DB.getTx()) {
      if (t.isIncome != isIncome || t.isRefund != refund) continue;
      if (t.category == Categories.transfer) continue;
      return t.category;
    }
    return null;
  }

  // the remembered category for a merchant, if any
  static String? forName(String? name, {required bool isIncome}) {
    if (name == null || name.trim().isEmpty) return null;
    final rules = all;
    final hit = rules[_rule(name, isIncome)];
    if (hit != null) return hit;
    // older rules stored the raw lowercased title — still honour them
    final legacy = rules['${isIncome ? '+' : '-'}${name.toLowerCase().trim()}'];
    if (legacy != null) return legacy;
    // "AMZN Mktp" and "Amazon" are one merchant
    final brand = Categorizer.brand(name);
    if (brand == null) return null;
    return rules[_rule(brand, isIncome)];
  }

  static Future<void> remember(String name, String category, {required bool isIncome}) async {
    if (!Hive.isBoxOpen('settings')) return;
    final rules = {...all, _rule(name, isIncome): category};
    final brand = Categorizer.brand(name);
    if (brand != null) rules[_rule(brand, isIncome)] = category;
    await Hive.box('settings').put('categoryRules', rules);
  }

  // other bookings of the same merchant that are in a different category
  static List<Transaction> others(Transaction tx, String category) {
    final name = tx.note?.trim() ?? '';
    if (name.isEmpty) return const [];
    final key = _key(name);
    return DB.getTx()
        .where((t) =>
            t.id != tx.id &&
            t.isIncome == tx.isIncome &&
            _key(t.note ?? '') == key &&
            t.category != category)
        .toList();
  }

  // moves every booking of the merchant and remembers it for new ones
  static Future<int> applyToAll(Transaction tx, String category) async {
    final list = others(tx, category);
    for (final t in list) {
      await DB.addTx(t.withCategory(category));
    }
    await remember(tx.note!, category, isIncome: tx.isIncome);
    return list.length;
  }

  // after smarter keyword rules: lift old "Sonstiges" when we now know better
  // (never overrides a category the user explicitly remembered)
  static Future<int> upgradeSonstiges() async {
    if (!Hive.isBoxOpen('settings')) return 0;
    var n = 0;
    for (final t in DB.getTx()) {
      if (t.category != 'Sonstiges') continue;
      final note = t.note?.trim() ?? '';
      if (note.isEmpty) continue;
      final remembered = forName(note, isIncome: t.isIncome);
      // a saved "Sonstiges" stays; guessing would undo the user's choice every start
      if (remembered == 'Sonstiges') continue;
      if (remembered != null) {
        await DB.addTx(t.withCategory(remembered));
        n++;
        continue;
      }
      final guessed = Categorizer.guess(note, isIncome: t.isIncome);
      if (guessed == 'Sonstiges') continue;
      await DB.addTx(t.withCategory(guessed));
      n++;
    }
    return n;
  }
}

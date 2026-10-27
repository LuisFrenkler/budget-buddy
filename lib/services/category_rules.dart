// Categories that learn: once a merchant is moved to another category, all
// its bookings follow, today and in the future (bank sync, quick entry).
import 'package:hive/hive.dart';
import '../models/transaction.dart';
import 'db.dart';

class CategoryRules {
  static String _key(String name) => name.toLowerCase().trim();

  // rules for income and expenses are kept apart
  static String _rule(String name, bool isIncome) => '${isIncome ? '+' : '-'}${_key(name)}';

  static Map<String, String> get all {
    if (!Hive.isBoxOpen('settings')) return const {};
    return Map<String, String>.from(Hive.box('settings').get('categoryRules') as Map? ?? const {});
  }

  // the remembered category for a merchant, if any
  static String? forName(String? name, {required bool isIncome}) {
    if (name == null || name.trim().isEmpty) return null;
    return all[_rule(name, isIncome)];
  }

  static Future<void> remember(String name, String category, {required bool isIncome}) async {
    final rules = {...all, _rule(name, isIncome): category};
    await Hive.box('settings').put('categoryRules', rules);
  }

  // other bookings of the same merchant that are in a different category
  static List<Transaction> others(Transaction tx, String category) {
    final name = tx.note?.trim() ?? '';
    if (name.isEmpty) return const [];
    return DB.getTx()
        .where((t) =>
            t.id != tx.id &&
            t.isIncome == tx.isIncome &&
            _key(t.note ?? '') == _key(name) &&
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
}

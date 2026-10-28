// Turns "Sonstiges" piles into proposed category moves. Buddy shows them as
// confirm cards; nothing is stored until the user taps Übernehmen.
import 'package:hive/hive.dart';
import '../models/transaction.dart';
import '../utils/merchant.dart';
import 'categorizer.dart';
import 'category_rules.dart';
import 'db.dart';

class CategoryProposal {
  final String sample; // a real note, for display and CategoryRules keying
  final String category;
  final int count;
  final int cents;
  final bool isIncome;

  const CategoryProposal({
    required this.sample,
    required this.category,
    required this.count,
    required this.cents,
    required this.isIncome,
  });
}

class CategoryGroup {
  final String sample;
  final int count;
  final int cents;
  final bool isIncome;
  const CategoryGroup({
    required this.sample,
    required this.count,
    required this.cents,
    required this.isIncome,
  });
}

class CategoryCoach {
  // Sonstiges bookings grouped by merchant, biggest spend first
  static List<CategoryGroup> groups({bool spendingOnly = true, int limit = 20}) {
    final map = <String, ({String sample, int count, int cents, bool isIncome})>{};
    for (final t in DB.getTx()) {
      if (t.category != 'Sonstiges') continue;
      if (spendingOnly && !t.isSpending) continue;
      final note = t.note?.trim() ?? '';
      if (note.isEmpty) continue;
      final key = '${t.isIncome ? '+' : '-'}${Merchant.key(note)}';
      final prev = map[key];
      map[key] = (
        sample: prev?.sample ?? note,
        count: (prev?.count ?? 0) + 1,
        cents: (prev?.cents ?? 0) + t.amountCents,
        isIncome: t.isIncome,
      );
    }
    final list = map.values.toList()
      ..sort((a, b) => b.cents != a.cents ? b.cents.compareTo(a.cents) : b.count.compareTo(a.count));
    return [
      for (final g in list.take(limit))
        CategoryGroup(sample: g.sample, count: g.count, cents: g.cents, isIncome: g.isIncome),
    ];
  }

  // merchants we can place without asking (keyword / MCC-free guess on the note)
  static List<CategoryProposal> autoFixes({int limit = 12}) {
    final out = <CategoryProposal>[];
    for (final g in groups(limit: 40)) {
      if (CategoryRules.forName(g.sample, isIncome: g.isIncome) == 'Sonstiges') continue;
      final guessed = Categorizer.guess(g.sample, isIncome: g.isIncome);
      if (guessed == 'Sonstiges') continue;
      out.add(CategoryProposal(
        sample: g.sample,
        category: guessed,
        count: g.count,
        cents: g.cents,
        isIncome: g.isIncome,
      ));
      if (out.length >= limit) break;
    }
    return out;
  }

  // still unknown after keywords — Buddy asks the user
  static List<CategoryGroup> leftovers({int limit = 8}) {
    final fixed = {for (final p in autoFixes(limit: 40)) Merchant.key(p.sample)};
    return [
      for (final g in groups(limit: 40))
        if (!fixed.contains(Merchant.key(g.sample))) g,
    ].take(limit).toList();
  }

  static int miscCount() {
    if (!Hive.isBoxOpen('transactions')) return 0;
    return DB.getTx().where((t) => t.isSpending && t.category == 'Sonstiges').length;
  }

  // moves every Sonstiges booking of this merchant and remembers the rule
  static Future<int> apply(String sample, String category, {required bool isIncome}) async {
    final key = Merchant.key(sample);
    var n = 0;
    for (final t in DB.getTx()) {
      if (t.isIncome != isIncome) continue;
      if (t.category == category) continue;
      final note = t.note?.trim() ?? '';
      if (note.isEmpty || Merchant.key(note) != key) continue;
      await DB.addTx(t.withCategory(category));
      n++;
    }
    await CategoryRules.remember(sample, category, isIncome: isIncome);
    return n;
  }

  // "REWE → Lebensmittel" / "Starbucks ist Essen & Trinken" / bare category while pending
  static ({String? merchant, String? category}) parseAssign(String text, {String? pending}) {
    final raw = text.trim();
    if (raw.isEmpty) return (merchant: null, category: null);
    final cats = _categories;
    final lower = raw.toLowerCase();

    String? cat;
    for (final c in cats) {
      if (lower == c.toLowerCase() || lower.endsWith(' ${c.toLowerCase()}') || lower.endsWith('→ ${c.toLowerCase()}')) {
        cat = c;
        break;
      }
    }
    if (cat == null) {
      for (final c in cats) {
        if (lower.contains(c.toLowerCase())) {
          cat = c;
          break;
        }
      }
    }
    if (cat == null) return (merchant: null, category: null);

    if (pending != null && (lower == cat.toLowerCase() || raw.length <= cat.length + 2)) {
      return (merchant: pending, category: cat);
    }

    var rest = raw;
    for (final sep in ['→', '->', ' ist ', ' = ', ':']) {
      final i = lower.indexOf(sep.toLowerCase());
      if (i > 0) {
        rest = raw.substring(0, i).trim();
        break;
      }
    }
    // "Lebensmittel für REWE" / trailing category stripped
    final cut = rest.toLowerCase().replaceAll(cat.toLowerCase(), '').trim();
    final merchant = cut.isEmpty ? pending : cut.replaceAll(RegExp(r'^(für|fuer)\s+'), '').trim();
    if (merchant == null || merchant.isEmpty) return (merchant: pending, category: cat);
    return (merchant: merchant, category: cat);
  }

  static List<String> get _categories => [
        'Lebensmittel',
        'Essen & Trinken',
        'Transport',
        'Unterhaltung',
        'Wohnen',
        'Kleidung',
        'Gesundheit',
        'Bildung',
        'Gehalt',
        'Nebenjob',
        'Investition',
        'Geschenk',
        'Umbuchung',
      ];
}

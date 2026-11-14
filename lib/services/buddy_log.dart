// Everything Buddy did for the person, with a way back. Each confirmed card
// lands here with what it changed; "Rückgängig" restores the state before.
// This is the promise Buddy makes: nothing happens behind your back, and
// nothing he did is final.
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../l10n/l10n.dart';
import '../models/budget.dart';
import 'buddy_tasks.dart';
import 'category_rules.dart';
import 'db.dart';
import 'goals_service.dart';

class BuddyLogEntry {
  final String id;
  final String kind; // budget, goal, category, reminder, cancel
  final String title;
  final String said;
  final DateTime at;
  final Map<String, dynamic> undo; // empty: nothing to take back
  final bool undone;
  const BuddyLogEntry(this.id, this.kind, this.title, this.said, this.at, this.undo, {this.undone = false});

  bool get canUndo => undo.isNotEmpty && !undone;

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind,
        'title': title,
        'said': said,
        'at': at.toIso8601String(),
        'undo': undo,
        'undone': undone,
      };

  static BuddyLogEntry? fromMap(dynamic m) {
    if (m is! Map) return null;
    final at = DateTime.tryParse('${m['at']}');
    if (at == null) return null;
    return BuddyLogEntry('${m['id']}', '${m['kind']}', '${m['title']}', '${m['said']}', at,
        Map<String, dynamic>.from((m['undo'] as Map?) ?? const {}),
        undone: m['undone'] == true);
  }
}

class BuddyLog {
  static const _key = 'buddyLog';
  static const keep = 100;
  static final changed = ValueNotifier<int>(0);
  static int _seq = 0;
  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static List<BuddyLogEntry> all() => [
        for (final m in (_box?.get(_key) as List?) ?? const [])
          if (BuddyLogEntry.fromMap(m) case final e?) e
      ]..sort((a, b) => b.at.compareTo(a.at));

  static Future<void> add(String kind, String title, String said, Map<String, dynamic> undo, {DateTime? now}) async {
    final box = _box;
    if (box == null) return;
    final at = now ?? DateTime.now();
    final entry = BuddyLogEntry('${DateTime.now().microsecondsSinceEpoch}-${_seq++}', kind, title, said, at, undo);
    await box.put(_key, [entry.toMap(), ...all().take(keep - 1).map((e) => e.toMap())]);
    changed.value++;
  }

  // takes one entry back; says in one line what happened
  static Future<String> undo(String id) async {
    final e = all().firstWhere((x) => x.id == id);
    if (!e.canUndo) return tr('Das lässt sich nicht rückgängig machen.');
    final u = e.undo;
    switch (e.kind) {
      case 'budget':
        final start = DateTime.parse('${u['start']}');
        await DB.deleteBudget(Budget(
            category: '${u['kategorie']}',
            limitCents: 0,
            startDate: start,
            endDate: DateTime(start.year, start.month + 1, 0)));
      case 'goal':
        await GoalsService.delete('${u['goalId']}');
      case 'category':
        final old = Map<String, dynamic>.from(u['old'] as Map);
        final byId = {for (final t in DB.getTx()) t.id: t};
        for (final entry in old.entries) {
          final t = byId[entry.key];
          if (t != null) await DB.addTx(t.withCategory('${entry.value}'));
        }
        // new bookings of the merchant go back where they went before
        final before = '${u['vorher'] ?? ''}';
        if (before.isNotEmpty) await CategoryRules.remember('${u['haendler']}', before, isIncome: false);
      case 'reminder':
        await BuddyTasks.remove('${u['taskId']}');
    }
    final box = _box!;
    await box.put(_key, [
      for (final x in all()) (x.id == id ? BuddyLogEntry(x.id, x.kind, x.title, x.said, x.at, x.undo, undone: true) : x).toMap()
    ]);
    changed.value++;
    return tr('Rückgängig gemacht: {x}', {'x': e.title});
  }
}

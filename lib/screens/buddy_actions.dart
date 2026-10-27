// What Buddy can do right after an answer: the next step as a button, so
// "Wo kann ich sparen?" ends in a budget, not just in a paragraph.
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/finance_snapshot.dart';
import '../services/goals_service.dart';
import '../services/local_buddy.dart';
import 'budget_screen.dart';
import 'contracts_screen.dart';
import 'goals_screen.dart';

class BuddyAction {
  final IconData icon;
  final String label;
  final void Function(BuildContext context) run;
  const BuddyAction(this.icon, this.label, this.run);
}

class BuddyActions {
  static bool _has(String q, List<String> words) => words.any(q.contains);

  static List<BuddyAction> forQuestion(String question, FinanceSnapshot s) {
    final q = question.toLowerCase();
    final contracts = BuddyAction(Icons.receipt_long_rounded, 'Verträge & Abos ansehen',
        (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ContractsScreen())));
    final taken = {for (final b in s.budgets) b.category};

    if (_has(q, ['leisten', 'urlaub', 'kaufen', 'sparziel', 'zurücklegen'])) {
      final amount = RegExp(r'(\d[\d.]*)').firstMatch(q);
      final euros = amount == null ? null : int.tryParse(amount.group(1)!.replaceAll('.', ''));
      final name = q.contains('urlaub')
          ? 'Urlaub'
          : q.contains('handy')
              ? 'Neues Handy'
              : q.contains('auto')
                  ? 'Auto'
                  : null;
      // a goal of that name exists already: go there instead of a second one
      final existing = name == null || !Hive.isBoxOpen('goals')
          ? null
          : GoalsService.all().where((g) => g.name.toLowerCase() == name.toLowerCase()).firstOrNull;
      return [
        if (existing != null)
          BuddyAction(Icons.flag_rounded, 'Zu deinem Ziel „${existing.name}“',
              (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const GoalsScreen())))
        else
          BuddyAction(Icons.flag_rounded,
              euros == null ? 'Als Sparziel anlegen' : 'Sparziel${name == null ? '' : ' „$name“'} · $euros €',
              (c) => addGoal(c, name: name, cents: euros == null ? null : euros * 100)),
      ];
    }
    if (_has(q, ['abo', 'vertr', 'fixkost'])) return s.contracts.isEmpty ? [] : [contracts];
    if (_has(q, ['spar', 'meisten', 'wofür', 'ausgaben', 'kategorie', 'budget'])) {
      // a budget for what stands out (or the biggest category) that has none yet
      final over = LocalBuddy.overUsual(s).map((e) => e.key);
      final biggest = (s.avgByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key);
      final target = [...over, ...biggest].where((c) => !taken.contains(c) && c != 'Wohnen').firstOrNull;
      return [
        if (target != null)
          BuddyAction(Icons.speed_rounded, 'Budget für $target anlegen', (c) => showAddBudgetDialog(c, category: target)),
        if (_has(q, ['spar']) && s.contracts.isNotEmpty) contracts,
      ];
    }
    return [];
  }
}

// What Buddy can do right after an answer: the next step as a button, so
// "Wo kann ich sparen?" ends in a budget, not just in a paragraph.
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/category_coach.dart';
import '../services/finance_snapshot.dart';
import '../services/goals_service.dart';
import '../services/local_buddy.dart';
import 'add_holding_screen.dart';
import 'budget_screen.dart';
import 'buddy_screen.dart';
import 'contracts_screen.dart';
import 'depot_screen.dart';
import 'goals_screen.dart';
import 'home_screen.dart';
import 'splits_screen.dart';
import 'vorsorge_screen.dart';
import 'wealth_screen.dart';
import '../widgets/misc_sort_sheet.dart';
import '../widgets/scenario_sheet.dart';
import '../l10n/l10n.dart';
import 'tax_screen.dart';

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
    final contracts = BuddyAction(Icons.receipt_long_rounded, tr('Verträge & Abos ansehen'),
        (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const ContractsScreen())));
    final taken = {for (final b in s.budgets) b.category};

    if (_has(q, ['steuererklärung', 'steuererklaerung', 'steuer zurück', 'steuern zurück', 'lohnsteuer', 'elster'])) {
      final year = RegExp(r'20\d\d').firstMatch(q)?.group(0);
      return [
        BuddyAction(Icons.savings_outlined, tr('Steuer-Seite öffnen'),
            (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => TaxScreen(year: int.tryParse(year ?? ''))))),
      ];
    }
    if (_has(q, ['vorsorge', 'rentenrechner', 'altersvorsorge', 'rentenlücke', 'rentenluecke'])) {
      return [
        BuddyAction(Icons.savings_rounded, tr('Rentenrechner öffnen'),
            (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const VorsorgeScreen()))),
      ];
    }
    if (_has(q, ['depot', 'aktie', 'aktien', 'etf', 'krypto']) &&
        _has(q, ['hinzu', 'anlegen', 'einrichten', 'wo', 'wie', 'füge', 'fuege'])) {
      return [
        BuddyAction(Icons.add_chart_rounded, tr('Position hinzufügen'),
            (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const AddHoldingScreen()))),
        BuddyAction(Icons.pie_chart_rounded, tr('Depot öffnen'),
            (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const DepotScreen()))),
      ];
    }
    if (_has(q, ['vermögen', 'vermoegen', 'schulden']) || (q.contains('notgroschen') && !q.contains('sparziel'))) {
      return [
        BuddyAction(Icons.account_balance_wallet_rounded, tr('Vermögen öffnen'),
            (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const WealthScreen()))),
      ];
    }
    if (_has(q, ['leisten', 'urlaub', 'kaufen', 'sparziel', 'zurücklegen'])) {
      final amount = RegExp(r'(\d[\d.]*)').firstMatch(q);
      final euros = amount == null ? null : int.tryParse(amount.group(1)!.replaceAll('.', ''));
      final name = q.contains('urlaub')
          ? tr('Urlaub')
          : q.contains('handy')
              ? tr('Neues Handy')
              : q.contains('auto')
                  ? tr('Auto')
                  : null;
      // a goal of that name exists already: go there instead of a second one
      final existing = name == null || !Hive.isBoxOpen('goals')
          ? null
          : GoalsService.all().where((g) => g.name.toLowerCase() == name.toLowerCase()).firstOrNull;
      return [
        if (existing != null)
          BuddyAction(Icons.flag_rounded, tr('Zu deinem Ziel „{name}“', {'name': existing.name}),
              (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const GoalsScreen())))
        else
          BuddyAction(Icons.flag_rounded,
              euros == null ? tr('Als Sparziel anlegen') : tr('Sparziel{x} · {euros} €', {'x': name == null ? '' : ' „$name“', 'euros': euros}),
              (c) => addGoal(c, name: name, cents: euros == null ? null : euros * 100)),
      ];
    }
    if (_has(q, ['abo', 'vertr', 'fixkost'])) return s.contracts.isEmpty ? [] : [contracts];
    if (_has(q, ['sonstiges', 'aufräumen', 'einordnen', 'zuordnen']) &&
        CategoryCoach.miscCount() > 0) {
      return [
        BuddyAction(Icons.auto_fix_high_rounded, tr('Sonstiges aufräumen'),
            (c) => showMiscSortSheet(c)),
      ];
    }
    if (_has(q, ['was bleibt', 'noch ausgeben', 'prognose', 'monatsende', 'noch frei', 'was wäre', 'leisten']) &&
        s.forecast != null) {
      return [
        BuddyAction(Icons.tune_rounded, tr('Was wäre wenn…?'), (c) {
          BuddyScreen.ask.value = null;
          showScenarioSheet(c);
        }),
        BuddyAction(Icons.insights_rounded, tr('Prognose auf Start'), (c) {
          BuddyScreen.ask.value = null;
          Navigator.popUntil(c, (r) => r.isFirst);
          HomeScreen.goTab.value = 0;
        }),
      ];
    }
    if (_has(q, ['split', 'schuldet', 'geteilt']) && s.splits.any((g) => g.myCents != 0)) {
      return [
        BuddyAction(Icons.group_rounded, tr('Splits öffnen'),
            (c) => Navigator.push(c, MaterialPageRoute(builder: (_) => const SplitsScreen()))),
      ];
    }
    if (_has(q, ['spar', 'meisten', 'wofür', 'ausgaben', 'kategorie', 'budget'])) {
      // a budget for what stands out (or the biggest category) that has none yet
      final over = LocalBuddy.overUsual(s).map((e) => e.key);
      final biggest = (s.avgByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key);
      final target = [...over, ...biggest].where((c) => !taken.contains(c) && c != 'Wohnen').firstOrNull;
      return [
        if (target != null)
          BuddyAction(Icons.speed_rounded, tr('Budget für {target} anlegen', {'target': target}), (c) => showAddBudgetDialog(c, category: target)),
        if (_has(q, ['spar']) && s.contracts.isNotEmpty) contracts,
      ];
    }
    return [];
  }
}

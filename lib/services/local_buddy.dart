// Buddy's answers without the AI: the common questions answered with real
// numbers computed on the device. Used offline, for guests, and whenever the
// server has no AI configured. The app labels these answers as offline.
import '../utils/money.dart';
import 'finance_snapshot.dart';

class LocalBuddy {
  static String answer(String question, FinanceSnapshot s) {
    final q = question.toLowerCase();
    if (_has(q, ['abo', 'vertr', 'fixkost'])) return _contracts(s);
    if (_has(q, ['leisten', 'urlaub', 'kaufen', 'sparziel', 'zurücklegen'])) return _afford(q, s);
    if (_has(q, ['spar'])) return _save(s);
    if (_has(q, ['budget'])) return _budgets(s);
    if (_has(q, ['depot', 'aktie', 'etf', 'invest', 'anlage'])) return _depot(s);
    if (_has(q, ['meisten', 'wofür', 'ausgegeben', 'ausgaben', 'kategorie'])) return _spending(s);
    return _overview(s);
  }

  static bool _has(String q, List<String> words) => words.any(q.contains);

  static String _eur(int cents) => Money.format(cents);

  static List<MapEntry<String, int>> _top(Map<String, int> m, int n) =>
      (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(n).toList();

  static String _spending(FinanceSnapshot s) {
    final m = s.current;
    if (m.expenses == 0) return 'Diesen Monat hast du noch keine Ausgaben erfasst.';
    final lines = [
      for (final e in _top(m.byCategory, 3)) '- ${e.key}: **${_eur(e.value)}** (${(e.value / m.expenses * 100).round()} %)'
    ];
    final merchant = s.topMerchants.isEmpty ? '' : '\n\nAm meisten Geld ging an **${s.topMerchants.first.name}** '
        '(${_eur(s.topMerchants.first.cents)}).';
    return 'Diesen Monat hast du bisher **${_eur(m.expenses)}** ausgegeben, vor allem für:\n${lines.join('\n')}$merchant';
  }

  // categories clearly above their usual level this month (at least 10 €
  // and 15 % more), biggest first; small wobbles are no saving tip
  static List<MapEntry<String, int>> overUsual(FinanceSnapshot s) {
    final avg = s.avgByCategory;
    final over = <MapEntry<String, int>>[];
    s.current.byCategory.forEach((k, v) {
      final usual = avg[k] ?? 0;
      final diff = v - usual;
      if (usual > 0 && diff >= 1000 && diff >= usual * 0.15) over.add(MapEntry(k, diff));
    });
    return over..sort((a, b) => b.value.compareTo(a.value));
  }

  static String _save(FinanceSnapshot s) {
    final avg = s.avgByCategory;
    final over = overUsual(s);

    final tips = <String>[];
    for (final e in over.take(2)) {
      tips.add('- **${e.key}**: ${_eur(e.value)} mehr als sonst in einem Monat');
    }
    final subs = s.contracts.where((c) => c.category == 'Unterhaltung').toList();
    if (subs.isNotEmpty) {
      final sum = subs.fold<int>(0, (a, c) => a + c.monthlyCents);
      tips.add('- **Abos**: ${subs.map((c) => c.name).join(', ')} kosten zusammen ${_eur(sum)} im Monat '
          '(${_eur(sum * 12)} im Jahr). Brauchst du alle?');
    }
    if (tips.isEmpty) {
      final top = _top(avg, 1);
      if (top.isEmpty) return 'Dafür brauche ich noch etwas mehr Verlauf. Erfasse ein paar Wochen deine Ausgaben.';
      tips.add('- Dein größter Posten ist **${top.first.key}** mit etwa ${_eur(top.first.value)} im Monat. '
          'Schon 10 % weniger sind ${_eur(top.first.value ~/ 10)} im Monat.');
    }
    return 'Hier steckt Sparpotenzial:\n${tips.join('\n')}\n\nTipp: Leg dir für die größte Kategorie ein Budget an, '
        'dann warnt dich die App rechtzeitig.';
  }

  static String _afford(String q, FinanceSnapshot s) {
    final surplus = s.avgIncome - s.avgExpenses;
    final match = RegExp(r'(\d[\d.]*)').firstMatch(q);
    final target = match == null ? null : int.tryParse(match.group(1)!.replaceAll('.', ''));
    if (s.past.isEmpty) return 'Dafür brauche ich mindestens einen vollen Monat an Daten.';
    if (surplus <= 0) {
      return 'Im Schnitt gibst du gerade **${_eur(-surplus)} mehr aus**, als reinkommt. Bevor du sparst, '
          'lohnt ein Blick auf deine größten Kategorien.';
    }
    final base = 'Im Schnitt bleiben dir **${_eur(surplus)} pro Monat** übrig '
        '(Einnahmen ${_eur(s.avgIncome)}, Ausgaben ${_eur(s.avgExpenses)}).';
    if (target == null || target <= 0) return '$base\n\nNenn mir einen Betrag, dann rechne ich aus, wie schnell du ihn zusammen hast.';
    final cents = target * 100;
    final months = (cents / surplus).ceil();
    final buffer = s.balanceCents - cents;
    return '$base\n\n- Für **${_eur(cents)}** brauchst du etwa **$months ${months == 1 ? 'Monat' : 'Monate'}**.\n'
        '- Aus dem Kontostand bezahlt blieben dir ${_eur(buffer)}'
        '${buffer < s.avgExpenses ? ', weniger als ein Monat Ausgaben. Lieber ansparen.' : '. Das passt.'}';
  }

  static String _contracts(FinanceSnapshot s) {
    if (s.contracts.isEmpty) return 'Ich habe noch keine festen Verträge erkannt. Dafür brauche ich drei Monate gleiche Zahlungen.';
    final total = s.contracts.fold<int>(0, (a, c) => a + c.monthlyCents);
    final lines = [for (final c in s.contracts.take(6)) '- ${c.name}: ${_eur(c.monthlyCents)}'];
    return 'Du hast **${s.contracts.length} feste Zahlungen** über **${_eur(total)} im Monat** '
        '(${_eur(total * 12)} im Jahr):\n${lines.join('\n')}';
  }

  static String _budgets(FinanceSnapshot s) {
    if (s.budgets.isEmpty) return 'Du hast für diesen Monat noch keine Budgets. Leg im Konto unter „Budgets“ eins an.';
    final lines = [
      for (final b in s.budgets)
        '- ${b.category}: ${_eur(b.spentCents)} von ${_eur(b.limitCents)}'
            '${b.spentCents > b.limitCents ? ' – **überschritten**' : ' (${b.percentUsed} %)'}'
    ];
    return 'So stehen deine Budgets, noch ${s.daysLeftInMonth} Tage im Monat:\n${lines.join('\n')}';
  }

  static String _depot(FinanceSnapshot s) {
    if (s.holdings.isEmpty) return 'Du hast noch keine Positionen im Depot.';
    final invested = s.holdings.fold<int>(0, (a, h) => a + h.investedCents);
    final gain = s.depotCents - invested;
    final biggest = (s.holdings.toList()..sort((a, b) => b.valueCents.compareTo(a.valueCents))).first;
    return 'Dein Depot ist **${_eur(s.depotCents)}** wert, ${gain >= 0 ? 'ein Plus' : 'ein Minus'} von '
        '${_eur(gain.abs())} auf ${_eur(invested)} Einsatz.\n\n- Größte Position: ${biggest.name} '
        '(${(biggest.valueCents / s.depotCents * 100).round()} %)\n- Faustregel: breit gestreut und langfristig, '
        'und vorher drei Monatsausgaben als Notgroschen.';
  }

  static String _overview(FinanceSnapshot s) {
    final m = s.current;
    return 'Dein Überblick:\n- Kontostand: **${_eur(s.balanceCents)}**\n- Depot: ${_eur(s.depotCents)}\n'
        '- Diesen Monat: ${_eur(m.income)} rein, ${_eur(m.expenses)} raus\n\n'
        'Frag mich zum Beispiel, wo du sparen kannst oder ob du dir etwas leisten kannst.';
  }
}

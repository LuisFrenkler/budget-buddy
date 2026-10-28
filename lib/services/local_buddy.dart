// Buddy's answers without the AI: the common questions answered with real
// numbers computed on the device. Used offline and whenever the
// server has no AI configured. The app labels these answers as offline.
import '../utils/dates.dart';
import '../utils/money.dart';
import 'category_coach.dart';
import 'finance_snapshot.dart';
import 'forecast_service.dart';
import 'goals_service.dart';

class LocalBuddy {
  // [history] is prior turns (user/assistant); follow-ups reuse the last user topic
  static String answer(String question, FinanceSnapshot s, {List<({bool fromUser, String text})>? history}) {
    final q = question.toLowerCase().trim();
    final prior = _priorUser(history);
    final topic = _followUp(q) && prior != null ? prior.toLowerCase() : q;
    if (_has(topic, ['kategor', 'sonstiges']) || _has(q, ['kategor', 'sonstiges aufräumen'])) {
      return _categories(s);
    }
    if (_has(topic, ['plus', 'premium']) && !_has(topic, ['depot', 'aktie', 'etf'])) return _plus(s);
    if (_has(topic, ['vorsorge', 'altersvorsorge', 'rente'])) return _vorsorge(s);
    if (_has(topic, ['split', 'schuldet', 'geteilt'])) return _splits(s);
    if (_has(topic, ['vermögen', 'vermoegen', 'schulden', 'notgroschen', 'versicherung', 'sparquote', 'netto'])) {
      return _wealth(s);
    }
    if (_has(topic, ['wiederkehr', 'dauerauftrag'])) return _recurring(s);
    if (_has(topic, ['letzte buchung', 'letzten buchungen', 'transaktion', 'welche konten', 'meine konten', 'konten'])) {
      return _accounts(s);
    }
    if (_has(topic, ['was bleibt', 'noch ausgeben', 'prognose', 'bleibt', 'monatsende'])) return _forecast(s);
    if (_goalQuestion(topic)) return _goals(s);
    if (_has(topic, ['abo', 'vertr', 'fixkost'])) return _contracts(s);
    if (_has(topic, ['leisten', 'urlaub', 'kaufen', 'sparziel', 'zurücklegen'])) return _afford(topic, s);
    if (_has(topic, ['spar'])) return _save(s);
    if (_has(topic, ['budget'])) return _budgets(s);
    if (_has(topic, ['depot', 'aktie', 'etf', 'invest', 'anlage'])) return _depot(s);
    if (_has(topic, ['meisten', 'wofür', 'ausgegeben', 'ausgaben', 'kategorie'])) return _spending(s);
    return _overview(s);
  }

  static String? _priorUser(List<({bool fromUser, String text})>? history) {
    if (history == null || history.length < 2) return null;
    for (var i = history.length - 2; i >= 0; i--) {
      if (history[i].fromUser && history[i].text.trim().isNotEmpty) return history[i].text;
    }
    return null;
  }

  static bool _followUp(String q) {
    if (q.length <= 28 && RegExp(r'^(und|warum|wieso|wie viel|wieviel|genau|davon|dazu|nochmal|mehr dazu|was meinst)\b').hasMatch(q)) {
      return true;
    }
    return q == 'und?' || q == 'warum?' || q == 'wieso?' || q == 'genau?' || q == 'davon?';
  }

  static String _categories(FinanceSnapshot s) {
    final n = CategoryCoach.miscCount();
    if (n == 0) return 'Alles sauber kategorisiert — kein Sonstiges offen.';
    final auto = CategoryCoach.autoFixes(limit: 5);
    final left = CategoryCoach.leftovers(limit: 5);
    final lines = <String>[
      '**$n** Buchungen stecken noch in Sonstiges.',
      if (auto.isNotEmpty) ...[
        '',
        'Kann ich so zuordnen — sag **„Sonstiges aufräumen“**:',
        for (final p in auto) '- ${p.sample}: **${p.category}** (${p.count}×)',
      ],
      if (left.isNotEmpty) ...[
        '',
        'Unklar, sag z. B. „${left.first.sample} → Lebensmittel“:',
        for (final g in left.take(3)) '- ${g.sample} (${g.count}×)',
      ],
    ];
    return lines.join('\n');
  }

  // status of a goal, not "kann ich mir etwas leisten"
  static bool _goalQuestion(String q) =>
      _has(q, ['sparziel', 'sparziele', 'mein ziel', 'meine ziele', 'ziele']) &&
      !_has(q, ['leisten', 'kaufen', 'urlaub', 'zurücklegen']);

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

  static String _goals(FinanceSnapshot s) {
    if (s.goals.isEmpty) return 'Du hast noch keine Sparziele. Leg eins unter Sparziele an, dann rechne ich den Plan.';
    final surplus = s.avgIncome - s.avgExpenses;
    final lines = [
      for (final g in s.goals.take(6))
        '- ${g.emoji} ${g.name}: ${_eur(g.savedCents)} von ${_eur(g.targetCents)} '
            '(${(g.progress * 100).round()} %). ${GoalsService.plan(g, avgSurplusCents: surplus, now: s.today).text}'
    ];
    return 'Deine Sparziele:\n${lines.join('\n')}';
  }

  static String _wealth(FinanceSnapshot s) {
    final net = s.balanceCents + s.depotCents - s.debtCents;
    final lines = <String>[
      '- Nettovermögen: **${_eur(net)}** (Konten ${_eur(s.balanceCents)}, Depot ${_eur(s.depotCents)}'
          '${s.debtCents > 0 ? ', Schulden ${_eur(s.debtCents)}' : ''})',
    ];
    if (s.savingsRatePercent != null) lines.add('- Sparquote der letzten vollen Monate: ${s.savingsRatePercent} %');
    if (s.emergencyTargetCents != null) {
      lines.add('- Notgroschen: ${_eur(s.emergencyHaveCents)} von ${_eur(s.emergencyTargetCents!)}');
    } else if (s.emergencyHaveCents > 0) {
      lines.add('- Auf Sparkonten: ${_eur(s.emergencyHaveCents)}');
    }
    if (s.debts.isNotEmpty) {
      lines.add('- Schulden: ${s.debts.take(4).map((d) => '${d.name} ${_eur(d.cents)}').join(', ')}');
    }
    if (s.policies.isNotEmpty) {
      final sum = s.policies.fold<int>(0, (a, p) => a + p.monthlyCents);
      lines.add('- Versicherungen: ${s.policies.take(4).map((p) => p.name).join(', ')} (${_eur(sum)} im Monat)');
    }
    if (s.runwayMonths != null) lines.add('- Reichweite: etwa ${s.runwayMonths} Monate bei deinem üblichen Verbrauch');
    return 'Vermögen:\n${lines.join('\n')}';
  }

  static String _vorsorge(FinanceSnapshot s) {
    final v = s.vorsorge;
    if (v == null) {
      return 'Altersvorsorge ist noch nicht eingerichtet. Trag unter Vorsorge deine Rente ein, dann rechne ich die Lücke. '
          'Das ist eine Orientierung, keine Beratung.';
    }
    if (v.gapClosed) {
      return 'Orientierung, keine Beratung: Deine Wunschrente von ${_eur(v.input.desiredNetCents)} im Monat '
          'ist mit den eingetragenen Bausteinen gedeckt.';
    }
    return 'Orientierung, keine Beratung: Bis ${v.input.retireAge} sind es **${v.yearsLeft} Jahre**. '
        'Dir fehlen etwa **${_eur(v.gapMonthlyCents)} im Monat**. Dafür wären ungefähr '
        '${_eur(v.saveExtraMonthlyCents)} im Monat extra nötig '
        '(gesetzlich ${_eur(v.input.statutoryCents)}, Kapital ${_eur(v.capitalCents)}).';
  }

  static String _splits(FinanceSnapshot s) {
    if (s.splits.isEmpty) return 'Du hast noch keine geteilten Ausgaben.';
    final lines = [
      for (final g in s.splits.take(5))
        '- ${g.name}: ${g.myCents == 0 ? 'ausgeglichen' : g.myCents > 0 ? 'du bekommst ${_eur(g.myCents)}' : 'du schuldest ${_eur(-g.myCents)}'}'
    ];
    return 'Splits:\n${lines.join('\n')}';
  }

  static String _recurring(FinanceSnapshot s) {
    final rules = s.recurring.where((r) => r.active).toList();
    if (rules.isEmpty) return 'Du hast keine aktiven wiederkehrenden Buchungen.';
    final lines = [
      for (final r in rules.take(6))
        '- ${r.title}: ${_eur(r.cents)} ${r.interval}${r.income ? ' (Einnahme)' : ''} · nächstes ${_date(r.next)}'
    ];
    return 'Wiederkehrend:\n${lines.join('\n')}';
  }

  static String _accounts(FinanceSnapshot s) {
    final accounts = s.accounts.isEmpty
        ? '- Kontostand: **${_eur(s.balanceCents)}**'
        : s.accounts.map((a) => '- ${a.name} (${a.art}): **${_eur(a.cents)}**').join('\n');
    final recent = [
      for (final t in s.recent.take(5))
        '- ${t.date}: ${t.note} ${t.cents < 0 ? '−' : '+'}${_eur(t.cents.abs())} (${t.account})'
    ];
    final tail = recent.isEmpty ? '' : '\n\nLetzte Buchungen:\n${recent.join('\n')}';
    return 'Konten:\n$accounts$tail';
  }

  static String _forecast(FinanceSnapshot s) {
    final f = s.forecast;
    if (f == null) return 'Dafür brauche ich ein paar volle Monate mit Einnahmen.';
    final tempo = switch (f.pace) {
      ForecastPace.relaxed => 'entspannt',
      ForecastPace.tight => 'knapp',
      ForecastPace.over => 'über dem Plan',
    };
    final due = f.due.isEmpty ? '' : ' Noch fällig: ${f.due.take(3).map((d) => '${d.name} ${_eur(d.cents)}').join(', ')}.';
    return 'Bis Monatsende bleiben dir **${_eur(f.freeCents)}**, etwa ${_eur(f.perDayCents)} am Tag. Das Tempo ist $tempo.$due';
  }

  static String _plus(FinanceSnapshot s) {
    final p = s.plus;
    if (p.active) {
      final trial = p.trial && p.bis != null ? ' Testphase bis ${_date(p.bis!)}.' : '';
      final end = p.cancelled && p.bis != null ? ' Gekündigt, nutzbar bis ${_date(p.bis!)}.' : '';
      return '**Plus ist aktiv** (${p.plan ?? 'monatlich'}).$trial$end';
    }
    final left = p.fragenRest == null
        ? ''
        : 'Noch ${p.fragenRest} Gratis-Fragen und ${p.scansRest ?? 0} Beleg-Scans in diesem Monat. ';
    return 'Plus ist nicht aktiv. ${left}Ein Sparziel ist gratis, weitere mit Plus.';
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : Dates.full(d);
  }

  static String _overview(FinanceSnapshot s) {
    final m = s.current;
    if (s.past.isEmpty && m.expenses == 0 && m.income == 0 && s.depotCents == 0) {
      return 'Hier ist noch wenig Verlauf. Verbinde deine Bank oder erfasse ein paar Ausgaben — '
          'dann kann ich konkret rechnen.\n\n'
          'Du kannst trotzdem fragen, z. B. **„Wo kann ich sparen?“** oder **„Wie lege ich ein Sparziel an?“**';
    }
    return 'Dein Überblick:\n- Kontostand: **${_eur(s.balanceCents)}**\n- Depot: ${_eur(s.depotCents)}\n'
        '- Diesen Monat: ${_eur(m.income)} rein, ${_eur(m.expenses)} raus\n\n'
        'Frag mich zum Beispiel zu Ausgaben, Sparzielen, Depot, Vermögen, Rente oder Splits.';
  }
}

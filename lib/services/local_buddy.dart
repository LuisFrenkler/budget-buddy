// Buddy's answers without the AI: the common questions answered with real
// numbers computed on the device. Used offline and whenever the
// server has no AI configured. The app labels these answers as offline.
import '../utils/dates.dart';
import '../utils/merchant.dart';
import '../utils/money.dart';
import 'category_coach.dart';
import 'db.dart';
import 'finance_snapshot.dart';
import 'forecast_service.dart';
import 'goals_service.dart';
import 'scenario_service.dart';
import '../l10n/l10n.dart';
import 'net_salary.dart';

class LocalBuddy {
  // [history] is prior turns (user/assistant); follow-ups reuse the last user topic
  // "3.000 brutto, was bleibt netto?": the 2026 wage tax works without AI too
  static String? netAnswer(String q) {
    if (!RegExp(r'brutto|gross|netto|net pay|take.home').hasMatch(q)) return null;
    final m = RegExp(r'(\d{1,3}(?:[.,]\d{3})+|\d{3,6})(?:[.,]\d{1,2})?\s*(?:€|euro|eur|k\b)?').firstMatch(q.replaceAll('€', ' €'));
    if (m == null) return null;
    var gross = double.tryParse(m.group(1)!.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
    if (gross < 400) return null;
    final yearly = RegExp(r'jahr|jährlich|p\.\s?a|year|annual').hasMatch(q) || gross > 15000;
    if (yearly) gross = gross / 12;
    final classMatch = RegExp(r'(?:steuerklasse|klasse|tax class|class)\s*(\d|i{1,3}|iv)').firstMatch(q);
    final roman = {'i': 1, 'ii': 2, 'iii': 3, 'iv': 4};
    final cls = classMatch == null ? 1 : int.tryParse(classMatch.group(1)!) ?? roman[classMatch.group(1)] ?? 1;
    final r = NetSalary.compute(gross, taxClass: cls, church: RegExp(r'kirch|church').hasMatch(q));
    return tr('Von **{gross}** brutto bleiben etwa **{net}** netto im Monat.\n\n'
            '- Lohnsteuer: {tax}{soli}\n'
            '- Sozialabgaben: {social} (Rente, Arbeitslosen-, Kranken- und Pflegeversicherung)\n\n'
            'Gerechnet für Steuerklasse {cls}, gesetzlich versichert mit durchschnittlichem Zusatzbeitrag, '
            'Lohnsteuer 2026. Deine Abrechnung kann um ein paar Euro abweichen.\n\n'
            'Nächster Schritt: Leg deine erste Abrechnung daneben und vergleich Steuerklasse und Netto.',
        {
          'gross': Money.format((gross * 100).round()),
          'net': Money.format((r.net * 100).round()),
          'tax': Money.format(((r.wageTax + r.churchTax) * 100).round()),
          'soli': r.soli > 0 ? tr(' plus {x} Soli', {'x': Money.format((r.soli * 100).round())}) : '',
          'social': Money.format((r.social * 100).round()),
          'cls': cls,
        });
  }

  static String answer(String question, FinanceSnapshot s, {List<({bool fromUser, String text})>? history}) {
    final q = question.toLowerCase().trim();
    final prior = _priorUser(history);
    final topic = _followUp(q) && prior != null ? prior.toLowerCase() : q;
    final net = netAnswer(q);
    if (net != null) return net;
    if (_has(topic, ['kategor', 'sonstiges', 'categor']) || _has(q, ['kategor', 'sonstiges aufräumen', 'tidy up other'])) {
      return _categories(s);
    }
    if (_has(topic, ['plus', 'premium']) && !_has(topic, ['depot', 'aktie', 'etf'])) return _plus(s);
    if (_has(topic, ['vorsorge', 'altersvorsorge', 'rente', 'retire', 'pension'])) return _vorsorge(s);
    if (_has(topic, ['split', 'schuldet', 'geteilt', 'owe', 'flatshare'])) return _splits(s);
    if (_has(topic, ['vermögen', 'vermoegen', 'schulden', 'notgroschen', 'versicherung', 'sparquote', 'netto', 'wealth', 'net worth', 'debt', 'emergency', 'insurance'])) {
      return _wealth(s);
    }
    if (_has(topic, ['wiederkehr', 'dauerauftrag', 'recurring', 'standing order'])) return _recurring(s);
    if (_has(topic, ['letzte buchung', 'letzten buchungen', 'transaktion', 'welche konten', 'meine konten', 'konten', 'transaction', 'my accounts'])) {
      return _accounts(s);
    }
    if (_scenarioQuestion(topic, s)) return _scenario(topic, s);
    if (_has(topic, ['was bleibt', 'noch ausgeben', 'prognose', 'bleibt', 'monatsende', 'left', 'end of the month', 'forecast', 'free this month'])) return _forecast(s);
    if (_goalQuestion(topic)) return _goals(s);
    if (_has(topic, ['abo', 'vertr', 'fixkost', 'subscri', 'contract', 'fixed cost'])) return _contracts(s);
    if (_has(topic, ['leisten', 'urlaub', 'kaufen', 'sparziel', 'zurücklegen', 'afford', 'holiday', 'buy', 'savings goal'])) return _afford(topic, s);
    if (_has(topic, ['spar', 'save'])) return _save(s);
    if (_has(topic, ['budget'])) return _budgets(s);
    if (_has(topic, ['depot', 'aktie', 'etf', 'invest', 'anlage', 'portfolio', 'stock'])) return _depot(s);
    if (_has(topic, ['meisten', 'wofür', 'ausgegeben', 'ausgaben', 'kategorie', 'spend', 'spent'])) return _spending(s);
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
    if (n == 0) return tr('Alles sauber kategorisiert, kein Sonstiges offen.');
    final auto = CategoryCoach.autoFixes(limit: 5);
    final left = CategoryCoach.leftovers(limit: 5);
    final lines = <String>[
      '**$n** Buchungen stecken noch in Sonstiges.',
      if (auto.isNotEmpty) ...[
        '',
        tr('So würde ich zuordnen. Sag **„Sonstiges aufräumen“**:'),
        for (final p in auto) '- ${p.sample}: **${tr(p.category)}** (${p.count}×)',
      ],
      if (left.isNotEmpty) ...[
        '',
        tr('Unklar, sag z. B. „{x} → Lebensmittel“:', {'x': left.first.sample}),
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
    if (m.expenses == 0) return tr('Diesen Monat hast du noch keine Ausgaben erfasst.');
    final lines = [
      for (final e in _top(m.byCategory, 3)) '- ${e.key}: **${_eur(e.value)}** (${(e.value / m.expenses * 100).round()} %)'
    ];
    final merchant = s.topMerchants.isEmpty ? '' : tr('\n\nAm meisten Geld ging an **{x}** ({y}).', {'x': s.topMerchants.first.name, 'y': _eur(s.topMerchants.first.cents)});
    return tr('Diesen Monat hast du bisher **{x}** ausgegeben, vor allem für:\n{y}{merchant}', {'x': _eur(m.expenses), 'y': lines.join('\n'), 'merchant': merchant});
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
      tips.add(tr('- **{x}**: {y} mehr als sonst in einem Monat', {'x': e.key, 'y': _eur(e.value)}));
    }
    final subs = s.contracts.where((c) => c.category == 'Unterhaltung').toList();
    if (subs.isNotEmpty) {
      final sum = subs.fold<int>(0, (a, c) => a + c.monthlyCents);
      tips.add(tr('- **Abos**: {x} kosten zusammen {y} im Monat ({z} im Jahr). Brauchst du alle?', {'x': subs.map((c) => c.name).join(', '), 'y': _eur(sum), 'z': _eur(sum * 12)}));
    }
    if (tips.isEmpty) {
      final top = _top(avg, 1);
      if (top.isEmpty) return tr('Dafür brauche ich noch etwas mehr Verlauf. Erfasse ein paar Wochen deine Ausgaben.');
      tips.add(tr('- Dein größter Posten ist **{x}** mit etwa {y} im Monat. Schon 10 % weniger sind {z} im Monat.', {'x': top.first.key, 'y': _eur(top.first.value), 'z': _eur(top.first.value ~/ 10)}));
    }
    return tr('Hier steckt Sparpotenzial:\n{x}\n\nTipp: Leg dir für die größte Kategorie ein Budget an, dann warnt dich die App rechtzeitig.', {'x': tips.join('\n')});
  }

  static String _afford(String q, FinanceSnapshot s) {
    final surplus = s.avgIncome - s.avgExpenses;
    final match = RegExp(r'(\d[\d.]*)').firstMatch(q);
    final target = match == null ? null : int.tryParse(match.group(1)!.replaceAll('.', ''));
    if (s.past.isEmpty) return tr('Dafür brauche ich mindestens einen vollen Monat an Daten.');
    if (surplus <= 0) {
      return tr('Im Schnitt gibst du gerade **{x} mehr aus**, als reinkommt. Bevor du sparst, lohnt ein Blick auf deine größten Kategorien.', {'x': _eur(-surplus)});
    }
    final base = tr('Im Schnitt bleiben dir **{x} pro Monat** übrig (Einnahmen {y}, Ausgaben {z}).', {'x': _eur(surplus), 'y': _eur(s.avgIncome), 'z': _eur(s.avgExpenses)});
    if (target == null || target <= 0) {
      return tr('{base}\n\nNenn mir einen Betrag, dann rechne ich aus, wie schnell du ihn zusammen hast.', {'base': base});
    }
    final cents = target * 100;
    final months = (cents / surplus).ceil();
    final buffer = s.balanceCents - cents;
    final lines = <String>[
      base,
      '',
      tr('- Für **{x}** brauchst du etwa **{months} {y}**.', {'x': _eur(cents), 'months': months, 'y': months == 1 ? tr('Monat') : tr('Monate')}),
      tr('- Aus dem Kontostand bezahlt blieben dir {x}{y}', {'x': _eur(buffer), 'y': buffer < s.avgExpenses ? tr(', weniger als ein Monat Ausgaben. Lieber ansparen.') : '. Das passt.'}),
    ];
    // same formula as Monats-Simulator for this month
    final cmp = ScenarioService.compare(
      DB.getTx(),
      overrides: ForecastOverrides(oneTimeSpentCents: cents),
      goals: GoalsService.all(),
      balanceCents: s.balanceCents,
      now: s.today,
    );
    if (cmp != null) {
      final free = cmp.sim.freeCents;
      lines.add(free >= 0
          ? tr('- Diesen Monat blieben danach noch **{x}** frei, etwa {y} am Tag.', {'x': _eur(free), 'y': _eur(cmp.sim.perDayCents)})
          : tr('- Diesen Monat wärst du **{x} über** dem Plan.', {'x': _eur(-free)}));
    }
    return lines.join('\n');
  }

  static String _contracts(FinanceSnapshot s) {
    if (s.contracts.isEmpty) return tr('Ich habe noch keine festen Verträge erkannt. Dafür brauche ich drei Monate gleiche Zahlungen.');
    final total = s.contracts.fold<int>(0, (a, c) => a + c.monthlyCents);
    final lines = [for (final c in s.contracts.take(6)) '- ${c.name}: ${_eur(c.monthlyCents)}'];
    return tr('Du hast **{x} feste Zahlungen** über **{y} im Monat** ({z} im Jahr):\n{a}', {'x': s.contracts.length, 'y': _eur(total), 'z': _eur(total * 12), 'a': lines.join('\n')});
  }

  static String _budgets(FinanceSnapshot s) {
    if (s.budgets.isEmpty) return tr('Du hast für diesen Monat noch keine Budgets. Leg im Konto unter „Budgets“ eins an.');
    final lines = [
      for (final b in s.budgets)
        tr('- {x}: {y} von {z}{a}', {'x': b.category, 'y': _eur(b.spentCents), 'z': _eur(b.limitCents), 'a': b.spentCents > b.limitCents ? tr(' – **überschritten**') : ' (${b.percentUsed} %)'})
    ];
    return tr('So stehen deine Budgets, noch {x} Tage im Monat:\n{y}', {'x': s.daysLeftInMonth, 'y': lines.join('\n')});
  }

  static String _depot(FinanceSnapshot s) {
    if (s.holdings.isEmpty) return tr('Du hast noch keine Positionen im Depot.');
    final invested = s.holdings.fold<int>(0, (a, h) => a + h.investedCents);
    final gain = s.depotCents - invested;
    final biggest = (s.holdings.toList()..sort((a, b) => b.valueCents.compareTo(a.valueCents))).first;
    return tr('Dein Depot ist **{x}** wert, {y} von {z} auf {a} Einsatz.\n\n- Größte Position: {b} ({c} %)\n- Faustregel: breit gestreut und langfristig, und vorher drei Monatsausgaben als Notgroschen.', {'x': _eur(s.depotCents), 'y': gain >= 0 ? 'ein Plus' : 'ein Minus', 'z': _eur(gain.abs()), 'a': _eur(invested), 'b': biggest.name, 'c': (biggest.valueCents / s.depotCents * 100).round()});
  }

  static String _goals(FinanceSnapshot s) {
    if (s.goals.isEmpty) return tr('Du hast noch keine Sparziele. Leg eins unter Sparziele an, dann rechne ich den Plan.');
    final surplus = s.avgIncome - s.avgExpenses;
    final lines = [
      for (final g in s.goals.take(6))
        tr('- {x} {y}: {z} von {a} ({b} %). {c}', {'x': g.emoji, 'y': g.name, 'z': _eur(g.savedCents), 'a': _eur(g.targetCents), 'b': (g.progress * 100).round(), 'c': GoalsService.plan(g, avgSurplusCents: surplus, now: s.today).text})
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
      lines.add(tr('- Notgroschen: {x} von {y}', {'x': _eur(s.emergencyHaveCents), 'y': _eur(s.emergencyTargetCents!)}));
    } else if (s.emergencyHaveCents > 0) {
      lines.add('- Auf Sparkonten: ${_eur(s.emergencyHaveCents)}');
    }
    if (s.debts.isNotEmpty) {
      lines.add('- Schulden: ${s.debts.take(4).map((d) => '${d.name} ${_eur(d.cents)}').join(', ')}');
    }
    if (s.policies.isNotEmpty) {
      final sum = s.policies.fold<int>(0, (a, p) => a + p.monthlyCents);
      lines.add(tr('- Versicherungen: {x} ({y} im Monat)', {'x': s.policies.take(4).map((p) => p.name).join(', '), 'y': _eur(sum)}));
    }
    if (s.runwayMonths != null) lines.add(tr('- Reichweite: etwa {x} Monate bei deinem üblichen Verbrauch', {'x': s.runwayMonths}));
    return tr('Vermögen:\n{x}', {'x': lines.join('\n')});
  }

  static String _vorsorge(FinanceSnapshot s) {
    final v = s.vorsorge;
    if (v == null) {
      return tr('Altersvorsorge ist noch nicht eingerichtet. Trag unter Vorsorge deine Rente ein, dann rechne ich die Lücke. Das ist eine Orientierung, keine Beratung.');
    }
    if (v.gapClosed) {
      return tr('Orientierung, keine Beratung: Deine Wunschrente von {x} im Monat ist mit den eingetragenen Bausteinen gedeckt.', {'x': _eur(v.input.desiredNetCents)});
    }
    return tr('Orientierung, keine Beratung: Bis {x} sind es **{y} Jahre**. Dir fehlen etwa **{z} im Monat**. Dafür wären ungefähr {a} im Monat extra nötig (gesetzlich {b}, Kapital {c}).', {'x': v.input.retireAge, 'y': v.yearsLeft, 'z': _eur(v.gapMonthlyCents), 'a': _eur(v.saveExtraMonthlyCents), 'b': _eur(v.input.statutoryCents), 'c': _eur(v.capitalCents)});
  }

  static String _splits(FinanceSnapshot s) {
    if (s.splits.isEmpty) return tr('Du hast noch keine geteilten Ausgaben.');
    final lines = [
      for (final g in s.splits.take(5))
        '- ${g.name}: ${g.myCents == 0 ? 'ausgeglichen' : g.myCents > 0 ? 'du bekommst ${_eur(g.myCents)}' : 'du schuldest ${_eur(-g.myCents)}'}'
    ];
    return 'Splits:\n${lines.join('\n')}';
  }

  static String _recurring(FinanceSnapshot s) {
    final rules = s.recurring.where((r) => r.active).toList();
    if (rules.isEmpty) return tr('Du hast keine aktiven wiederkehrenden Buchungen.');
    final lines = [
      for (final r in rules.take(6))
        tr('- {x}: {y} {z}{a} · nächstes {b}', {'x': r.title, 'y': _eur(r.cents), 'z': tr(r.interval), 'a': r.income ? tr(' (Einnahme)') : '', 'b': _date(r.next)})
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

  // "Was wäre ohne Netflix?" / "wenn ich 200 ausgebe", same formula as the sheet
  static bool _scenarioQuestion(String q, FinanceSnapshot s) {
    if (_has(q, ['was wäre', 'wenn ich', 'what if'])) return true;
    if (!_has(q, ['kündig', 'ohne', 'cancel', 'without', 'drop'])) return false;
    return s.contracts.any((c) => q.contains(c.name.toLowerCase()));
  }

  static String _scenario(String q, FinanceSnapshot s) {
    if (s.forecast == null) return tr('Dafür brauche ich ein paar volle Monate mit Einnahmen.');
    final named = s.contracts.where((c) => q.contains(c.name.toLowerCase())).toList();
    final match = RegExp(r'(\d[\d.]*)').firstMatch(q);
    final euros = match == null ? null : int.tryParse(match.group(1)!.replaceAll('.', ''));

    late final ForecastOverrides overrides;
    late final String label;
    if (named.isNotEmpty) {
      final c = named.first;
      overrides = ForecastOverrides(excludedContractKeys: {Merchant.key(c.name)});
      label = tr('ohne **{x}** ({y}/Monat)', {'x': c.name, 'y': _eur(c.monthlyCents)});
    } else if (euros != null && euros > 0) {
      overrides = ForecastOverrides(oneTimeSpentCents: euros * 100);
      label = tr('mit einem Kauf von **{x}**', {'x': _eur(euros * 100)});
    } else if (s.contracts.isNotEmpty) {
      final tip = s.contracts.take(3).map((c) => c.name).join(', ');
      return tr('Sag z. B. „Was wäre ohne {x}?“ oder nenn einen Betrag.\nErkannte Abos: {tip}.', {'x': s.contracts.first.name, 'tip': tip});
    } else {
      return tr('Abos habe ich noch keine erkannt. Frag zum Beispiel: „Was wäre, wenn ich 200 € ausgebe?“');
    }

    final cmp = ScenarioService.compare(
      DB.getTx(),
      overrides: overrides,
      goals: GoalsService.all(),
      balanceCents: s.balanceCents,
      now: s.today,
    );
    if (cmp == null) return tr('Dafür brauche ich ein paar volle Monate mit Einnahmen.');
    final delta = cmp.deltaFree;
    final deltaLine = delta == 0
        ? tr('Am freien Betrag ändert sich nichts.')
        : delta > 0
            ? tr('Das wären **{x} mehr** frei ({y}/Tag).', {'x': _eur(delta), 'y': _eur(cmp.deltaPerDay)})
            : tr('Das wären **{x} weniger** frei ({y}/Tag).', {'x': _eur(-delta), 'y': _eur(-cmp.deltaPerDay)});
    return 'Heute bleiben **${_eur(cmp.base.freeCents)}**.\n'
        'Szenario $label: **${_eur(cmp.sim.freeCents)}**.\n'
        '$deltaLine';
  }

  static String _forecast(FinanceSnapshot s) {
    final f = s.forecast;
    if (f == null) return tr('Dafür brauche ich ein paar volle Monate mit Einnahmen.');
    final tempo = switch (f.pace) {
      ForecastPace.relaxed => 'entspannt',
      ForecastPace.tight => 'knapp',
      ForecastPace.over => tr('über dem Plan'),
    };
    final due = f.due.isEmpty ? '' : tr(' Noch fällig: {x}.', {'x': f.due.take(3).map((d) => '${d.name} ${_eur(d.cents)}').join(', ')});
    return tr('Bis Monatsende bleiben dir **{x}**, etwa {y} am Tag. Das Tempo ist {tempo}.{due}', {'x': _eur(f.freeCents), 'y': _eur(f.perDayCents), 'tempo': tempo, 'due': due});
  }

  static String _plus(FinanceSnapshot s) {
    final p = s.plus;
    if (p.active) {
      final trial = p.trial && p.bis != null ? tr(' Testphase bis {x}.', {'x': _date(p.bis!)}) : '';
      final end = p.cancelled && p.bis != null ? tr(' Gekündigt, nutzbar bis {x}.', {'x': _date(p.bis!)}) : '';
      return tr('**Plus ist aktiv** ({x}).{trial}{end}', {'x': p.plan ?? 'monatlich', 'trial': trial, 'end': end});
    }
    final left = p.fragenRest == null
        ? ''
        : tr('Noch {x} Gratis-Fragen und {y} Beleg-Scans in diesem Monat. ', {'x': p.fragenRest, 'y': p.scansRest ?? 0});
    return tr('Plus ist nicht aktiv. {left}Ein Sparziel ist gratis, weitere mit Plus.', {'left': left});
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : Dates.full(d);
  }

  static String _overview(FinanceSnapshot s) {
    final m = s.current;
    if (s.past.isEmpty && m.expenses == 0 && m.income == 0 && s.depotCents == 0) {
      return tr('Hier ist noch wenig Verlauf. Verbinde deine Bank oder erfasse ein paar Ausgaben, dann kann ich konkret rechnen.\n\nDu kannst trotzdem fragen, z. B. **„Wo kann ich sparen?“** oder **„Wie lege ich ein Sparziel an?“**');
    }
    return tr('Dein Überblick:\n- Kontostand: **{x}**\n- Depot: {y}\n- Diesen Monat: {z} rein, {a} raus\n\nFrag mich zum Beispiel zu Ausgaben, Sparzielen, Depot, Vermögen, Rente oder Splits.', {'x': _eur(s.balanceCents), 'y': _eur(s.depotCents), 'z': _eur(m.income), 'a': _eur(m.expenses)});
  }
}

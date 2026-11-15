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
import 'sub_tips.dart';
import '../l10n/l10n.dart';
import 'affordability.dart';
import 'insurance_check.dart';
import 'net_salary.dart';

class LocalBuddy {
  // [history] is prior turns (user/assistant); follow-ups reuse the last user topic
  // "3.000 brutto, was bleibt netto?": the 2026 wage tax works without AI too
  static String? netAnswer(String q) {
    if (!RegExp(r'brutto|gross|netto|net pay|take.home').hasMatch(q))
      return null;
    final m = RegExp(
            r'(\d{1,3}(?:[.,]\d{3})+|\d{3,6})(?:[.,]\d{1,2})?\s*(?:€|euro|eur|k\b)?')
        .firstMatch(q.replaceAll('€', ' €'));
    if (m == null) return null;
    var gross =
        double.tryParse(m.group(1)!.replaceAll(RegExp(r'[.,]'), '')) ?? 0;
    if (gross < 400) return null;
    final yearly = RegExp(r'jahr|jährlich|p\.\s?a|year|annual').hasMatch(q) ||
        gross > 15000;
    if (yearly) gross = gross / 12;
    final classMatch =
        RegExp(r'(?:steuerklasse|klasse|tax class|class)\s*(\d|i{1,3}|iv)')
            .firstMatch(q);
    final roman = {'i': 1, 'ii': 2, 'iii': 3, 'iv': 4};
    final cls = classMatch == null
        ? 1
        : int.tryParse(classMatch.group(1)!) ?? roman[classMatch.group(1)] ?? 1;
    final r = NetSalary.compute(gross,
        taxClass: cls, church: RegExp(r'kirch|church').hasMatch(q));
    return tr(
        '**{net}** netto, von **{gross}** brutto. Lohnsteuer {tax}{soli}, Sozialabgaben {social}. Steuerklasse {cls}, Lohnsteuer 2026, kann um ein paar Euro abweichen.',
        {
          'gross': Money.format((gross * 100).round()),
          'net': Money.format((r.net * 100).round()),
          'tax': Money.format(((r.wageTax + r.churchTax) * 100).round()),
          'soli': r.soli > 0
              ? tr(
                  ' plus {x} Soli', {'x': Money.format((r.soli * 100).round())})
              : '',
          'social': Money.format((r.social * 100).round()),
          'cls': cls,
        });
  }

  static String answer(String question, FinanceSnapshot s,
      {List<({bool fromUser, String text})>? history}) {
    final q = question.toLowerCase().trim();
    final prior = _priorUser(history);
    final topic = _followUp(q) && prior != null ? prior.toLowerCase() : q;
    final net = netAnswer(q);
    if (net != null) return net;
    if (_has(topic, ['kategor', 'sonstiges', 'categor']) ||
        _has(q, ['kategor', 'sonstiges aufräumen', 'tidy up other'])) {
      return _categories(s);
    }
    if (_has(topic, ['plus', 'premium']) &&
        !_has(topic, ['depot', 'aktie', 'etf'])) return _plus(s);
    if (_has(
        topic, ['vorsorge', 'altersvorsorge', 'rente', 'retire', 'pension']))
      return _vorsorge(s);
    if (_has(topic, ['split', 'schuldet', 'geteilt', 'owe', 'flatshare']))
      return _splits(s);
    if (_has(topic, [
          'versicherung',
          'insurance',
          'überversichert',
          'uberversichert',
          'overinsured'
        ]) &&
        !_has(topic, ['vermögen', 'vermoegen', 'schulden', 'wealth', 'debt'])) {
      return _insurance(s);
    }
    if (_has(topic, [
      'vermögen',
      'vermoegen',
      'schulden',
      'notgroschen',
      'sparquote',
      'netto',
      'wealth',
      'net worth',
      'debt',
      'emergency'
    ])) {
      return _wealth(s);
    }
    if (_has(
        topic, ['wiederkehr', 'dauerauftrag', 'recurring', 'standing order']))
      return _recurring(s);
    if (_has(topic, [
      'letzte buchung',
      'letzten buchungen',
      'transaktion',
      'welche konten',
      'meine konten',
      'konten',
      'transaction',
      'my accounts'
    ])) {
      return _accounts(s);
    }
    if (_scenarioQuestion(topic, s)) return _scenario(topic, s);
    if (_has(topic, [
      'was bleibt',
      'noch ausgeben',
      'prognose',
      'bleibt',
      'monatsende',
      'left',
      'end of the month',
      'forecast',
      'free this month'
    ])) return _forecast(s);
    if (_goalQuestion(topic)) return _goals(s);
    if (_has(topic, [
      'abo',
      'vertr',
      'fixkost',
      'subscri',
      'contract',
      'fixed cost'
    ])) return _contracts(s);
    if (_has(topic, [
      'leisten',
      'urlaub',
      'kaufen',
      'sparziel',
      'zurücklegen',
      'afford',
      'holiday',
      'buy',
      'savings goal'
    ])) return _afford(topic, s);
    if (_has(topic, ['spar', 'save'])) return _save(s);
    if (_has(topic, ['budget'])) return _budgets(s);
    if (_has(topic, [
      'depot',
      'aktie',
      'etf',
      'invest',
      'anlage',
      'portfolio',
      'stock'
    ])) return _depot(s);
    if (_has(topic, [
      'meisten',
      'wofür',
      'ausgegeben',
      'ausgaben',
      'kategorie',
      'spend',
      'spent'
    ])) return _spending(s);
    return _overview(s);
  }

  static String? _priorUser(List<({bool fromUser, String text})>? history) {
    if (history == null || history.length < 2) return null;
    for (var i = history.length - 2; i >= 0; i--) {
      if (history[i].fromUser && history[i].text.trim().isNotEmpty)
        return history[i].text;
    }
    return null;
  }

  static bool _followUp(String q) {
    if (q.length <= 28 &&
        RegExp(r'^(und|warum|wieso|wie viel|wieviel|genau|davon|dazu|nochmal|mehr dazu|was meinst|and|why|how much|'
                r'what do you mean|tell me more|more on that)\b')
            .hasMatch(q)) {
      return true;
    }
    return const {
      'und?',
      'warum?',
      'wieso?',
      'genau?',
      'davon?',
      'and?',
      'why?',
      'really?',
      'more?'
    }.contains(q);
  }

  static String _categories(FinanceSnapshot s) {
    final n = CategoryCoach.miscCount();
    if (n == 0) return tr('Nichts liegt in Sonstiges.');
    final auto = CategoryCoach.autoFixes(limit: 5);
    final left = CategoryCoach.leftovers(limit: 5);
    final lines = <String>[
      tr('**{n}** Buchungen liegen in Sonstiges.', {'n': n}),
      if (auto.isNotEmpty) ...[
        '',
        tr('So würde ich zuordnen. Sag **„Sonstiges aufräumen“**:'),
        for (final p in auto)
          '- ${p.sample}: **${tr(p.category)}** (${p.count}×)',
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
      _has(q, [
        'sparziel',
        'sparziele',
        'mein ziel',
        'meine ziele',
        'ziele',
        'my goal',
        'savings goals',
        'goals'
      ]) &&
      !_has(q, [
        'leisten',
        'kaufen',
        'urlaub',
        'zurücklegen',
        'afford',
        'buy',
        'holiday',
        'put aside'
      ]);

  static bool _has(String q, List<String> words) => words.any(q.contains);

  static String _eur(int cents) => Money.format(cents);

  static List<MapEntry<String, int>> _top(Map<String, int> m, int n) =>
      (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(n)
          .toList();

  static String _spending(FinanceSnapshot s) {
    final m = s.current;
    if (m.expenses == 0)
      return tr('Diesen Monat hast du noch keine Ausgaben erfasst.');
    final lines = [
      for (final e in _top(m.byCategory, 3))
        '- ${tr(e.key)}: **${_eur(e.value)}** (${(e.value / m.expenses * 100).round()} %)'
    ];
    final merchant = s.topMerchants.isEmpty
        ? ''
        : tr(' Am meisten an **{x}** ({y}).', {
            'x': s.topMerchants.first.name,
            'y': _eur(s.topMerchants.first.cents)
          });
    return tr('**{x}** ausgegeben diesen Monat, vor allem:\n{y}{merchant}',
        {'x': _eur(m.expenses), 'y': lines.join('\n'), 'merchant': merchant});
  }

  // categories clearly above their usual level this month (at least 10 €
  // and 15 % more), biggest first; small wobbles are no saving tip
  static List<MapEntry<String, int>> overUsual(FinanceSnapshot s) {
    final avg = s.avgByCategory;
    final over = <MapEntry<String, int>>[];
    s.current.byCategory.forEach((k, v) {
      final usual = avg[k] ?? 0;
      final diff = v - usual;
      if (usual > 0 && diff >= 1000 && diff >= usual * 0.15)
        over.add(MapEntry(k, diff));
    });
    return over..sort((a, b) => b.value.compareTo(a.value));
  }

  static String _save(FinanceSnapshot s) {
    final avg = s.avgByCategory;
    final over = overUsual(s);

    final tips = <String>[];
    for (final e in over.take(2)) {
      tips.add(tr('**{x}** liegt {y} über einem üblichen Monat.',
          {'x': tr(e.key), 'y': _eur(e.value)}));
    }
    final subs =
        s.contracts.where((c) => c.category == 'Unterhaltung').toList();
    if (subs.isNotEmpty) {
      final sum = subs.fold<int>(0, (a, c) => a + c.monthlyCents);
      tips.add(tr('**Abos** ({x}): {y} im Monat, {z} im Jahr. Brauchst du alle?',
          {
            'x': subs.map((c) => c.name).join(', '),
            'y': _eur(sum),
            'z': _eur(sum * 12)
          }));
      final tip = subs
          .map((c) => SubTips.forName(c.name))
          .whereType<SubTip>()
          .firstOrNull;
      if (tip != null) tips.add(tip.text);
    }
    if (tips.isEmpty) {
      final top = _top(avg, 1);
      if (top.isEmpty)
        return tr(
            'Dafür fehlt noch Verlauf. Ein paar Wochen Ausgaben reichen.');
      tips.add(tr(
          '**{x}** ist der größte Posten, etwa {y} im Monat. 10 % weniger sind {z}.',
          {
            'x': tr(top.first.key),
            'y': _eur(top.first.value),
            'z': _eur(top.first.value ~/ 10)
          }));
    }
    return '${tips.join(' ')}\n\n${tr('Nächster Schritt: Budget für die größte Kategorie.')}';
  }

  static String _afford(String q, FinanceSnapshot s) {
    final surplus = s.avgIncome - s.avgExpenses;
    final match = RegExp(r'(\d[\d.]*)').firstMatch(q);
    final target = match == null
        ? null
        : int.tryParse(match.group(1)!.replaceAll('.', ''));
    if (s.past.isEmpty)
      return tr('Dafür fehlt mindestens ein voller Monat Daten.');
    if (surplus <= 0) {
      return tr('**{x} mehr** gehen im Schnitt raus, als reinkommt.',
          {'x': _eur(-surplus)});
    }
    final base = tr(
        '**{x}** bleiben im Monat (rein {y}, raus {z}).',
        {'x': _eur(surplus), 'y': _eur(s.avgIncome), 'z': _eur(s.avgExpenses)});
    if (target == null || target <= 0) {
      return tr(
          '{base}\n\nNenn einen Betrag, dann sage ich, wie lange es dauert.',
          {'base': base});
    }
    final cents = target * 100;
    final months = (cents / surplus).ceil();
    final light = _light(cents, s);
    final buffer = s.balanceCents - cents;
    final lines = <String>[
      if (light != null) light,
      tr('{base} Für **{x}** etwa **{months} {y}**.', {
        'base': base,
        'x': _eur(cents),
        'months': months,
        'y': months == 1 ? tr('Monat') : tr('Monate')
      }),
      tr('Vom Kontostand blieben {x}{y}', {
        'x': _eur(buffer),
        'y': buffer < s.avgExpenses
            ? tr(', weniger als ein Monat Ausgaben.')
            : '.'
      }),
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
          ? tr('Diesen Monat danach noch **{x}** frei, etwa {y} am Tag.', {
              'x': _eur(free),
              'y': _eur(cmp.sim.perDayCents)
            })
          : tr('Diesen Monat **{x} über** dem Plan.', {'x': _eur(-free)}));
    }
    return lines.join('\n');
  }

  // the same traffic light as the agent's „leisten“ tool, for this month
  static String? _light(int cents, FinanceSnapshot s) {
    final f = s.forecast;
    if (f == null) return null;
    final target = s.emergencyTargetCents;
    final r = Affordability.check(
      amountCents: cents,
      freeCents: f.freeCents,
      goalsMonthCents: f.goalsCents,
      surplusCents: s.avgIncome - s.avgExpenses,
      spareSavingsCents: target == null
          ? 0
          : (s.emergencyHaveCents - target).clamp(0, 1 << 40),
    );
    return switch (r.light) {
      'gruen' => tr(
          '🟢 **Grün:** Das geht aus dem freien Geld, mit Puffer.'),
      'gelb' =>
          tr('🟡 **Gelb:** Nur mit weniger Sparen oder aus Erspartem.'),
      _ => tr('🔴 **Rot:** Das ginge an den Notgroschen.'),
    };
  }

  static String _contracts(FinanceSnapshot s) {
    if (s.contracts.isEmpty)
      return tr(
          'Noch keine festen Verträge. Dafür brauche ich drei Monate gleicher Zahlungen.');
    final total = s.contracts.fold<int>(0, (a, c) => a + c.monthlyCents);
    final lines = [
      for (final c in s.contracts.take(6))
        '- ${c.name}: ${_eur(c.monthlyCents)}'
    ];
    return tr(
        '**{y}** im Monat für **{x}** feste Zahlungen ({z} im Jahr):\n{a}',
        {
          'x': s.contracts.length,
          'y': _eur(total),
          'z': _eur(total * 12),
          'a': lines.join('\n')
        });
  }

  static String _budgets(FinanceSnapshot s) {
    if (s.budgets.isEmpty)
      return tr(
          'Noch keine Budgets.\n\nNächster Schritt: Unter Budgets im Konto eins anlegen.');
    final lines = [
      for (final b in s.budgets)
        tr('- {x}: {y} von {z}{a}', {
          'x': tr(b.category),
          'y': _eur(b.spentCents),
          'z': _eur(b.limitCents),
          'a': b.spentCents > b.limitCents
              ? tr(' – **überschritten**')
              : ' (${b.percentUsed} %)'
        })
    ];
    return tr('Noch **{x}** Tage im Monat:\n{y}',
        {'x': s.daysLeftInMonth, 'y': lines.join('\n')});
  }

  static String _depot(FinanceSnapshot s) {
    if (s.holdings.isEmpty) return tr('Noch keine Depot-Positionen.');
    final invested = s.holdings.fold<int>(0, (a, h) => a + h.investedCents);
    final gain = s.depotCents - invested;
    final biggest = (s.holdings.toList()
          ..sort((a, b) => b.valueCents.compareTo(a.valueCents)))
        .first;
    return tr(
        '**{x}** im Depot, {y} {z} auf {a}. Größte Position: {b} ({c} %).',
        {
          'x': _eur(s.depotCents),
          'y': gain >= 0 ? tr('ein Plus') : tr('ein Minus'),
          'z': _eur(gain.abs()),
          'a': _eur(invested),
          'b': biggest.name,
          'c': (biggest.valueCents / s.depotCents * 100).round()
        });
  }

  static String _goals(FinanceSnapshot s) {
    if (s.goals.isEmpty)
      return tr(
          'Noch keine Sparziele.\n\nNächster Schritt: Unter Sparziele anlegen.');
    final surplus = s.avgIncome - s.avgExpenses;
    final lines = [
      for (final g in s.goals.take(6))
        tr('- {x} {y}: {z} von {a} ({b} %). {c}', {
          'x': g.emoji,
          'y': g.name,
          'z': _eur(g.savedCents),
          'a': _eur(g.targetCents),
          'b': (g.progress * 100).round(),
          'c': GoalsService.plan(g, avgSurplusCents: surplus, now: s.today).text
        })
    ];
    return lines.join('\n');
  }

  static String _wealth(FinanceSnapshot s) {
    final net = s.balanceCents + s.depotCents - s.debtCents;
    final parts = <String>[
      tr('**{x}** netto. Konten {y}, Depot {z}{a}.', {
        'x': _eur(net),
        'y': _eur(s.balanceCents),
        'z': _eur(s.depotCents),
        'a': s.debtCents > 0
            ? tr(', Schulden {x}', {'x': _eur(s.debtCents)})
            : '',
      }),
    ];
    final mid = <String>[
      if (s.savingsRatePercent != null)
        tr('Sparquote {x} %.', {'x': s.savingsRatePercent}),
      if (s.emergencyTargetCents != null)
        tr('Notgroschen {x} von {y}.', {
          'x': _eur(s.emergencyHaveCents),
          'y': _eur(s.emergencyTargetCents!)
        })
      else if (s.emergencyHaveCents > 0)
        tr('Auf Sparkonten {x}.', {'x': _eur(s.emergencyHaveCents)}),
    ];
    if (mid.isNotEmpty) parts.add(mid.join(' '));
    if (s.debts.isNotEmpty) {
      parts.add(tr('Schulden: {x}.', {
        'x': s.debts
            .take(4)
            .map((d) =>
                '${d.name} ${_eur(d.cents)}${d.rateLabel == null ? '' : ' · ${d.rateLabel}'}')
            .join(', ')
      }));
    }
    final tail = <String>[
      if (s.policies.isNotEmpty)
        tr('Versicherungen: {x}, {y} im Monat.', {
          'x': s.policies.take(4).map((p) => p.name).join(', '),
          'y': _eur(s.policies.fold<int>(0, (a, p) => a + p.monthlyCents))
        }),
      if (s.runwayMonths != null)
        tr('Reichweite etwa {x} Monate.', {'x': s.runwayMonths}),
    ];
    if (tail.isNotEmpty) parts.add(tail.join(' '));
    return parts.join(' ');
  }

  static String _insurance(FinanceSnapshot s) {
    final r = InsuranceCheck.check([
      ...s.policies.map((p) => p.name),
      ...s.contracts.map((c) => c.name),
    ]);
    if (r.found.isEmpty) {
      return tr(
          'Keine Versicherung erkannt. Privathaftpflicht zuerst.\n\nNächster Schritt: Unter Vermögen eintragen.');
    }
    final listed = [
      for (final f in r.found.take(6))
        '- ${f.name} (${InsuranceCheck.label(f.type)})'
    ].join('\n');
    final notes = InsuranceCheck.notes(r);
    final extra = notes.isEmpty
        ? tr('Privathaftpflicht ist da. Keine doppelte Deckung erkannt.')
        : notes.map((n) => '- $n').join('\n');
    return tr('Versicherungs-Check:\n{x}\n\n{y}', {'x': listed, 'y': extra});
  }

  static String _vorsorge(FinanceSnapshot s) {
    final v = s.vorsorge;
    if (v == null) {
      return tr(
          'Altersvorsorge ist noch nicht eingerichtet.\n\nNächster Schritt: „Vorsorge einrichten“.');
    }
    if (v.gapClosed) {
      return tr(
          '**{x}** Wunschrente im Monat ist gedeckt. Orientierung, keine Beratung.',
          {'x': _eur(v.input.desiredNetCents)});
    }
    return tr(
        '**{z}** fehlen im Monat, noch **{y} Jahre** bis {x}. Etwa {a} extra im Monat (gesetzlich {b}, Kapital {c}). Orientierung, keine Beratung.',
        {
          'x': v.input.retireAge,
          'y': v.yearsLeft,
          'z': _eur(v.gapMonthlyCents),
          'a': _eur(v.saveExtraMonthlyCents),
          'b': _eur(v.input.statutoryCents),
          'c': _eur(v.capitalCents)
        });
  }

  static String _splits(FinanceSnapshot s) {
    if (s.splits.isEmpty) return tr('Noch keine geteilten Ausgaben.');
    final lines = [
      for (final g in s.splits.take(5))
        '- ${g.name}: ${g.myCents == 0 ? tr('ausgeglichen') : g.myCents > 0 ? tr('du bekommst {x}', {
                'x': _eur(g.myCents)
              }) : tr('du schuldest {x}', {'x': _eur(-g.myCents)})}'
    ];
    return lines.join('\n');
  }

  static String _recurring(FinanceSnapshot s) {
    final rules = s.recurring.where((r) => r.active).toList();
    if (rules.isEmpty)
      return tr('Keine aktiven wiederkehrenden Buchungen.');
    final lines = [
      for (final r in rules.take(6))
        tr('- {x}: {y} {z}{a} · nächstes {b}', {
          'x': r.title,
          'y': _eur(r.cents),
          'z': tr(r.interval),
          'a': r.income ? tr(' (Einnahme)') : '',
          'b': _date(r.next)
        })
    ];
    return lines.join('\n');
  }

  static String _accounts(FinanceSnapshot s) {
    final accounts = s.accounts.isEmpty
        ? tr('**{x}** Kontostand.', {'x': _eur(s.balanceCents)})
        : s.accounts
            .map((a) => '**${_eur(a.cents)}** · ${a.name} (${tr(a.art)})')
            .join('\n');
    final recent = [
      for (final t in s.recent.take(5))
        '- ${t.date}: ${t.note} ${t.cents < 0 ? '−' : '+'}${_eur(t.cents.abs())} (${t.account})'
    ];
    final tail = recent.isEmpty
        ? ''
        : tr('\n\nLetzte Buchungen:\n{x}', {'x': recent.join('\n')});
    return '$accounts$tail';
  }

  // "Was wäre ohne Netflix?" / "wenn ich 200 ausgebe", same formula as the sheet
  static bool _scenarioQuestion(String q, FinanceSnapshot s) {
    if (_has(q, ['was wäre', 'wenn ich', 'what if'])) return true;
    if (!_has(q, ['kündig', 'ohne', 'cancel', 'without', 'drop'])) return false;
    return s.contracts.any((c) => q.contains(c.name.toLowerCase()));
  }

  static String _scenario(String q, FinanceSnapshot s) {
    if (s.forecast == null)
      return tr('Dafür fehlen ein paar volle Monate mit Einnahmen.');
    final named =
        s.contracts.where((c) => q.contains(c.name.toLowerCase())).toList();
    final match = RegExp(r'(\d[\d.]*)').firstMatch(q);
    final euros = match == null
        ? null
        : int.tryParse(match.group(1)!.replaceAll('.', ''));

    late final ForecastOverrides overrides;
    late final String label;
    if (named.isNotEmpty) {
      final c = named.first;
      overrides =
          ForecastOverrides(excludedContractKeys: {Merchant.key(c.name)});
      label = tr(
          'ohne **{x}** ({y}/Monat)', {'x': c.name, 'y': _eur(c.monthlyCents)});
    } else if (euros != null && euros > 0) {
      overrides = ForecastOverrides(oneTimeSpentCents: euros * 100);
      label = tr('mit einem Kauf von **{x}**', {'x': _eur(euros * 100)});
    } else if (s.contracts.isNotEmpty) {
      final tip = s.contracts.take(3).map((c) => c.name).join(', ');
      return tr(
          'Sag zum Beispiel „Was wäre ohne {x}?“ oder nenn einen Betrag. Abos: {tip}.',
          {'x': s.contracts.first.name, 'tip': tip});
    } else {
      return tr(
          'Noch keine Abos erkannt. Zum Beispiel: „Was wäre, wenn ich 200 € ausgebe?“');
    }

    final cmp = ScenarioService.compare(
      DB.getTx(),
      overrides: overrides,
      goals: GoalsService.all(),
      balanceCents: s.balanceCents,
      now: s.today,
    );
    if (cmp == null)
      return tr('Dafür fehlen ein paar volle Monate mit Einnahmen.');
    final delta = cmp.deltaFree;
    final deltaLine = delta == 0
        ? tr('Am freien Betrag ändert sich nichts.')
        : delta > 0
            ? tr('Das wären **{x} mehr** frei ({y}/Tag).',
                {'x': _eur(delta), 'y': _eur(cmp.deltaPerDay)})
            : tr('Das wären **{x} weniger** frei ({y}/Tag).',
                {'x': _eur(-delta), 'y': _eur(-cmp.deltaPerDay)});
    return tr('**{x}** frei. Szenario {label}: **{y}**. {delta}', {
      'x': _eur(cmp.base.freeCents),
      'label': label,
      'y': _eur(cmp.sim.freeCents),
      'delta': deltaLine
    });
  }

  static String _forecast(FinanceSnapshot s) {
    final f = s.forecast;
    if (f == null)
      return tr('Dafür fehlen ein paar volle Monate mit Einnahmen.');
    final tempo = switch (f.pace) {
      ForecastPace.relaxed => tr('entspannt'),
      ForecastPace.tight => tr('knapp'),
      ForecastPace.over => tr('über dem Plan'),
    };
    final due = f.due.isEmpty
        ? ''
        : tr(' Noch fällig: {x}.', {
            'x': f.due
                .take(3)
                .map((d) => '${d.name} ${_eur(d.cents)}')
                .join(', ')
          });
    return tr(
        '**{x}** bis Monatsende, etwa {y} am Tag. Tempo: {tempo}.{due}',
        {
          'x': _eur(f.freeCents),
          'y': _eur(f.perDayCents),
          'tempo': tempo,
          'due': due
        });
  }

  static String _plus(FinanceSnapshot s) {
    final p = s.plus;
    if (p.active) {
      final trial = p.trial && p.bis != null
          ? tr(' Testphase bis {x}.', {'x': _date(p.bis!)})
          : '';
      final end = p.cancelled && p.bis != null
          ? tr(' Gekündigt, nutzbar bis {x}.', {'x': _date(p.bis!)})
          : '';
      return tr('**Plus ist aktiv** ({x}).{trial}{end}',
          {'x': tr(p.plan ?? 'monatlich'), 'trial': trial, 'end': end});
    }
    final left = p.fragenRest == null
        ? ''
        : tr('Noch {x} Gratis-Fragen und {y} Beleg-Scans in diesem Monat. ',
            {'x': p.fragenRest, 'y': p.scansRest ?? 0});
    return tr('Plus ist nicht aktiv. {left}Ein Ziel ist gratis, mehr mit Plus.',
        {'left': left});
  }

  static String _date(String iso) {
    final d = DateTime.tryParse(iso);
    return d == null ? iso : Dates.full(d);
  }

  static String _overview(FinanceSnapshot s) {
    final m = s.current;
    if (s.past.isEmpty &&
        m.expenses == 0 &&
        m.income == 0 &&
        s.depotCents == 0) {
      return tr(
          'Noch wenig Verlauf.\n\nNächster Schritt: Bank verbinden oder ein paar Ausgaben erfassen.');
    }
    return tr(
        '**{x}** auf dem Konto, Depot {y}. Diesen Monat {z} rein, {a} raus.', {
      'x': _eur(s.balanceCents),
      'y': _eur(s.depotCents),
      'z': _eur(m.income),
      'a': _eur(m.expenses)
    });
  }
}

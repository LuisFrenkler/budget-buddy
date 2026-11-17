// Buddy's tools: the questions the agent may ask the app about the person's
// money. They run here on the device, on the real data, and return short
// JSON (amounts in euros, two decimals). The model never sees the bookings
// as a whole, only these answers, and every number it says has to come from
// one of them. The list and the descriptions the model reads live on the
// server (backend/lib/agent.dart); the names here must match.
import 'dart:math' as math;

import '../models/transaction.dart';
import '../utils/theme.dart';
import '../l10n/l10n.dart';
import 'buddy_proposals.dart';
import 'affordability.dart';
import 'booking_text.dart';
import 'debt_plan.dart';
import 'emergency_plan.dart';
import 'net_salary.dart';
import 'oddities.dart';
import 'income_sources.dart';
import 'installments.dart';
import 'insurance_check.dart';
import 'overdraft.dart';
import 'payslip_history.dart';
import 'periodic_payments.dart';
import 'sub_tips.dart';
import 'tax_estimate.dart';
import 'buddy_service.dart';
import 'db.dart';

class BuddyTools {
  final List<Transaction> tx;
  // the summary the offline Buddy uses too (konten, sparziele, prognose …)
  final Map<String, dynamic> snapshot;
  final DateTime today;
  // what this answer proposes (cards) and shows (charts); the chat puts them
  // under the answer
  final proposals = <BuddyProposal>[];
  final charts = <BuddyChart>[];
  // which tools this answer used, for feedback
  final used = <String>[];

  BuddyTools({required this.tx, required this.snapshot, required DateTime now})
      : today = DateTime(now.year, now.month, now.day);

  // the tools on this device, from what is stored now
  factory BuddyTools.device() => BuddyTools(
        tx: DB.getTx(),
        snapshot: BuddyService.snapshot().toJson(),
        now: DateTime.now(),
      );

  static const names = {
    'konten',
    'ausgaben',
    'einnahmen',
    'buchungen_suchen',
    'monatsverlauf',
    'vertraege_und_abos',
    'monatsprognose',
    'ziele_und_vermoegen',
    'was_waere_wenn',
    'sparplan',
    'rechner',
    'budget_vorschlagen',
    'sparziel_vorschlagen',
    'kuendigung_vorbereiten',
    'kuendigungsfrist',
    'brutto_netto',
    'auffaelligkeiten',
    'steuer_schaetzung',
    'kategorie_vorschlagen',
    'erinnerung_vorschlagen',
    'zuruecklegen_vorschlagen',
    'notgroschen',
    'leisten',
    'buchung_erklaeren',
    'versicherungen_pruefen',
    'jahreszahlungen',
    'schulden_plan',
    'diagramm',
  };

  // Runs one tool. A bad input or a failure comes back as {"fehler": …}, so
  // the model can say what is missing instead of guessing.
  Map<String, dynamic> run(String name, Map<String, dynamic> input) {
    used.add(name);
    try {
      return switch (name) {
        'konten' => _konten(),
        'ausgaben' => _ausgaben(input),
        'einnahmen' => _einnahmen(input),
        'buchungen_suchen' => _buchungen(input),
        'monatsverlauf' => _monatsverlauf(input),
        'vertraege_und_abos' => _vertraege(),
        'monatsprognose' => _prognose(),
        'ziele_und_vermoegen' => _ziele(),
        'was_waere_wenn' => _wasWaereWenn(input),
        'sparplan' => _sparplan(input),
        'rechner' => {
            'ergebnis': _round(Calculator.eval('${input['ausdruck'] ?? ''}'))
          },
        'budget_vorschlagen' => _propose(BuddyProposal.budget(input)),
        'sparziel_vorschlagen' =>
          _propose(BuddyProposal.goal(input, today: today)),
        'kuendigung_vorbereiten' => _propose(BuddyProposal.cancel(input)),
        'kuendigungsfrist' => _frist(input),
        'zuruecklegen_vorschlagen' => _propose(BuddyProposal.save(input)),
        'brutto_netto' => _bruttoNetto(input),
        'auffaelligkeiten' => _auffaelligkeiten(),
        'steuer_schaetzung' => _steuer(input),
        'notgroschen' => _notgroschen(),
        'leisten' => _leisten(input),
        'buchung_erklaeren' => _erklaeren(input),
        'versicherungen_pruefen' => _versicherungen(),
        'jahreszahlungen' => _jahreszahlungen(),
        'schulden_plan' => _schuldenPlan(input),
        'kategorie_vorschlagen' => _propose(BuddyProposal.category(input)),
        'erinnerung_vorschlagen' => _propose(BuddyProposal.reminder(input)),
        'diagramm' => _diagramm(input),
        _ => {'fehler': 'Unbekanntes Werkzeug $name'},
      };
    } on FormatException catch (e) {
      return {'fehler': e.message};
    } catch (e) {
      return {'fehler': 'Das ging gerade nicht: $e'};
    }
  }

  // a card under the answer; nothing is stored until the person confirms
  Map<String, dynamic> _propose(BuddyProposal p) {
    if (proposals.length >= 3)
      return {'fehler': 'Höchstens drei Vorschläge pro Antwort.'};
    if (proposals.any((x) => x.kind == p.kind && x.title == p.title)) {
      return {'karte': 'schon gezeigt', 'titel': p.title};
    }
    proposals.add(p);
    return {
      'karte': 'gezeigt',
      'titel': p.title,
      'details': p.detail,
      'hinweis':
          'Die Person sieht jetzt eine Karte mit „${p.confirm}“. Gespeichert ist noch nichts.',
    };
  }

  Map<String, dynamic> _diagramm(Map<String, dynamic> input) {
    if (charts.length >= 2)
      return {'fehler': 'Höchstens zwei Diagramme pro Antwort.'};
    switch ('${input['art'] ?? ''}') {
      case 'monate':
        final n = ((input['monate'] as num?)?.toInt() ?? 6).clamp(2, 12);
        final months = _months(n);
        const names = [
          'Jan',
          'Feb',
          'Mär',
          'Apr',
          'Mai',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Okt',
          'Nov',
          'Dez'
        ];
        charts.add(BuddyChart(ChartKind.months, tr('Einnahmen und Ausgaben'), [
          for (final m in months)
            (label: tr(names[m.month.month - 1]), a: m.income, b: m.spent)
        ]));
        return {'diagramm': 'gezeigt', 'art': 'monate', 'monate': n};
      case 'kategorien':
        final r = _ausgaben({'von': input['von'], 'bis': input['bis']});
        final rows = (r['nachKategorie'] as List).take(6).toList();
        charts.add(
            BuddyChart(ChartKind.categories, tr('Ausgaben nach Kategorie'), [
          for (final c in rows)
            (
              label: tr(c['name'].toString()),
              a: ((c['summe'] as num) * 100).round(),
              b: 0
            )
        ]));
        return {
          'diagramm': 'gezeigt',
          'art': 'kategorien',
          'summe': r['summe']
        };
      case 'sparplan':
        final r = _sparplan({
          'betrag': input['betrag'],
          'bis': input['bis_monat'],
          'schon_gespart': input['schon_gespart']
        });
        if (r['fehler'] != null) return r;
        final months = r['monate'] as int;
        final rate = ((r['rateProMonat'] as num) * 100).round();
        final have = ((((input['schon_gespart'] as num?) ?? 0)) * 100).round();
        const names = [
          'Jan',
          'Feb',
          'Mär',
          'Apr',
          'Mai',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Okt',
          'Nov',
          'Dez'
        ];
        final target = ((r['zielbetrag'] as num) * 100).round();
        const long = [
          'Januar',
          'Februar',
          'März',
          'April',
          'Mai',
          'Juni',
          'Juli',
          'August',
          'September',
          'Oktober',
          'November',
          'Dezember'
        ];
        final end = DateTime(today.year, today.month + months - 1);
        charts.add(BuddyChart(
            ChartKind.plan,
            tr('Sparplan bis {m} {y}',
                {'m': tr(long[end.month - 1]), 'y': end.year}),
            [
              for (var i = 0; i < months.clamp(1, 12); i++)
                (
                  label: tr(names[(today.month - 1 + i) % 12]),
                  a: (have + rate * (i + 1)).clamp(0, target),
                  b: target,
                )
            ]));
        return {
          'diagramm': 'gezeigt',
          'art': 'sparplan',
          'rateProMonat': r['rateProMonat'],
          'monate': months
        };
      case 'abrechnung':
        final c = PayslipHistory.chart();
        if (c == null) {
          return {
            'fehler': tr('Noch keine gespeicherten Abrechnungen. Schick Ahead ein Foto davon.')
          };
        }
        charts.add(c);
        return {
          'diagramm': 'gezeigt',
          'art': 'abrechnung',
          'monate': c.rows.length,
          'hinweis': tr('Grau ist Brutto, Kupfer Netto, dunkelgrau die Abzüge.'),
        };
    }
    throw const FormatException(
        'art muss monate, kategorien, sparplan oder abrechnung sein');
  }

  // A few numbers that go with every question, so simple ones ("wie viel ist
  // frei?") need no extra step. Everything else still goes through tools.
  Map<String, dynamic> kurzinfo() {
    const days = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag'
    ];
    final f = snapshot['prognose'] as Map?;
    return {
      'heute': '${days[today.weekday - 1]}, ${_day(today)}',
      if (snapshot['kontostand'] != null) 'summeKonten': snapshot['kontostand'],
      if (snapshot['tageBisMonatsende'] != null)
        'tageBisMonatsende': snapshot['tageBisMonatsende'],
      if (f?['vorhanden'] == true) ...{
        'freiBisMonatsende': f!['freiBisMonatsende'],
        'proTag': f['proTag'],
      },
    };
  }

  // --- helpers --------------------------------------------------------------

  static double _eur(int cents) => cents / 100;
  static num _round(num v) => (v * 100).round() / 100;
  static String _day(DateTime d) => d.toIso8601String().substring(0, 10);

  DateTime _date(dynamic raw, String field) {
    final s = '${raw ?? ''}';
    final d = DateTime.tryParse(s);
    if (d == null)
      throw FormatException('$field fehlt oder ist kein Datum (JJJJ-MM-TT)');
    return DateTime(d.year, d.month, d.day);
  }

  bool _within(Transaction t, DateTime from, DateTime to) {
    final d = DateTime(t.date.year, t.date.month, t.date.day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  static String _title(Transaction t) {
    final n = t.note?.trim() ?? '';
    return n.isEmpty ? t.category : n;
  }

  // what ends up in a month's spending: real spending minus refunds, no transfers
  Iterable<Transaction> get _counted =>
      tx.where((t) => Categories.counts(t.category));

  // --- the tools ------------------------------------------------------------

  Map<String, dynamic> _konten() => {
        'stand': _day(today),
        'konten': snapshot['konten'] ?? const [],
        'summeKonten': snapshot['kontostand'],
        'depotwert': snapshot['depotwert'],
        'gesamtvermoegen': snapshot['gesamtvermoegen'],
      };

  ({int total, Map<String, int> groups, int count}) _spend(DateTime from,
      DateTime to, String by, String? category, String? merchant) {
    final groups = <String, int>{};
    var total = 0, count = 0;
    final cat = category?.trim().toLowerCase();
    final m = merchant?.trim().toLowerCase();
    for (final t in _counted) {
      if (!t.isSpending || !_within(t, from, to)) continue;
      if (cat != null && cat.isNotEmpty && t.category.toLowerCase() != cat)
        continue;
      if (m != null && m.isNotEmpty && !_title(t).toLowerCase().contains(m))
        continue;
      final key = by == 'haendler' ? _title(t) : t.category;
      groups[key] = (groups[key] ?? 0) + t.spendCents;
      total += t.spendCents;
      count++;
    }
    return (total: total, groups: groups, count: count);
  }

  Map<String, dynamic> _ausgaben(Map<String, dynamic> input) {
    final from = _date(input['von'], 'von');
    final to = _date(input['bis'], 'bis');
    if (to.isBefore(from)) throw const FormatException('bis liegt vor von');
    final by = input['gruppierung'] == 'haendler' ? 'haendler' : 'kategorie';
    final category = input['kategorie'] as String?;
    final merchant = input['haendler'] as String?;
    final now = _spend(from, to, by, category, merchant);
    // the same number of days just before, for "mehr oder weniger als sonst"
    final days = to.difference(from).inDays + 1;
    final prevTo = from.subtract(const Duration(days: 1));
    final prevFrom = prevTo.subtract(Duration(days: days - 1));
    final before = _spend(prevFrom, prevTo, by, category, merchant);
    final ranked = now.groups.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'zeitraum': {'von': _day(from), 'bis': _day(to), 'tage': days},
      'summe': _eur(now.total),
      'anzahlBuchungen': now.count,
      by == 'haendler' ? 'nachHaendler' : 'nachKategorie': [
        for (final e in ranked.take(15))
          {
            'name': e.key,
            'summe': _eur(e.value),
            'anteilProzent':
                now.total == 0 ? 0 : (e.value * 100 / now.total).round()
          }
      ],
      if (ranked.length > 15) 'weitere': ranked.length - 15,
      'vergleich': {
        'von': _day(prevFrom),
        'bis': _day(prevTo),
        'summe': _eur(before.total),
        'differenz': _eur(now.total - before.total),
      },
    };
  }

  Map<String, dynamic> _einnahmen(Map<String, dynamic> input) {
    final from = _date(input['von'], 'von');
    final to = _date(input['bis'], 'bis');
    final groups = <String, int>{};
    var total = 0;
    for (final t in _counted) {
      if (!t.isEarning || !_within(t, from, to)) continue;
      final key = _title(t);
      groups[key] = (groups[key] ?? 0) + t.amountCents;
      total += t.amountCents;
    }
    final ranked = groups.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return {
      'zeitraum': {'von': _day(from), 'bis': _day(to)},
      'summe': _eur(total),
      'nachQuelle': [
        for (final e in ranked.take(12)) {'name': e.key, 'summe': _eur(e.value)}
      ],
    };
  }

  Map<String, dynamic> _buchungen(Map<String, dynamic> input) {
    final text = '${input['text'] ?? ''}'.trim().toLowerCase();
    final from = input['von'] == null ? null : _date(input['von'], 'von');
    final to = input['bis'] == null ? null : _date(input['bis'], 'bis');
    final kind = '${input['art'] ?? 'alle'}';
    final min = (input['mindestbetrag'] as num?)?.toDouble();
    final limit = ((input['limit'] as num?)?.toInt() ?? 15).clamp(1, 25);
    final hits = [
      for (final t in tx)
        if ((text.isEmpty ||
                _title(t).toLowerCase().contains(text) ||
                t.category.toLowerCase().contains(text)) &&
            (from == null || !t.date.isBefore(from)) &&
            (to == null ||
                !DateTime(t.date.year, t.date.month, t.date.day).isAfter(to)) &&
            (kind == 'alle' || (kind == 'ausgabe') == !t.isIncome) &&
            (min == null || t.amountCents >= min * 100))
          t
    ]..sort((a, b) => b.date.compareTo(a.date));
    var sum = 0;
    for (final t in hits) {
      sum += t.isIncome ? t.amountCents : -t.amountCents;
    }
    return {
      'anzahl': hits.length,
      'summe': _eur(sum),
      'hinweis': 'summe: Einnahmen positiv, Ausgaben negativ',
      'buchungen': [
        for (final t in hits.take(limit))
          {
            'datum': _day(t.date),
            'titel': _title(t),
            'kategorie': t.category,
            'betrag': _eur(t.isIncome ? t.amountCents : -t.amountCents),
          }
      ],
      if (hits.length > limit) 'weitere': hits.length - limit,
    };
  }

  // per calendar month: earnings, spending, saved
  List<({DateTime month, int income, int spent})> _months(int n) {
    final out = <({DateTime month, int income, int spent})>[];
    for (var i = n - 1; i >= 0; i--) {
      final m = DateTime(today.year, today.month - i);
      final end = DateTime(m.year, m.month + 1, 0);
      var inc = 0, out0 = 0;
      for (final t in _counted) {
        if (!_within(t, m, end)) continue;
        if (t.isEarning) inc += t.amountCents;
        if (t.isSpending) out0 += t.spendCents;
      }
      out.add((month: m, income: inc, spent: out0));
    }
    return out;
  }

  Map<String, dynamic> _monatsverlauf(Map<String, dynamic> input) {
    final n = ((input['monate'] as num?)?.toInt() ?? 6).clamp(1, 24);
    final months = _months(n);
    return {
      'monate': [
        for (final m in months)
          {
            'monat':
                '${m.month.year}-${m.month.month.toString().padLeft(2, '0')}',
            'einnahmen': _eur(m.income),
            'ausgaben': _eur(m.spent),
            'gespart': _eur(m.income - m.spent),
            'sparquoteProzent': m.income == 0
                ? null
                : ((m.income - m.spent) * 100 / m.income).round(),
            if (m.month.year == today.year && m.month.month == today.month)
              'laufend': true,
          }
      ],
    };
  }

  Map<String, dynamic> _vertraege() {
    final contracts = (snapshot['vertraegeUndAbos'] as List?) ?? const [];
    final monthly = contracts.fold<double>(
        0, (s, c) => s + ((c as Map)['proMonat'] as num? ?? 0));
    final tips = [
      for (final c in contracts)
        if (SubTips.forName('${(c as Map)['name']}') case final t?)
          {'name': c['name'], 'guenstiger': t.ways}
    ];
    return {
      'vertraegeUndAbos': contracts,
      'summeProMonat': _round(monthly),
      if (tips.isNotEmpty) ...{
        'spartipps': tips,
        'hinweisSpartipps':
            'werbung = Abo mit Werbung, jahresabo = jährlich zahlen, teilen = Familien-/Duo-Abo, '
                'student = Studierenden-Tarif. Nenn die Möglichkeit, keine Preise: die ändern sich, die Person prüft das '
                'aktuelle Angebot.',
      },
      'dauerauftraege': snapshot['wiederkehrend'] ?? const [],
    };
  }

  // When can a contract end at the earliest? German rules for consumer
  // contracts, as an estimate: the contract itself has the exact dates.
  // - since 1 March 2022 (§ 309 Nr. 9 BGB): at most 24 months minimum term,
  //   after that cancellable any time with at most one month's notice
  // - phone and internet (§ 56 TKG, since Dec 2021): the same after the minimum term
  // - subscriptions billed monthly: usually to the end of the paid month
  // - insurance: usually three months before the end of the insurance year
  Map<String, dynamic> _frist(Map<String, dynamic> input) {
    final who = '${input['anbieter'] ?? ''}'.trim();
    if (who.isEmpty) return {'fehler': 'anbieter fehlt'};
    final contracts = [
      for (final c in (snapshot['vertraegeUndAbos'] as List?) ?? const [])
        (c as Map).cast<String, dynamic>()
    ];
    final found = contracts
        .where((c) =>
            '${c['name']}'.toLowerCase().contains(who.toLowerCase()) ||
            who.toLowerCase().contains('${c['name']}'.toLowerCase()))
        .firstOrNull;
    final art =
        '${input['art'] ?? (found == null ? 'sonstiges' : _artOf('${found['kategorie']}', '${found['name']}'))}';
    DateTime? month(String? s) {
      if (s == null || s.isEmpty) return null;
      final m = RegExp(r'^(\d{4})-(\d{2})(?:-(\d{2}))?').firstMatch(s);
      return m == null
          ? null
          : DateTime(
              int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3] ?? '1'));
    }

    final start =
        month(input['beginn'] as String?) ?? month(found?['seit'] as String?);
    final minMonths = (input['mindestlaufzeit_monate'] as num?)?.toInt();
    final next = month(found?['naechste'] as String?);
    final base = <String, dynamic>{
      'anbieter': found?['name'] ?? who,
      'erkannt': found != null,
      'art': art,
      if (start != null) 'beginn': _day(start),
      if (found != null) 'proMonat': found['proMonat'],
      if (next != null) 'naechsteZahlung': _day(next),
    };
    const hint =
        'Schätzung nach den gesetzlichen Regeln. Die genaue Frist steht im Vertrag oder im Kundenkonto. '
        'Online abgeschlossene Verträge müssen einen Knopf „Verträge hier kündigen“ haben (§ 312k BGB).';
    DateTime addMonths(DateTime d, int m) {
      final last = DateTime(d.year, d.month + m + 1, 0).day;
      return DateTime(d.year, d.month + m, d.day > last ? last : d.day);
    }

    if (art == 'versicherung') {
      return {
        ...base,
        'regel':
            'Meist zum Ende des Versicherungsjahres, mit drei Monaten Frist. Nach einer Beitragserhöhung '
                'oder einem Schaden gibt es oft ein Sonderkündigungsrecht.',
        'hinweis': hint,
      };
    }
    if (art == 'abo') {
      return {
        ...base,
        'regel':
            'Monatlich kündbar, das Abo läuft bis zum Ende des bezahlten Monats.',
        if (next != null)
          'endetFruehestens': _day(next.subtract(const Duration(days: 1))),
        if (next != null)
          'kuendigenBis': _day(next.subtract(const Duration(days: 1))),
        'hinweis': hint,
      };
    }
    final old = start != null &&
        start.isBefore(DateTime(2022, 3, 1)) &&
        art != 'handy_internet';
    if (old) {
      return {
        ...base,
        'altvertrag': true,
        'regel':
            'Vertrag von vor März 2022: Er durfte sich noch um bis zu zwölf Monate verlängern, mit bis zu drei '
                'Monaten Frist. Das genaue Datum steht im Vertrag.',
        'hinweis': hint,
      };
    }
    final months = minMonths ?? (art == 'strom_gas' ? 12 : 24);
    final minEnd = start == null ? null : addMonths(start, months);
    final noticeEnd = addMonths(today, 1);
    if (minEnd != null && minEnd.isAfter(noticeEnd)) {
      return {
        ...base,
        'mindestlaufzeitMonate': months,
        if (minMonths == null) 'mindestlaufzeitGeschaetzt': true,
        'endetFruehestens': _day(minEnd),
        'kuendigenBis': _day(addMonths(minEnd, -1)),
        'tageBisKuendigung': addMonths(minEnd, -1).difference(today).inDays,
        'regel':
            'Bis zum Ende der Mindestlaufzeit gebunden, danach monatlich kündbar.',
        'hinweis': hint,
      };
    }
    return {
      ...base,
      'endetFruehestens': _day(noticeEnd),
      'kuendigenBis': 'jederzeit',
      'regel': start == null
          ? 'Ohne Beginn geschätzt: Nach der Mindestlaufzeit ist ein Vertrag jederzeit mit einem Monat Frist kündbar.'
          : 'Die Mindestlaufzeit ist vorbei: jederzeit mit höchstens einem Monat Frist kündbar.',
      'hinweis': hint,
    };
  }

  // the tax return estimate: the saved profile, what the model learned in
  // the chat, and the bookings that may count
  Map<String, dynamic> _steuer(Map<String, dynamic> input) {
    final year = (input['jahr'] as num?)?.toInt() ?? today.year;
    var p = TaxEstimate.profile();
    double? n(String k) => (input[k] as num?)?.toDouble();
    p = p.copyWith(
      grossMonth: n('brutto_monat') ??
          (n('brutto_jahr') != null ? n('brutto_jahr')! / 12 : null),
      monthsWorked: (input['monate_gearbeitet'] as num?)?.toInt(),
      km: n('km_einfach'),
      officeDaysPerWeek: n('buerotage_pro_woche'),
      homeDaysPerWeek: n('homeoffice_tage_pro_woche'),
      taxClass: (input['steuerklasse'] as num?)?.toInt(),
      church: input['kirchensteuer'] as bool?,
    );
    final open = TaxEstimate.openYears(today);
    if (year < today.year && !open.contains(year)) {
      return {
        'jahr': year,
        'zuSpaet': true,
        'hinweis': year < NetSalary.firstYear
            ? 'Für $year kennt Ahead die Regeln nicht.'
            : 'Die freiwillige Abgabe für $year lief am ${_day(TaxEstimate.deadline(year))} ab.',
        'offeneJahre': open,
      };
    }
    // the saved profile is this year's job; an earlier year needs its own pay
    final pastWithoutPay = year < today.year && n('brutto_monat') == null && n('brutto_jahr') == null;
    if (p.grossMonth <= 0 || pastWithoutPay) {
      return {
        'fehlt': pastWithoutPay ? 'brutto_monat und monate_gearbeitet für $year' : 'brutto_monat',
        'hinweis': pastWithoutPay
            ? 'Frag nach Brutto und Monaten in $year, oder ob die Person die Lohnsteuerbescheinigung $year fotografieren will.'
            : 'Ohne Bruttogehalt keine Schätzung. Frag danach, oder ob die Person eine Abrechnung fotografieren will.',
      };
    }
    final counted = TaxEstimate.counted(tx, year);
    final receipts = counted.fold<int>(0, (s, c) => s + c.tx.amountCents) / 100;
    final r = TaxEstimate.compute(p, receipts: receipts, year: year);
    return {
      'jahr': year,
      if (year < today.year) 'abgabeBis': _day(TaxEstimate.deadline(year)),
      'offeneJahre': open,
      ...r.toJson(),
      'elster': TaxEstimate.elster(r, counted),
      'annahmen': {
        'bruttoMonat': p.grossMonth,
        'monateGearbeitet': p.monthsWorked,
        'kmEinfach': p.km,
        'buerotageProWoche': p.officeDaysPerWeek,
        'homeofficeTageProWoche': p.homeDaysPerWeek,
        'steuerklasse': p.taxClass,
      },
      'belegeAusBuchungen': [
        for (final c in counted.take(12))
          {
            'was': c.tx.note ?? c.tx.category,
            'art': c.kind,
            'betrag': c.tx.amountCents / 100
          }
      ],
      'regeln': year >= 2026
          ? 'Pendlerpauschale 0,38 € ab dem ersten km, Homeoffice 6 € am Tag bis 210 Tage, '
              'Arbeitnehmer-Pauschbetrag 1.230 €, Kontoführung 16 € pauschal.'
          : 'Pendlerpauschale 0,30 € bis km 20, 0,38 € ab km 21, '
              '${year <= 2022 ? 'Homeoffice 5 € am Tag bis 120 Tage, Arbeitnehmer-Pauschbetrag 1.200 €' : 'Homeoffice 6 € am Tag bis 210 Tage, Arbeitnehmer-Pauschbetrag 1.230 €'}, '
              'Kontoführung 16 € pauschal.',
      'hinweis': 'Schätzung, keine Steuerberatung. Die Person gibt selbst ab, kostenlos über ELSTER; die Felder unter '
          '„elster“ zeigen, was wo hinkommt. In der App unter Profil › Steuer.',
    };
  }

  // the Notgroschen goal among the saved goals, if there is one
  Map? _emergencyGoal() {
    final goals = (snapshot['sparziele'] as List?) ?? const [];
    return goals
        .whereType<Map>()
        .where((g) => RegExp(
                r'notgroschen|notfall|puffer|reserve|polster|emergency',
                caseSensitive: false)
            .hasMatch('${g['name']}'))
        .firstOrNull;
  }

  Map<String, dynamic> _notgroschen() {
    double eur(int c) => c / 100;
    final plan = EmergencyPlan.compute(tx, now: today);
    if (plan.monthlyCents <= 0) {
      return {
        'fehler':
            'Noch zu wenig Verlauf: es gibt keine Ausgaben aus den letzten drei Monaten.'
      };
    }
    final goal = _emergencyGoal();
    final onAccounts =
        ((((snapshot['vermoegen'] as Map?)?['notgroschenVorhanden']) as num?) ??
                0) *
            100;
    final inGoal = (((goal?['gespart'] as num?) ?? 0) * 100);
    final have = math.max(onAccounts, inGoal).round();
    final missing = math.max(0, plan.targetCents - have);
    final rate12 = (missing / 12 / 100).ceil() * 100;
    final out = <String, dynamic>{
      'monatImNotfall': eur(plan.monthlyCents),
      if (!plan.fromAverage) ...{
        'fixkosten': [
          for (final p in plan.fixed.take(10))
            {'name': p.name, 'betrag': eur(p.cents)}
        ],
        'lebenshaltung': [
          for (final p in plan.living)
            {'kategorie': p.name, 'betrag': eur(p.cents)}
        ],
      } else
        'grundlage':
            'Durchschnitt aller Ausgaben der letzten drei Monate (noch keine Verträge erkannt)',
      if (plan.skipped.isNotEmpty)
        'imNotfallPausierbar': [
          for (final p in plan.skipped.take(8))
            {'name': p.name, 'betrag': eur(p.cents)}
        ],
      'monate': plan.months,
      'warum': plan.irregularIncome
          ? 'Das Einkommen schwankt um mehr als ein Viertel zwischen den Monaten, deshalb sechs Monate.'
          : 'Regelmäßiges Einkommen: drei Monate reichen als Notgroschen.',
      'zielEmpfohlen': eur(plan.targetCents),
      'spanne': {
        'dreiMonate': eur(plan.lowCents),
        'sechsMonate': eur(plan.highCents)
      },
      'vorhanden': eur(have),
      'fehlt': eur(missing),
      if (missing > 0) 'rateFuer12Monate': eur(rate12),
      'sparziel': goal == null
          ? null
          : {
              'name': goal['name'],
              'ziel': goal['ziel'],
              'gespart': goal['gespart']
            },
      'hinweis':
          'Auf ein Tagesgeldkonto, getrennt vom Girokonto. Erst wenn er voll ist, langfristig anlegen.',
    };
    if (goal == null && missing > 0) {
      out['karte'] = _propose(BuddyProposal.goal({
        'name': tr('Notgroschen'),
        'betrag': plan.targetCents / 100,
        'monatlich': rate12 / 100,
      }, today: today));
    } else if (goal != null) {
      final set = (((goal['ziel'] as num?) ?? 0) * 100).round();
      if (set > 0 && (set - plan.targetCents).abs() > plan.targetCents * 0.2) {
        out['zielAbweichung'] =
            'Das gespeicherte Ziel (${goal['ziel']} €) weicht um mehr als 20 % von der Empfehlung ab. '
            'Sag das und lass die Person entscheiden; ändern kann sie es unter Sparziele.';
      }
    }
    return out;
  }

  Map<String, dynamic> _leisten(Map<String, dynamic> input) {
    double eur(int c) => c / 100;
    final amount = (((input['betrag'] as num?) ?? 0) * 100).round();
    if (amount <= 0) return {'fehler': 'betrag fehlt'};
    var months = 0;
    final m =
        RegExp(r'^(\d{4})-(\d{2})$').firstMatch('${input['monat'] ?? ''}');
    if (m != null) {
      months = (int.parse(m.group(1)!) - today.year) * 12 +
          int.parse(m.group(2)!) -
          today.month;
      if (months < 0) return {'fehler': 'monat liegt in der Vergangenheit'};
    }
    final f = snapshot['prognose'] as Map?;
    if (f?['vorhanden'] != true) {
      return {
        'fehler':
            'Noch keine Monatsprognose: Es fehlen Einnahmen oder Kontostand. Frag nach dem Kontostand.'
      };
    }
    int c(Object? v) => (((v as num?) ?? 0) * 100).round();
    final usual = _usual();
    final w = snapshot['vermoegen'] as Map?;
    final spare =
        math.max(0, c(w?['notgroschenVorhanden']) - c(w?['notgroschenZiel']));
    final r = Affordability.check(
      amountCents: amount,
      freeCents: c(f!['freiBisMonatsende']),
      goalsMonthCents: c(f['sparzieleMonat']),
      surplusCents: usual.months == 0 ? 0 : usual.income - usual.spent,
      spareSavingsCents: w?['notgroschenZiel'] == null ? 0 : spare,
      months: months,
    );
    return {
      'was': '${input['was'] ?? ''}',
      'betrag': eur(amount),
      'ampel': r.light,
      'wann': months == 0 ? 'diesen Monat' : 'in $months Monaten',
      'freiOhneEtwasAnzufassen': eur(r.roomCents),
      'freiMitSparrateUndRuecklagen': eur(r.withSavingsCents),
      'puffer': eur(Affordability.bufferCents),
      'gruende': r.reasons,
      if (r.monthsToSave != null) 'monateSparen': r.monthsToSave,
      if (r.ratePerMonthCents != null)
        'rateProMonat': eur(r.ratePerMonthCents!),
      'regeln':
          'gruen = aus dem freien Geld mit 50 € Puffer; gelb = nur mit Sparrate aussetzen oder Ersparnissen '
              'über dem Notgroschen; rot = ginge an den Notgroschen oder ins Minus. Bei gelb/rot biete ein Sparziel '
              'mit rateProMonat an (sparziel_vorschlagen).',
    };
  }

  Map<String, dynamic> _erklaeren(Map<String, dynamic> input) {
    final q = '${input['suchtext'] ?? ''}'.toLowerCase().trim();
    if (q.isEmpty) return {'fehler': 'suchtext fehlt'};
    final hits = [
      for (final t in tx)
        if ('${t.note ?? ''} ${t.raw ?? ''}'.toLowerCase().contains(q)) t
    ]..sort((a, b) => b.date.compareTo(a.date));
    if (hits.isEmpty)
      return {
        'gefunden': 0,
        'hinweis': 'Keine Buchung mit diesem Text gefunden.'
      };
    final t = hits.first;
    return {
      'gefunden': hits.length,
      'buchung': {
        'datum': _day(t.date),
        'betrag': t.amountCents / 100 * (t.isIncome ? 1 : -1),
        'titel': t.note ?? t.category,
        'kategorie': t.category,
        if (t.raw != null) 'textDerBank': t.raw,
      },
      'erklaerung':
          BookingText.explain(raw: t.raw, note: t.note, income: t.isIncome),
    };
  }

  Map<String, dynamic> _schuldenPlan(Map<String, dynamic> input) {
    int c(Object? v) => (((v as num?) ?? 0) * 100).round();
    final rates = <String, double>{
      for (final e in ((input['zinsen'] as Map?) ?? const {}).entries)
        if (e.value is num)
          '${e.key}'.toLowerCase(): (e.value as num).toDouble()
    };
    final rest = <String, int>{
      for (final e in ((input['offeneRaten'] as Map?) ?? const {}).entries)
        if (e.value is num) '${e.key}'.toLowerCase(): (e.value as num).toInt()
    };
    int? restFor(String name) {
      final n = name.toLowerCase();
      for (final e in rest.entries) {
        if (n.contains(e.key) || e.key.contains(n)) return e.value;
      }
      return null;
    }

    double? rateFor(String name) {
      final n = name.toLowerCase();
      for (final e in rates.entries) {
        if (n.contains(e.key) || e.key.contains(n)) return e.value;
      }
      return null;
    }

    final items = <DebtItem>[
      for (final d
          in (((snapshot['vermoegen'] as Map?)?['schulden'] as List?) ??
                  const [])
              .whereType<Map>())
        DebtItem('${d['name']}', c(d['betrag']),
            ratePercent:
                rateFor('${d['name']}') ?? (d['zins'] as num?)?.toDouble()),
      // running instalments: their rate is the minimum; with the number of
      // rates still open (the person knows it from the app) they get an end
      for (final r in Installments.detect(tx, now: today))
        if (r.paidCount > 0)
          DebtItem(
              r.shop == null ? r.provider : '${r.provider} (${r.shop})',
              r.monthlyCents *
                  (restFor(r.shop ?? r.provider) ?? restFor(r.provider) ?? 0),
              ratePercent: rateFor(r.provider),
              minCents: r.monthlyCents),
    ];
    final withAmount = items.where((d) => d.cents > 0).toList();
    if (withAmount.isEmpty) {
      return {
        'schulden': const [],
        if (items.isNotEmpty)
          'ratenOhneRestbetrag': [
            for (final d in items)
              {'name': d.name, 'proMonat': d.minCents / 100}
          ],
        'hinweis': 'Keine Schulden mit Betrag gespeichert. Frag nach Betrag und Zinssatz (Dispo, Kreditkarte, Kredit) '
            'oder biete an, sie unter Vermögen einzutragen. Bei Ratenkäufen: frag, wie viele Raten noch offen sind '
            '(steht in der Klarna- oder PayPal-App), und gib das unter offeneRaten mit.',
      };
    }
    final extra = c(input['extraProMonat']);
    final r = DebtPlan.compute(withAmount, extraCents: extra);
    return {
      'reihenfolge': [
        for (final s in r.order)
          {
            'name': s.name,
            'frei': 'nach ${s.month} Monaten',
            if (s.ratePercent != null) 'zins': s.ratePercent
          }
      ],
      'monateBisSchuldenfrei': r.tooSlow ? null : r.months,
      'zinsenGesamtGeschaetzt': r.interestCents / 100,
      'extraProMonat': extra / 100,
      if (r.tooSlow)
        'warnung':
            'Mit diesem Betrag sinken die Schulden nicht in 30 Jahren. Mehr pro Monat nötig oder Schuldnerberatung.',
      if (withAmount.any((d) => d.ratePercent == null))
        'ohneZinssatz': [
          for (final d in withAmount.where((d) => d.ratePercent == null)) d.name
        ],
      'regel':
          'Teuerster Zins zuerst (Lawine), ohne bekannten Zins die kleinste zuerst. Fehlt der Zins, frag danach. '
              'Bei Überforderung: kostenlose Schuldnerberatung (Verbraucherzentrale, Caritas, Diakonie).',
    };
  }

  Map<String, dynamic> _jahreszahlungen() {
    final list = PeriodicPayments.detect(tx, now: today);
    if (list.isEmpty) {
      return {
        'gefunden': const [],
        'hinweis':
            'Keine Jahres- oder Quartalszahlungen erkannt. Frag nach Kfz, Versicherungen, Rundfunkbeitrag.'
      };
    }
    final monthly = PeriodicPayments.monthly(list);
    final goals = (snapshot['sparziele'] as List?) ?? const [];
    final hasReserve = goals.whereType<Map>().any((g) =>
        RegExp(r'r[üu]cklage|jahreszahlung|versicherung', caseSensitive: false)
            .hasMatch('${g['name']}'));
    final out = <String, dynamic>{
      'gefunden': [
        for (final p in list)
          {
            'name': p.name,
            'betrag': p.cents / 100,
            'alleMonate': p.everyMonths,
            'naechste': _day(p.next),
            'proMonatZuruecklegen': p.monthlyCents / 100,
          }
      ],
      'zusammenProMonat': monthly / 100,
      'hinweis':
          'Monatlich zurücklegen, am besten per Dauerauftrag auf ein eigenes Sparziel.',
    };
    if (!hasReserve && monthly >= 1000) {
      final year =
          list.fold<int>(0, (s, p) => s + p.cents * (12 ~/ p.everyMonths));
      out['karte'] = _propose(BuddyProposal.goal({
        'name': tr('Rücklage Jahreszahlungen'),
        'betrag': year / 100,
        'monatlich': (monthly / 100).ceilToDouble(),
      }, today: today));
    }
    return out;
  }

  Map<String, dynamic> _versicherungen() {
    final contracts = [
      for (final c in (snapshot['vertraegeUndAbos'] as List?) ?? const [])
        (c as Map)
    ];
    final policies = [
      for (final p
          in (((snapshot['vermoegen'] as Map?)?['versicherungen']) as List?) ??
              const [])
        (p as Map)
    ];
    final monthly = <String, num>{
      for (final c in contracts) '${c['name']}': (c['proMonat'] as num?) ?? 0,
      for (final p in policies) '${p['name']}': (p['proMonat'] as num?) ?? 0,
    };
    final r = InsuranceCheck.check(monthly.keys);
    if (r.found.isEmpty) {
      return {
        'gefunden': const [],
        'hinweis':
            'Keine Versicherung in den Buchungen oder unter Vermögen erkannt. Frag, welche die Person hat; '
                'die Privathaftpflicht ist für fast alle die wichtigste.',
      };
    }
    return {
      'gefunden': [
        for (final f in r.found)
          {'name': f.name, 'art': f.type, 'proMonat': monthly[f.name]}
      ],
      'summeProMonat':
          _round(r.found.fold<double>(0, (s, f) => s + (monthly[f.name] ?? 0))),
      'doppelt': r.twice,
      'oftUnnoetigMitZwanzig': r.rarelyNeeded,
      'haftpflichtFehlt': r.liabilityMissing,
      'regeln': 'Allgemein, keine Beratung: Privathaftpflicht zuerst, Berufsunfähigkeit wenn vom Einkommen viel '
          'abhängt, Hausrat je nach Wert der Sachen. Handy-, Glas-, Restschuld- und Kapitallebensversicherung lohnen '
          'sich selten. Doppelte Deckung bringt nichts. Keine Anbieter oder Tarife nennen; als Frage formulieren.',
    };
  }

  Map<String, dynamic> _auffaelligkeiten() {
    double eur(int c) => c / 100;
    final doubles = Oddities.doubles(tx, now: today, days: 60);
    final fees = Oddities.fees(tx, now: today);
    return {
      'doppelteAbbuchungen': [
        for (final d in doubles)
          {
            'haendler': d.merchant,
            'betrag': eur(d.cents),
            'daten': [_day(d.first.date), _day(d.second.date)],
          }
      ],
      'bankgebuehren90Tage': [
        for (final f in fees)
          {'art': f.kind, 'summe': eur(f.cents), 'anzahl': f.count}
      ],
      'bankgebuehrenImJahrGeschaetzt': eur(Oddities.yearly(fees)),
      'ratenkaeufe': [
        for (final r in Installments.detect(tx, now: today))
          {
            'anbieter': r.provider,
            if (r.shop != null) 'fuer': r.shop,
            'proMonat': eur(r.monthlyCents),
            'bezahlteRaten': r.paidCount
          }
      ],
      'mahnungenUndInkasso': [
        for (final d in Oddities.dunning(tx, now: today, days: 60))
          {
            'an': d.tx.note ?? d.tx.category,
            'betrag': eur(d.tx.amountCents),
            'datum': _day(d.tx.date),
            'inkasso': d.collector
          }
      ],
      'zurueckgegangeneLastschriften': [
        for (final r in Oddities.returnedDebits(tx, now: today, days: 30))
          {
            'haendler': r.merchant,
            'betrag': eur(r.cents),
            'datum': _day(r.back.date)
          }
      ],
      'hinweis':
          'Doppelt kann gewollt sein (zwei Tickets). Eine Lastschrift lässt sich 8 Wochen lang bei der Bank '
              'zurückholen, bei Karte über den Händler oder die Bank.',
    };
  }

  Map<String, dynamic> _bruttoNetto(Map<String, dynamic> input) {
    final month = (input['brutto_monat'] as num?)?.toDouble() ??
        ((input['brutto_jahr'] as num?)?.toDouble() ?? 0) / 12;
    if (month <= 0) return {'fehler': 'brutto_monat oder brutto_jahr fehlt'};
    final r = NetSalary.compute(
      month,
      taxClass: (input['steuerklasse'] as num?)?.toInt() ?? 1,
      children: (input['kinder'] as num?)?.toInt() ?? 0,
      age: (input['alter'] as num?)?.toInt(),
      church: input['kirchensteuer'] == true,
      state: '${input['bundesland'] ?? ''}',
      additional: (input['zusatzbeitrag'] as num?)?.toDouble() ??
          NetSalary.averageAdditional,
      student: input['werkstudent'] == true,
    );
    return {
      ...r.toJson(),
      'annahmen': {
        'steuerklasse': (input['steuerklasse'] as num?)?.toInt() ?? 1,
        'zusatzbeitragProzent': (input['zusatzbeitrag'] as num?)?.toDouble() ??
            NetSalary.averageAdditional,
        'kirchensteuer': input['kirchensteuer'] == true,
        'gesetzlichVersichert': true,
        'stand':
            'Lohnsteuer 2026 nach dem Programmablaufplan des Finanzministeriums',
      },
      'hinweis':
          'Schätzung. Die Abrechnung nutzt den genauen Zusatzbeitrag der Krankenkasse und z. B. '
              'Betriebsrente oder Freibeträge.',
    };
  }

  static String _artOf(String category, String name) {
    final t = '$category $name'.toLowerCase();
    if (RegExp(r'versicher|haftpflicht|hausrat|allianz|huk|ergo').hasMatch(t))
      return 'versicherung';
    if (RegExp(
            r'netflix|spotify|disney|youtube|prime|apple|icloud|dazn|audible|chatgpt|abo')
        .hasMatch(t)) return 'abo';
    if (RegExp(r'telekom|vodafone|o2|1&1|congstar|handy|internet|mobilfunk')
        .hasMatch(t)) return 'handy_internet';
    if (RegExp(r'strom|gas|stadtwerke|vattenfall|eon|e\.on|energie')
        .hasMatch(t)) return 'strom_gas';
    if (RegExp(r'fitx|mcfit|fitness|gym|urban sports|sport').hasMatch(t))
      return 'fitness';
    return 'sonstiges';
  }

  Map<String, dynamic> _prognose() {
    final cash = snapshot['kontostand'] as num?;
    final risk = cash == null
        ? null
        : Overdraft.check(tx, balanceCents: (cash * 100).round(), now: today);
    return {
      'heute': _day(today),
      'tageBisMonatsende': snapshot['tageBisMonatsende'],
      'prognose': snapshot['prognose'] ?? {'vorhanden': false},
      'budgets': snapshot['budgets'] ?? const [],
      'einnahmequellen': [
        for (final x in IncomeSources.detect(tx, now: today).take(8))
          {
            'name': x.name,
            'art': x.kind,
            'regelmaessig': x.regular,
            x.regular ? 'proMonat' : 'einmalig': x.monthlyCents / 100,
            'zuletzt': _day(x.last),
          }
      ],
      'ausstehendeEinnahmen': [
        for (final m in IncomeSources.missing(tx, now: today))
          {
            'name': m.name,
            'art': m.kind,
            'sonstUm': m.day,
            'betrag': m.monthlyCents / 100
          }
      ],
      'hinweisEinnahmen':
          'Die Prognose rechnet nur mit regelmäßigen Einnahmen (mindestens zwei der letzten drei Monate). '
              'Einmalige wie Bonus oder Steuererstattung zählen nicht mit.',
      if (risk != null)
        'minusVorDemGehalt': {
          'gehaltErwartet': _day(risk.payday),
          'fehltVoraussichtlich': risk.shortCents / 100,
          'nochFaelligBisDahin': risk.dueCents / 100,
          'verbrauchProTag': risk.dailyCents / 100,
          'hinweis':
              'Sag das früh und ruhig: was sich verschieben lässt, Dispo vermeiden, notfalls kurz vom Sparkonto.',
        },
    };
  }

  Map<String, dynamic> _ziele() => {
        for (final k in [
          'sparziele',
          'depot',
          'vermoegen',
          'vorsorge',
          'splits'
        ])
          if (snapshot[k] != null) k: snapshot[k],
      };

  // the usual month from the last three complete ones
  ({int income, int spent, int months}) _usual() {
    final full =
        _months(4).take(3).where((m) => m.income > 0 || m.spent > 0).toList();
    if (full.isEmpty) return (income: 0, spent: 0, months: 0);
    return (
      income: full.fold<int>(0, (s, m) => s + m.income) ~/ full.length,
      spent: full.fold<int>(0, (s, m) => s + m.spent) ~/ full.length,
      months: full.length,
    );
  }

  Map<String, dynamic> _wasWaereWenn(Map<String, dynamic> input) {
    int cents(String k) => (((input[k] as num?) ?? 0) * 100).round();
    final save = cents('monatlich_sparen'), once = cents('einmalig');
    final raise = cents('netto_aenderung'), fixed = cents('neue_fixkosten');
    final usual = _usual();
    if (usual.months == 0) {
      return {
        'fehler':
            'Noch zu wenig Verlauf: es gibt keinen vollständigen Monat mit Buchungen.'
      };
    }
    final before = usual.income - usual.spent;
    final after = before + raise - fixed - save;
    final forecast = snapshot['prognose'] as Map?;
    final freeNow = forecast?['vorhanden'] == true
        ? forecast!['freiBisMonatsende'] as num
        : null;
    return {
      'grundlage':
          'Durchschnitt der letzten ${usual.months} vollständigen Monate',
      'ueblichEinnahmen': _eur(usual.income),
      'ueblichAusgaben': _eur(usual.spent),
      'monatspufferVorher': _eur(before),
      'monatspufferNachher': _eur(after),
      'aenderungProMonat': _eur(after - before),
      'aufEinJahr': _eur((after - before) * 12),
      if (save > 0) 'gespartNachEinemJahr': _eur(save * 12),
      if (freeNow != null) 'freiBisMonatsendeJetzt': freeNow,
      if (freeNow != null && once > 0)
        'freiBisMonatsendeNachEinmalig': _round(freeNow - once / 100),
      'reichtEs': after >= 0,
    };
  }

  Map<String, dynamic> _sparplan(Map<String, dynamic> input) {
    final target = (((input['betrag'] as num?) ?? 0) * 100).round();
    if (target <= 0) throw const FormatException('betrag fehlt');
    final have = (((input['schon_gespart'] as num?) ?? 0) * 100).round();
    final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch('${input['bis'] ?? ''}');
    if (m == null) throw const FormatException('bis fehlt (JJJJ-MM)');
    final end = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!));
    // this month counts when there are still days left in it
    final months = (end.year - today.year) * 12 + end.month - today.month + 1;
    if (months < 1)
      return {'fehler': 'Der Zielmonat liegt in der Vergangenheit.'};
    final missing = math.max(0, target - have);
    final rate = (missing / months).ceil();
    final usual = _usual();
    final buffer = usual.income - usual.spent;
    return {
      'zielbetrag': _eur(target),
      'fehlt': _eur(missing),
      'monate': months,
      'rateProMonat': _eur(rate),
      if (usual.months > 0) 'ueblicherMonatspuffer': _eur(buffer),
      if (usual.months > 0 && buffer > 0)
        'anteilAmPufferProzent': (rate * 100 / buffer).round(),
      if (usual.months > 0) 'machbar': buffer >= rate,
    };
  }
}

// A small exact calculator for the model: numbers, + - * /, parentheses.
// No variables, no functions: nothing it reads can run as code.
class Calculator {
  static num eval(String expression) {
    final p = _Parser(expression
        .replaceAll(',', '.')
        .replaceAll('€', '')
        .replaceAll(' ', ''));
    if (p.src.isEmpty) throw const FormatException('ausdruck fehlt');
    final v = p.expr();
    if (p.i != p.src.length)
      throw FormatException('Unerwartetes Zeichen in "$expression"');
    if (v.isNaN || v.isInfinite)
      throw const FormatException('Division durch null');
    return v;
  }
}

class _Parser {
  final String src;
  int i = 0;
  _Parser(this.src);

  double expr() {
    var v = term();
    while (i < src.length && (src[i] == '+' || src[i] == '-')) {
      final op = src[i++];
      final r = term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double term() {
    var v = factor();
    while (i < src.length && (src[i] == '*' || src[i] == '/')) {
      final op = src[i++];
      final r = factor();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  double factor() {
    if (i < src.length && src[i] == '-') {
      i++;
      return -factor();
    }
    if (i < src.length && src[i] == '(') {
      i++;
      final v = expr();
      if (i >= src.length || src[i] != ')')
        throw const FormatException('Klammer fehlt');
      i++;
      return v;
    }
    final start = i;
    while (i < src.length && RegExp(r'[0-9.]').hasMatch(src[i])) {
      i++;
    }
    final n = double.tryParse(src.substring(start, i));
    if (n == null)
      throw FormatException('Zahl erwartet an Stelle ${start + 1}');
    return n;
  }
}

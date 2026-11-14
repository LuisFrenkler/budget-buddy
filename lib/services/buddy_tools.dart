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
    'kategorie_vorschlagen',
    'erinnerung_vorschlagen',
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
        'rechner' => {'ergebnis': _round(Calculator.eval('${input['ausdruck'] ?? ''}'))},
        'budget_vorschlagen' => _propose(BuddyProposal.budget(input)),
        'sparziel_vorschlagen' => _propose(BuddyProposal.goal(input, today: today)),
        'kuendigung_vorbereiten' => _propose(BuddyProposal.cancel(input)),
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
    if (proposals.length >= 3) return {'fehler': 'Höchstens drei Vorschläge pro Antwort.'};
    if (proposals.any((x) => x.kind == p.kind && x.title == p.title)) {
      return {'karte': 'schon gezeigt', 'titel': p.title};
    }
    proposals.add(p);
    return {
      'karte': 'gezeigt',
      'titel': p.title,
      'details': p.detail,
      'hinweis': 'Die Person sieht jetzt eine Karte mit „${p.confirm}“. Gespeichert ist noch nichts.',
    };
  }

  Map<String, dynamic> _diagramm(Map<String, dynamic> input) {
    if (charts.length >= 2) return {'fehler': 'Höchstens zwei Diagramme pro Antwort.'};
    switch ('${input['art'] ?? ''}') {
      case 'monate':
        final n = ((input['monate'] as num?)?.toInt() ?? 6).clamp(2, 12);
        final months = _months(n);
        const names = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
        charts.add(BuddyChart(ChartKind.months, tr('Einnahmen und Ausgaben'), [
          for (final m in months) (label: tr(names[m.month.month - 1]), a: m.income, b: m.spent)
        ]));
        return {'diagramm': 'gezeigt', 'art': 'monate', 'monate': n};
      case 'kategorien':
        final r = _ausgaben({'von': input['von'], 'bis': input['bis']});
        final rows = (r['nachKategorie'] as List).take(6).toList();
        charts.add(BuddyChart(ChartKind.categories, tr('Ausgaben nach Kategorie'), [
          for (final c in rows) (label: tr(c['name'].toString()), a: ((c['summe'] as num) * 100).round(), b: 0)
        ]));
        return {'diagramm': 'gezeigt', 'art': 'kategorien', 'summe': r['summe']};
      case 'sparplan':
        final r = _sparplan({'betrag': input['betrag'], 'bis': input['bis_monat'], 'schon_gespart': input['schon_gespart']});
        if (r['fehler'] != null) return r;
        final months = r['monate'] as int;
        final rate = ((r['rateProMonat'] as num) * 100).round();
        final have = ((((input['schon_gespart'] as num?) ?? 0)) * 100).round();
        const names = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
        final target = ((r['zielbetrag'] as num) * 100).round();
        const long = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni', 'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
        final end = DateTime(today.year, today.month + months - 1);
        charts.add(BuddyChart(ChartKind.plan, tr('Sparplan bis {m} {y}', {'m': tr(long[end.month - 1]), 'y': end.year}), [
          for (var i = 0; i < months.clamp(1, 12); i++)
            (
              label: tr(names[(today.month - 1 + i) % 12]),
              a: (have + rate * (i + 1)).clamp(0, target),
              b: target,
            )
        ]));
        return {'diagramm': 'gezeigt', 'art': 'sparplan', 'rateProMonat': r['rateProMonat'], 'monate': months};
    }
    throw const FormatException('art muss monate, kategorien oder sparplan sein');
  }

  // A few numbers that go with every question, so simple ones ("wie viel ist
  // frei?") need no extra step. Everything else still goes through tools.
  Map<String, dynamic> kurzinfo() {
    const days = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    final f = snapshot['prognose'] as Map?;
    return {
      'heute': '${days[today.weekday - 1]}, ${_day(today)}',
      if (snapshot['kontostand'] != null) 'summeKonten': snapshot['kontostand'],
      if (snapshot['tageBisMonatsende'] != null) 'tageBisMonatsende': snapshot['tageBisMonatsende'],
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
    if (d == null) throw FormatException('$field fehlt oder ist kein Datum (JJJJ-MM-TT)');
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
  Iterable<Transaction> get _counted => tx.where((t) => Categories.counts(t.category));

  // --- the tools ------------------------------------------------------------

  Map<String, dynamic> _konten() => {
        'stand': _day(today),
        'konten': snapshot['konten'] ?? const [],
        'summeKonten': snapshot['kontostand'],
        'depotwert': snapshot['depotwert'],
        'gesamtvermoegen': snapshot['gesamtvermoegen'],
      };

  ({int total, Map<String, int> groups, int count}) _spend(
      DateTime from, DateTime to, String by, String? category, String? merchant) {
    final groups = <String, int>{};
    var total = 0, count = 0;
    final cat = category?.trim().toLowerCase();
    final m = merchant?.trim().toLowerCase();
    for (final t in _counted) {
      if (!t.isSpending || !_within(t, from, to)) continue;
      if (cat != null && cat.isNotEmpty && t.category.toLowerCase() != cat) continue;
      if (m != null && m.isNotEmpty && !_title(t).toLowerCase().contains(m)) continue;
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
    final ranked = now.groups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return {
      'zeitraum': {'von': _day(from), 'bis': _day(to), 'tage': days},
      'summe': _eur(now.total),
      'anzahlBuchungen': now.count,
      by == 'haendler' ? 'nachHaendler' : 'nachKategorie': [
        for (final e in ranked.take(15))
          {'name': e.key, 'summe': _eur(e.value), 'anteilProzent': now.total == 0 ? 0 : (e.value * 100 / now.total).round()}
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
    final ranked = groups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
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
        if ((text.isEmpty || _title(t).toLowerCase().contains(text) || t.category.toLowerCase().contains(text)) &&
            (from == null || !t.date.isBefore(from)) &&
            (to == null || !DateTime(t.date.year, t.date.month, t.date.day).isAfter(to)) &&
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
            'monat': '${m.month.year}-${m.month.month.toString().padLeft(2, '0')}',
            'einnahmen': _eur(m.income),
            'ausgaben': _eur(m.spent),
            'gespart': _eur(m.income - m.spent),
            'sparquoteProzent': m.income == 0 ? null : ((m.income - m.spent) * 100 / m.income).round(),
            if (m.month.year == today.year && m.month.month == today.month) 'laufend': true,
          }
      ],
    };
  }

  Map<String, dynamic> _vertraege() {
    final contracts = (snapshot['vertraegeUndAbos'] as List?) ?? const [];
    final monthly = contracts.fold<double>(0, (s, c) => s + ((c as Map)['proMonat'] as num? ?? 0));
    return {
      'vertraegeUndAbos': contracts,
      'summeProMonat': _round(monthly),
      'dauerauftraege': snapshot['wiederkehrend'] ?? const [],
    };
  }

  Map<String, dynamic> _prognose() => {
        'heute': _day(today),
        'tageBisMonatsende': snapshot['tageBisMonatsende'],
        'prognose': snapshot['prognose'] ?? {'vorhanden': false},
        'budgets': snapshot['budgets'] ?? const [],
      };

  Map<String, dynamic> _ziele() => {
        for (final k in ['sparziele', 'depot', 'vermoegen', 'vorsorge', 'splits'])
          if (snapshot[k] != null) k: snapshot[k],
      };

  // the usual month from the last three complete ones
  ({int income, int spent, int months}) _usual() {
    final full = _months(4).take(3).where((m) => m.income > 0 || m.spent > 0).toList();
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
      return {'fehler': 'Noch zu wenig Verlauf: es gibt keinen vollständigen Monat mit Buchungen.'};
    }
    final before = usual.income - usual.spent;
    final after = before + raise - fixed - save;
    final forecast = snapshot['prognose'] as Map?;
    final freeNow = forecast?['vorhanden'] == true ? forecast!['freiBisMonatsende'] as num : null;
    return {
      'grundlage': 'Durchschnitt der letzten ${usual.months} vollständigen Monate',
      'ueblichEinnahmen': _eur(usual.income),
      'ueblichAusgaben': _eur(usual.spent),
      'monatspufferVorher': _eur(before),
      'monatspufferNachher': _eur(after),
      'aenderungProMonat': _eur(after - before),
      'aufEinJahr': _eur((after - before) * 12),
      if (save > 0) 'gespartNachEinemJahr': _eur(save * 12),
      if (freeNow != null) 'freiBisMonatsendeJetzt': freeNow,
      if (freeNow != null && once > 0) 'freiBisMonatsendeNachEinmalig': _round(freeNow - once / 100),
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
    if (months < 1) return {'fehler': 'Der Zielmonat liegt in der Vergangenheit.'};
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
      if (usual.months > 0 && buffer > 0) 'anteilAmPufferProzent': (rate * 100 / buffer).round(),
      if (usual.months > 0) 'machbar': buffer >= rate,
    };
  }
}

// A small exact calculator for the model: numbers, + - * /, parentheses.
// No variables, no functions: nothing it reads can run as code.
class Calculator {
  static num eval(String expression) {
    final p = _Parser(expression.replaceAll(',', '.').replaceAll('€', '').replaceAll(' ', ''));
    if (p.src.isEmpty) throw const FormatException('ausdruck fehlt');
    final v = p.expr();
    if (p.i != p.src.length) throw FormatException('Unerwartetes Zeichen in "$expression"');
    if (v.isNaN || v.isInfinite) throw const FormatException('Division durch null');
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
      if (i >= src.length || src[i] != ')') throw const FormatException('Klammer fehlt');
      i++;
      return v;
    }
    final start = i;
    while (i < src.length && RegExp(r'[0-9.]').hasMatch(src[i])) {
      i++;
    }
    final n = double.tryParse(src.substring(start, i));
    if (n == null) throw FormatException('Zahl erwartet an Stelle ${start + 1}');
    return n;
  }
}

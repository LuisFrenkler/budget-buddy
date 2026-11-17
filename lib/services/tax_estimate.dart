// The tax return, roughly, all year long: Buddy collects what counts as
// Werbungskosten from the bookings, adds the commute and home office from
// a few answers, and estimates what comes back. For employees in tax class
// I to IV; a first job that started during the year usually gets money back
// on its own, because the monthly wage tax assumes twelve months of pay.
//
// Rules per year, 2022 to 2026. Commuting: 0.30 € per km for the first 20 km
// and 0.38 € from km 21 until 2025, 0.38 € from the first km in 2026 (StÄndG
// 2025). Home office: 5 € a day for up to 120 days in 2022, 6 € for up to 210
// days since 2023. Employee allowance 1,200 € in 2022, 1,230 € since. 16 €
// account fees without receipt. A voluntary return for a year can be filed
// for four years (it must reach the office by 31 Dec of year + 4).
// Everything is an estimate, not tax advice; the person files themselves.
import 'package:hive/hive.dart';

import '../l10n/l10n.dart';
import '../models/transaction.dart';
import '../utils/money.dart';
import 'net_salary.dart';
import 'product_events.dart';

class TaxCandidate {
  final Transaction tx;
  final String kind; // arbeitsmittel, fortbildung, bewerbung, gewerkschaft, umzug
  const TaxCandidate(this.tx, this.kind);
}

class TaxProfile {
  final double grossMonth;
  final int monthsWorked;
  final double km; // one way
  final double officeDaysPerWeek;
  final double homeDaysPerWeek;
  final int taxClass;
  final bool church;
  // from the Lohnsteuerbescheinigung, when photographed: the real year
  final double? grossYear, withheldYear;
  const TaxProfile({
    this.grossMonth = 0,
    this.monthsWorked = 12,
    this.km = 0,
    this.officeDaysPerWeek = 5,
    this.homeDaysPerWeek = 0,
    this.taxClass = 1,
    this.church = false,
    this.grossYear,
    this.withheldYear,
  });

  bool get fromCertificate => grossYear != null && withheldYear != null;

  Map<String, dynamic> toJson() => {
        'grossMonth': grossMonth,
        'monthsWorked': monthsWorked,
        'km': km,
        'officeDaysPerWeek': officeDaysPerWeek,
        'homeDaysPerWeek': homeDaysPerWeek,
        'taxClass': taxClass,
        'church': church,
        if (grossYear != null) 'grossYear': grossYear,
        if (withheldYear != null) 'withheldYear': withheldYear,
      };

  factory TaxProfile.fromJson(Map j) => TaxProfile(
        grossMonth: (j['grossMonth'] as num?)?.toDouble() ?? 0,
        monthsWorked: (j['monthsWorked'] as num?)?.toInt() ?? 12,
        km: (j['km'] as num?)?.toDouble() ?? 0,
        officeDaysPerWeek: (j['officeDaysPerWeek'] as num?)?.toDouble() ?? 5,
        homeDaysPerWeek: (j['homeDaysPerWeek'] as num?)?.toDouble() ?? 0,
        taxClass: (j['taxClass'] as num?)?.toInt() ?? 1,
        church: j['church'] == true,
        grossYear: (j['grossYear'] as num?)?.toDouble(),
        withheldYear: (j['withheldYear'] as num?)?.toDouble(),
      );

  TaxProfile copyWith({
    double? grossMonth,
    int? monthsWorked,
    double? km,
    double? officeDaysPerWeek,
    double? homeDaysPerWeek,
    int? taxClass,
    bool? church,
    double? grossYear,
    double? withheldYear,
  }) =>
      TaxProfile(
        grossMonth: grossMonth ?? this.grossMonth,
        monthsWorked: monthsWorked ?? this.monthsWorked,
        km: km ?? this.km,
        officeDaysPerWeek: officeDaysPerWeek ?? this.officeDaysPerWeek,
        homeDaysPerWeek: homeDaysPerWeek ?? this.homeDaysPerWeek,
        taxClass: taxClass ?? this.taxClass,
        church: church ?? this.church,
        grossYear: grossYear ?? this.grossYear,
        withheldYear: withheldYear ?? this.withheldYear,
      );
}

class TaxResult {
  final double commute, homeOffice, accountFee, receipts;
  final double withheld; // wage tax incl. soli and church taken during the year
  final double due; // what the year really costs
  final List<String> notes;
  final double allowance;
  // what the commute and home office lines of the form ask for
  final double officeDays, homeDays, km;
  const TaxResult({
    required this.commute,
    required this.homeOffice,
    required this.accountFee,
    required this.receipts,
    required this.withheld,
    required this.due,
    this.notes = const [],
    this.allowance = 1230,
    this.officeDays = 0,
    this.homeDays = 0,
    this.km = 0,
  });

  double get werbungskosten => commute + homeOffice + accountFee + receipts;
  double get aboveAllowance => werbungskosten > allowance ? werbungskosten - allowance : 0;
  double get refund => withheld - due;

  Map<String, dynamic> toJson() {
    double r(double v) => (v * 100).round() / 100;
    return {
      'werbungskosten': {
        'fahrten': r(commute),
        'homeoffice': r(homeOffice),
        'kontofuehrung': r(accountFee),
        'belege': r(receipts),
        'summe': r(werbungskosten),
        'ueberPauschbetrag': r(aboveAllowance),
      },
      'lohnsteuerEinbehalten': r(withheld),
      'steuerFuersJahr': r(due),
      'erstattungGeschaetzt': r(refund),
      if (notes.isNotEmpty) 'hinweise': notes,
    };
  }
}

class TaxEstimate {
  static const perKm = 0.38, homeOfficePerDay = 6.0, homeOfficeMaxDays = 210, accountFee = 16.0;

  // the commute deduction for [km] one way on one office day
  static double commutePerDay(double km, int year) {
    final k = km.ceilToDouble();
    if (year >= 2026) return k * perKm;
    return (k < 20 ? k : 20) * 0.30 + (k > 20 ? k - 20 : 0) * perKm;
  }

  // a voluntary return for [year] must reach the tax office by this day
  static DateTime deadline(int year) => DateTime(year + 4, 12, 31);

  // past years whose voluntary return can still be filed on [today]
  static List<int> openYears(DateTime today) => [
        for (var y = NetSalary.firstYear; y < today.year; y++)
          if (!DateTime(today.year, today.month, today.day).isAfter(deadline(y))) y
      ];

  // what goes where in ELSTER (Anlage N), so the person can type it in.
  // Wage and wage tax come from the employer electronically.
  static List<Map<String, dynamic>> elster(TaxResult r, List<TaxCandidate> counted) {
    double r2(double v) => (v * 100).round() / 100;
    final byKind = <String, double>{};
    for (final c in counted) {
      byKind[c.kind] = (byKind[c.kind] ?? 0) + c.tx.amountCents / 100;
    }
    const labels = {
      'arbeitsmittel': 'Aufwendungen für Arbeitsmittel',
      'fortbildung': 'Fortbildungskosten',
      'gewerkschaft': 'Beiträge zu Berufsverbänden',
      'bewerbung': 'Weitere Werbungskosten: Bewerbungskosten',
      'umzug': 'Weitere Werbungskosten: Umzugskosten',
    };
    Map<String, dynamic> f(String feld, Object wert) => {'formular': 'Anlage N', 'feld': feld, 'wert': wert};
    return [
      {
        'formular': 'Anlage N',
        'feld': 'Bruttoarbeitslohn und Lohnsteuer',
        'wert': 'kommt elektronisch vom Arbeitgeber, nur mit der Lohnsteuerbescheinigung vergleichen'
      },
      if (r.officeDays > 0 && r.km > 0) ...[
        f('Erste Tätigkeitsstätte: Arbeitstage', r.officeDays.round()),
        f('Erste Tätigkeitsstätte: einfache Entfernung in km', r.km.ceil()),
      ],
      if (r.homeOffice > 0) f('Tagespauschale (Homeoffice): Anzahl der Tage', r.homeDays.round()),
      for (final e in byKind.entries) f(labels[e.key] ?? 'Weitere Werbungskosten', r2(e.value)),
      f('Weitere Werbungskosten: Kontoführungsgebühren', r2(r.accountFee)),
    ];
  }
  // working days in a full year after holidays and leave, roughly
  static const workDays = 220;

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  // each year has its own answers; a year without falls back to the last saved ones
  static TaxProfile profile({int? year}) {
    final j = (year == null ? null : _box?.get('taxProfile:$year')) ?? _box?.get('taxProfile');
    return j is Map ? TaxProfile.fromJson(j) : const TaxProfile();
  }

  static Future<void> saveProfile(TaxProfile p, {int? year}) async {
    // the certificate belongs to its year only
    await _box?.put('taxProfile', p.toJson()..remove('grossYear')..remove('withheldYear'));
    if (year != null) await _box?.put('taxProfile:$year', p.toJson());
  }

  // bookings the person included (true) or left out (false); others follow the suggestion
  static Map<String, bool> picks() =>
      ((_box?.get('taxPicks') as Map?) ?? const {}).map((k, v) => MapEntry('$k', v == true));

  static Future<void> pick(String txId, bool include) async => _box?.put('taxPicks', {...picks(), txId: include});

  static final _kinds = <String, RegExp>{
    'gewerkschaft': RegExp(r'gewerkschaft|ver\.?di|ig metall|ig bce|gew\b|komba|marburger bund', caseSensitive: false),
    'fortbildung': RegExp(
        r'fortbildung|weiterbildung|seminar|schulung|zertifizierung|prüfungsgebühr|pruefungsgebuehr|udemy|coursera|'
        r'linkedin learning|ihk\b|sprachkurs|fachkonferenz',
        caseSensitive: false),
    'arbeitsmittel': RegExp(
        r'fachbuch|fachliteratur|arbeitskleidung|berufskleidung|schutzkleidung|bürostuhl|buerostuhl|schreibtisch|'
        r'monitor|headset|laptop|notebook|aktentasche|arbeitsschuhe',
        caseSensitive: false),
    'bewerbung': RegExp(r'bewerbung|bewerbungsfoto|bewerbungsmappe', caseSensitive: false),
    'umzug': RegExp(r'umzug|umzugsunternehmen|umzugskarton|transporter', caseSensitive: false),
  };

  // bookings of [year] that may count as Werbungskosten
  static List<TaxCandidate> candidates(List<Transaction> tx, int year) => [
        for (final t in tx)
          if (!t.isIncome && t.date.year == year)
            for (final e in _kinds.entries)
              if (e.value.hasMatch('${t.note ?? ''} ${t.category}')) TaxCandidate(t, e.key)
      ];

  // the candidates that count: suggested ones unless left out, plus picked ones
  static List<TaxCandidate> counted(List<Transaction> tx, int year) {
    final p = picks();
    return [
      for (final c in candidates(tx, year))
        if (p[c.tx.id] ?? true) c
    ];
  }

  static TaxResult compute(TaxProfile p, {double receipts = 0, int year = 2026}) {
    final notes = <String>[];
    final months = p.monthsWorked.clamp(1, 12);
    final share = months / 12;
    final weekDays = (p.officeDaysPerWeek + p.homeDaysPerWeek).clamp(0.5, 7);
    final officeDays = (workDays * share * p.officeDaysPerWeek / (weekDays < 5 ? 5 : weekDays)).roundToDouble();
    final homeDays = (workDays * share * p.homeDaysPerWeek / (weekDays < 5 ? 5 : weekDays)).roundToDouble();
    var commute = commutePerDay(p.km, year) * officeDays;
    if (commute > 4500) notes.add(tr('Über 4.500 € Fahrtkosten zählen nur mit eigenem Auto.'));
    final (perDay, maxDays) = year <= 2022 ? (5.0, 120) : (homeOfficePerDay, homeOfficeMaxDays);
    final home = (homeDays > maxDays ? maxDays : homeDays) * perDay;
    final cls = p.taxClass >= 1 && p.taxClass <= 4 ? p.taxClass : 1;
    final allowance = NetSalary.allowance(year);

    // wage tax taken each month, as if the pay ran all year
    final monthly = NetSalary.yearTax(p.grossMonth * 12, taxClass: cls, church: p.church, year: year);
    final withheld = p.withheldYear ?? (monthly.tax + monthly.soli + monthly.church) / 12 * months;
    // the real year: the months worked and the real costs
    final wk = commute + home + accountFee + receipts;
    final real =
        NetSalary.yearTax(p.grossYear ?? p.grossMonth * months, taxClass: cls, church: p.church, werbungskosten: wk, year: year);
    if (months < 12) {
      notes.add(tr('Nur {n} Monate gearbeitet: Ein Teil der Lohnsteuer kommt deshalb sowieso zurück.', {'n': months}));
    }
    if (wk <= allowance) {
      notes.add(allowance == 1200
          ? tr('Unter dem Pauschbetrag von 1.200 €: Die Kosten selbst bringen nichts extra, die Erklärung kann sich '
              'trotzdem lohnen.')
          : tr('Unter dem Pauschbetrag von 1.230 €: Die Kosten selbst bringen nichts extra, die Erklärung kann sich '
              'trotzdem lohnen.'));
    }
    return TaxResult(
      commute: commute,
      homeOffice: home,
      accountFee: accountFee,
      receipts: receipts,
      withheld: withheld,
      due: real.tax + real.soli + real.church,
      notes: notes,
      allowance: allowance,
      officeDays: officeDays,
      homeDays: homeDays > maxDays ? maxDays.toDouble() : homeDays,
      km: p.km,
    );
  }

  // ---------------------------------------------------------------- range

  // What surely comes back and what comes back if every claimed cost is
  // accepted. Without the certificate the withheld tax is our guess, so the
  // low end also allows for that.
  // shortcut: the 10 % band is a guess, set it from the measured deviation once 30 assessments are in.
  static ({double low, double high}) range(TaxProfile p, {double receipts = 0, int year = 2026}) {
    final full = compute(p, receipts: receipts, year: year).refund;
    final sure = compute(p.copyWith(km: 0, homeDaysPerWeek: 0), year: year);
    final low = sure.refund - (p.fromCertificate ? 0 : sure.withheld * 0.1);
    double clip(double v) => v < 0 ? 0 : v;
    return (low: clip(low < full ? low : full), high: clip(full));
  }

  // one line per reason, so the number can be checked
  static List<String> reasons(TaxProfile p, TaxResult r, int year) => [
        if (p.monthsWorked < 12)
          tr('Nur {n} Monate gearbeitet: Die Lohnsteuer wurde jeden Monat so berechnet, als ginge der Lohn das ganze Jahr.',
              {'n': p.monthsWorked}),
        if (r.commute > 0)
          tr('Arbeitsweg {km} km an {d} Tagen: {x} Fahrtkosten.',
              {'km': p.km.ceil(), 'd': r.officeDays.round(), 'x': Money.format((r.commute * 100).round())}),
        if (r.homeOffice > 0)
          tr('Homeoffice an {d} Tagen: {x}.', {'d': r.homeDays.round(), 'x': Money.format((r.homeOffice * 100).round())}),
        if (r.receipts > 0) tr('Belege aus deinen Buchungen: {x}.', {'x': Money.format((r.receipts * 100).round())}),
        if (r.werbungskosten > r.allowance)
          tr('Deine Werbungskosten liegen {x} über dem Pauschbetrag.', {'x': Money.format((r.aboveAllowance * 100).round())}),
        if (p.fromCertificate)
          tr('Lohn und Lohnsteuer stammen aus deiner Lohnsteuerbescheinigung.')
        else
          tr('Lohnsteuer geschätzt aus deinem Brutto. Mit der Lohnsteuerbescheinigung wird die Zahl genau.'),
      ];

  // The refund check before sign-up: three answers, a range for every year
  // that can still be filed. The same pay is assumed for every year.
  // shortcut: one gross for all years, ask per year once people correct it often.
  static List<QuickYear> quickCheck({
    required int startYear,
    required int startMonth,
    required double grossMonth,
    double km = 0,
    required DateTime today,
  }) {
    final years = [...openYears(today), today.year];
    return [
      for (final y in years)
        if (y >= startYear)
          () {
            final p = TaxProfile(grossMonth: grossMonth, km: km, monthsWorked: y == startYear ? 13 - startMonth : 12);
            final r = compute(p, year: y);
            final band = range(p, year: y);
            return QuickYear(y, band.low, band.high, reasons(p, r, y), y < today.year ? deadline(y) : null);
          }()
    ];
  }

  // After sign-up: the guest's refund check becomes one profile per open
  // year (years with own answers stay), then it is gone. Returns the oldest
  // open year to show, or null when there was no check.
  static Future<int?> adoptRefundCheck({required DateTime now}) async {
    final q = _box?.get('refundCheck');
    if (q is! Map) return null;
    final start = (q['startYear'] as num?)?.toInt() ?? now.year;
    final month = (q['startMonth'] as num?)?.toInt() ?? 1;
    final gross = (q['grossMonth'] as num?)?.toDouble() ?? 0;
    final km = (q['km'] as num?)?.toDouble() ?? 0;
    final years = [for (final y in [...openYears(now), now.year]) if (y >= start) y];
    for (final y in years) {
      if (_box?.get('taxProfile:$y') != null) continue;
      await saveProfile(TaxProfile(grossMonth: gross, km: km, monthsWorked: y == start ? 13 - month : 12), year: y);
    }
    await _box?.delete('refundCheck');
    final open = openYears(now).where((y) => y >= start);
    return open.isEmpty ? (years.isEmpty ? null : years.first) : open.first;
  }

  // -------------------------------------------------- filed and assessed

  static Map<String, dynamic> _year(int year) =>
      (((_box?.get('taxYears') as Map?) ?? const {})['$year'] as Map?)?.cast<String, dynamic>() ?? {};

  static Future<void> _saveYear(int year, Map<String, dynamic> data) async {
    final all = ((_box?.get('taxYears') as Map?) ?? const {}).cast<String, dynamic>();
    await _box?.put('taxYears', {...all, '$year': data});
  }

  static DateTime? filedAt(int year) => DateTime.tryParse('${_year(year)['filed'] ?? ''}');
  static double? filedEstimate(int year) => (_year(year)['estimate'] as num?)?.toDouble();

  // [control]: what the three-answer check alone would have said, so the
  // notice shows whether bank data, receipts and the certificate made it better
  static Future<void> markFiled(int year, double estimate, {double? control, DateTime? at}) async {
    await _saveYear(year, {
      ..._year(year),
      'filed': (at ?? DateTime.now()).toIso8601String(),
      'estimate': estimate,
      if (control != null) 'control': control,
    });
    await ProductEvents.track(ProductEvents.taxFiled);
  }

  static Future<void> unmarkFiled(int year) async => _saveYear(year, {..._year(year)}..remove('filed'));

  static Assessment? assessment(int year) {
    final a = _year(year)['assessment'];
    return a is Map ? Assessment.fromJson(a.cast<String, dynamic>()) : null;
  }

  static Future<void> saveAssessment(Assessment a) async {
    await _saveYear(a.year, {..._year(a.year), 'assessment': a.toJson()});
    await ProductEvents.track(ProductEvents.assessment);
    final est = filedEstimate(a.year);
    if (est != null) await ProductEvents.track(accuracyEvent(est, a.refund));
    final control = (_year(a.year)['control'] as num?)?.toDouble();
    if (control != null) await ProductEvents.track(accuracyEvent(control, a.refund, control: true));
  }

  // how close the estimate was, as a bucket: no amount leaves the phone
  static String accuracyEvent(double estimate, double actual, {bool control = false}) {
    final off = (actual - estimate).abs() / (estimate.abs() < 50 ? 50 : estimate.abs());
    if (control) {
      return off <= 0.10
          ? ProductEvents.controlWithin10
          : off <= 0.25
              ? ProductEvents.controlWithin25
              : ProductEvents.controlOff;
    }
    return off <= 0.10
        ? ProductEvents.estimateWithin10
        : off <= 0.25
            ? ProductEvents.estimateWithin25
            : ProductEvents.estimateOff;
  }

  // the three-answer estimate for a profile: no certificate, no receipts, no home office
  static double controlEstimate(TaxProfile p, int year) => compute(
          TaxProfile(grossMonth: p.grossMonth, monthsWorked: p.monthsWorked, km: p.km, taxClass: p.taxClass, church: p.church),
          year: year)
      .refund;

  // The objection period: one month after the notice counts as delivered,
  // four days after its date since 2025 (three before). Weekends that would
  // push the date later are ignored, so the date shown is never too late.
  static DateTime objectionUntil(DateTime noticeDate) {
    final known = noticeDate.add(Duration(days: noticeDate.year >= 2025 ? 4 : 3));
    final next = DateTime(known.year, known.month + 1, known.day);
    // 31 Jan + 1 month: the last day of February, not 3 March
    return next.month == (known.month % 12) + 1 ? next : DateTime(known.year, known.month + 2, 0);
  }
}

class QuickYear {
  final int year;
  final double low, high;
  final List<String> reasons;
  final DateTime? deadline; // null: the year is still running
  const QuickYear(this.year, this.low, this.high, this.reasons, this.deadline);
}

// what the tax office decided, read off the notice
class Assessment {
  final int year;
  final double refund; // negative: back payment
  final double? werbungskosten; // what the office accepted
  final DateTime date;
  const Assessment({required this.year, required this.refund, this.werbungskosten, required this.date});

  Map<String, dynamic> toJson() =>
      {'year': year, 'refund': refund, 'werbungskosten': werbungskosten, 'date': date.toIso8601String()};

  factory Assessment.fromJson(Map<String, dynamic> j) => Assessment(
        year: (j['year'] as num).toInt(),
        refund: (j['refund'] as num).toDouble(),
        werbungskosten: (j['werbungskosten'] as num?)?.toDouble(),
        date: DateTime.parse('${j['date']}'),
      );
}

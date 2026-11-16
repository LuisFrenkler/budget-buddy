// The tax return, roughly, all year long: Buddy collects what counts as
// Werbungskosten from the bookings, adds the commute and home office from
// a few answers, and estimates what comes back. For employees in tax class
// I to IV; a first job that started during the year usually gets money back
// on its own, because the monthly wage tax assumes twelve months of pay.
//
// 2026 rules: commuting 0.38 € per km from the first km (StÄndG 2025), home
// office 6 € a day for up to 210 days, 16 € account fees without receipt,
// employee allowance 1,230 €. Everything is an estimate, not tax advice.
import 'package:hive/hive.dart';

import '../l10n/l10n.dart';
import '../models/transaction.dart';
import 'net_salary.dart';

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
  const TaxProfile({
    this.grossMonth = 0,
    this.monthsWorked = 12,
    this.km = 0,
    this.officeDaysPerWeek = 5,
    this.homeDaysPerWeek = 0,
    this.taxClass = 1,
    this.church = false,
  });

  Map<String, dynamic> toJson() => {
        'grossMonth': grossMonth,
        'monthsWorked': monthsWorked,
        'km': km,
        'officeDaysPerWeek': officeDaysPerWeek,
        'homeDaysPerWeek': homeDaysPerWeek,
        'taxClass': taxClass,
        'church': church,
      };

  factory TaxProfile.fromJson(Map j) => TaxProfile(
        grossMonth: (j['grossMonth'] as num?)?.toDouble() ?? 0,
        monthsWorked: (j['monthsWorked'] as num?)?.toInt() ?? 12,
        km: (j['km'] as num?)?.toDouble() ?? 0,
        officeDaysPerWeek: (j['officeDaysPerWeek'] as num?)?.toDouble() ?? 5,
        homeDaysPerWeek: (j['homeDaysPerWeek'] as num?)?.toDouble() ?? 0,
        taxClass: (j['taxClass'] as num?)?.toInt() ?? 1,
        church: j['church'] == true,
      );

  TaxProfile copyWith({
    double? grossMonth,
    int? monthsWorked,
    double? km,
    double? officeDaysPerWeek,
    double? homeDaysPerWeek,
    int? taxClass,
    bool? church,
  }) =>
      TaxProfile(
        grossMonth: grossMonth ?? this.grossMonth,
        monthsWorked: monthsWorked ?? this.monthsWorked,
        km: km ?? this.km,
        officeDaysPerWeek: officeDaysPerWeek ?? this.officeDaysPerWeek,
        homeDaysPerWeek: homeDaysPerWeek ?? this.homeDaysPerWeek,
        taxClass: taxClass ?? this.taxClass,
        church: church ?? this.church,
      );
}

class TaxResult {
  final double commute, homeOffice, accountFee, receipts;
  final double withheld; // wage tax incl. soli and church taken during the year
  final double due; // what the year really costs
  final List<String> notes;
  const TaxResult({
    required this.commute,
    required this.homeOffice,
    required this.accountFee,
    required this.receipts,
    required this.withheld,
    required this.due,
    this.notes = const [],
  });

  double get werbungskosten => commute + homeOffice + accountFee + receipts;
  double get aboveAllowance => werbungskosten > 1230 ? werbungskosten - 1230 : 0;
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
  // working days in a full year after holidays and leave, roughly
  static const workDays = 220;

  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static TaxProfile profile() {
    final j = _box?.get('taxProfile');
    return j is Map ? TaxProfile.fromJson(j) : const TaxProfile();
  }

  static Future<void> saveProfile(TaxProfile p) async => _box?.put('taxProfile', p.toJson());

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

  static TaxResult compute(TaxProfile p, {double receipts = 0}) {
    final notes = <String>[];
    final months = p.monthsWorked.clamp(1, 12);
    final share = months / 12;
    final weekDays = (p.officeDaysPerWeek + p.homeDaysPerWeek).clamp(0.5, 7);
    final officeDays = (workDays * share * p.officeDaysPerWeek / (weekDays < 5 ? 5 : weekDays)).roundToDouble();
    final homeDays = (workDays * share * p.homeDaysPerWeek / (weekDays < 5 ? 5 : weekDays)).roundToDouble();
    var commute = p.km.ceil() * perKm * officeDays;
    if (commute > 4500) notes.add(tr('Über 4.500 € Fahrtkosten zählen nur mit eigenem Auto.'));
    final home = (homeDays > homeOfficeMaxDays ? homeOfficeMaxDays : homeDays) * homeOfficePerDay;
    final cls = p.taxClass >= 1 && p.taxClass <= 4 ? p.taxClass : 1;

    // wage tax taken each month, as if the pay ran all year
    final monthly = NetSalary.yearTax(p.grossMonth * 12, taxClass: cls, church: p.church);
    final withheld = (monthly.tax + monthly.soli + monthly.church) / 12 * months;
    // the real year: the months worked and the real costs
    final wk = commute + home + accountFee + receipts;
    final real = NetSalary.yearTax(p.grossMonth * months, taxClass: cls, church: p.church, werbungskosten: wk);
    if (months < 12) {
      notes.add(tr('Nur {n} Monate gearbeitet: Ein Teil der Lohnsteuer kommt deshalb sowieso zurück.', {'n': months}));
    }
    if (wk <= 1230) {
      notes.add(tr('Unter dem Pauschbetrag von 1.230 €: Die Kosten selbst bringen nichts extra, die Erklärung kann sich '
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
    );
  }
}

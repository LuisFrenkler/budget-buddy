// shortcut: a copy of lib/services/net_salary.dart, because the server image only holds backend/;
// test/mcp_parity_test.dart fails when the two differ. Share a package once a third copy is needed.
// Gross to net for employees in Germany, 2026: wage tax after the official
// program flow of the Federal Ministry of Finance (PAP 2026) and the employee
// share of the social contributions. For tax classes I to IV and people with
// statutory health insurance. It is an estimate: the payslip uses the exact
// additional health contribution of the insurer and things like company
// pension or tax allowances.
//
// Sources: § 32a EStG (2026 tariff), PAP 2026 (Vorsorgepauschale, SolZ
// threshold 20,350 €), social security values 2026 (contribution ceilings
// 69,750 € and 101,400 € a year, RV 18.6 %, AV 2.6 %, KV 14.6 %, PV 3.6 %,
// average additional contribution 2.9 %).
import 'dart:math' as math;

class NetResult {
  final double gross; // per month
  final double wageTax, soli, churchTax;
  final double pension, unemployment, health, care;
  final List<String> notes;
  const NetResult({
    required this.gross,
    required this.wageTax,
    required this.soli,
    required this.churchTax,
    required this.pension,
    required this.unemployment,
    required this.health,
    required this.care,
    this.notes = const [],
  });

  double get taxes => wageTax + soli + churchTax;
  double get social => pension + unemployment + health + care;
  double get net => _r(gross - taxes - social);

  Map<String, dynamic> toJson() => {
        'bruttoMonat': _r(gross),
        'nettoMonat': net,
        'nettoJahr': _r(net * 12),
        'lohnsteuer': _r(wageTax),
        'soli': _r(soli),
        'kirchensteuer': _r(churchTax),
        'rentenversicherung': _r(pension),
        'arbeitslosenversicherung': _r(unemployment),
        'krankenversicherung': _r(health),
        'pflegeversicherung': _r(care),
        'steuernGesamt': _r(taxes),
        'sozialabgabenGesamt': _r(social),
        if (notes.isNotEmpty) 'hinweise': notes,
      };

  static double _r(double v) => (v * 100).round() / 100;
}

class NetSalary {
  // 2026 values
  static const bbgKvPv = 69750.0; // a year
  static const bbgRvAv = 101400.0;
  static const rv = 0.093, av = 0.013; // employee shares
  static const kvGeneral = 0.073, kvReduced = 0.07; // half of 14.6 % / 14.0 %
  static const averageAdditional = 2.9; // percent, shared half and half
  static const solzFree = 20350.0;
  static const minijob = 603.0, midijobTop = 2000.0;

  // § 32a EStG per year: basic allowance, end of zone 2, end of zone 3, the
  // zone 2 and 3 factors, the zone 3 constant and the 42 % / 45 % offsets.
  // 2022 and 2024 as changed later in the year (Steuerentlastungsgesetz 2022,
  // Steuerfortentwicklungsgesetz 2024).
  static const _tariffs = <int, List<double>>{
    2022: [10347, 14926, 58596, 1088.67, 206.43, 869.32, 9336.45, 17671.20],
    2023: [10908, 15999, 62809, 979.18, 192.59, 966.53, 9972.98, 18307.73],
    2024: [11784, 17005, 66760, 954.80, 181.19, 991.21, 10636.31, 18971.06],
    2025: [12096, 17443, 68480, 932.30, 176.64, 1015.13, 10911.92, 19246.67],
    2026: [12348, 17799, 69878, 914.51, 173.10, 1034.87, 11135.63, 19470.38],
  };
  // the tax one person may owe before the solidarity surcharge starts
  static const _solzFree = <int, double>{2022: 16956, 2023: 17543, 2024: 18130, 2025: 19950, 2026: solzFree};
  static const firstYear = 2022, lastYear = 2026;
  static int _y(int year) => year.clamp(firstYear, lastYear);

  // the employee allowance (Arbeitnehmer-Pauschbetrag) of a year
  static double allowance(int year) => _y(year) == 2022 ? 1200 : 1230;

  // the wage tax of a year after § 32a EStG, rounded down to full euros
  static int tariff(double zve, {int year = 2026}) {
    final t = _tariffs[_y(year)]!;
    final x = zve.floorToDouble();
    double st;
    if (x <= t[0]) {
      st = 0;
    } else if (x <= t[1]) {
      final y = (x - t[0]) / 10000;
      st = (t[3] * y + 1400) * y;
    } else if (x <= t[2]) {
      final z = (x - t[1]) / 10000;
      st = (t[4] * z + 2397) * z + t[5];
    } else if (x <= 277825) {
      st = 0.42 * x - t[6];
    } else {
      st = 0.45 * x - t[7];
    }
    return st.floor();
  }

  // the employee's care insurance rate
  static double careRate({required int children, required bool childlessSurcharge, bool saxony = false}) {
    var r = saxony ? 0.023 : 0.018;
    if (children == 0 && childlessSurcharge) r += 0.006;
    if (children >= 2) r -= 0.0025 * (math.min(children, 5) - 1);
    return r;
  }

  // the taxes of one year of [income], with the given Werbungskosten (at
  // least the 1,230 € allowance). Used for the payslip (one month as a year)
  // and for the tax return estimate (the real year, real costs).
  static ({double tax, double soli, double church}) yearTax(
    double income, {
    int taxClass = 1,
    int children = 0,
    int? age,
    bool church = false,
    String state = '',
    double additional = averageAdditional,
    bool student = false,
    double werbungskosten = 1230,
    int year = 2026,
  }) {
    // shortcut: social security caps and rates and the single-parent relief stay 2026 for earlier
    // years; they shift the result by a few euros a month, upgrade if past-year estimates must be exact
    final saxony = state.toLowerCase().startsWith('sachsen') && !state.toLowerCase().contains('anhalt');
    final capKv = math.min(income, bbgKvPv), capRv = math.min(income, bbgRvAv);
    final childless = children == 0 && (age == null || age >= 23);
    final care = careRate(children: children, childlessSurcharge: childless, saxony: saxony);

    // Vorsorgepauschale (PAP 2026: UPEVP, MVSPKVPV, MVSPHB)
    final vspR = capRv * rv;
    final vspKvPv = student ? 0.0 : capKv * (kvReduced + additional / 200 + care);
    final vspAlv = student ? 0.0 : capRv * av;
    final vspHb = math.min(1900.0, vspAlv + vspKvPv);
    final vsp = math.max(vspR + vspKvPv, vspR + vspHb).ceilToDouble();

    // Werbungskosten (at least the allowance), Sonderausgaben 36 €, single parents (II)
    final efa = taxClass == 2 ? 4260.0 + 240.0 * math.max(0, children - 1) : 0.0;
    final zve = math.max(0.0, income - math.max(allowance(year), werbungskosten) - 36 - efa - vsp);
    final split = taxClass == 3 ? 2 : 1;
    final tax = (tariff(zve / split, year: year) * split).toDouble();

    // solidarity surcharge with its threshold and the softening zone
    final free = _solzFree[_y(year)]! * split;
    final soli = tax <= free ? 0.0 : math.min(tax * 0.055, (tax - free) * 0.119);
    final bwBy = RegExp(r'baden|bayern|bw\b|by\b', caseSensitive: false).hasMatch(state);
    final kist = church ? tax * (bwBy ? 0.08 : 0.09) : 0.0;
    return (tax: tax, soli: soli, church: kist);
  }

  static NetResult compute(
    double grossMonth, {
    int taxClass = 1,
    int children = 0,
    int? age,
    bool church = false,
    String state = '',
    double additional = averageAdditional,
    bool student = false,
  }) {
    final notes = <String>[];
    final saxony = state.toLowerCase().startsWith('sachsen') && !state.toLowerCase().contains('anhalt');
    if (taxClass < 1 || taxClass > 4) {
      notes.add('Steuerklasse $taxClass rechnet Ahead nicht genau; gerechnet wie Klasse I.');
      taxClass = 1;
    }
    if (grossMonth <= minijob) {
      // a mini job: no wage tax for the employee, 3.6 % pension unless exempted
      final pension = grossMonth * 0.036;
      return NetResult(
        gross: grossMonth,
        wageTax: 0,
        soli: 0,
        churchTax: 0,
        pension: pension,
        unemployment: 0,
        health: 0,
        care: 0,
        notes: ['Minijob bis 603 €: keine Lohnsteuer, 3,6 % Rentenbeitrag, außer du lässt dich befreien.'],
      );
    }
    if (!student && grossMonth <= midijobTop) {
      notes.add('Übergangsbereich bis 2.000 €: Die echten Sozialabgaben sind etwas niedriger, '
          'das Netto also etwas höher als hier.');
    }

    final year = grossMonth * 12;
    final capKv = math.min(year, bbgKvPv), capRv = math.min(year, bbgRvAv);
    final childless = children == 0 && (age == null || age >= 23);
    final care = careRate(children: children, childlessSurcharge: childless, saxony: saxony);

    final t = yearTax(year,
        taxClass: taxClass, children: children, age: age, church: church, state: state, additional: additional, student: student);
    final tax = t.tax, soli = t.soli, kist = t.church;
    if (church && children > 0) notes.add('Mit Kindern ist die Kirchensteuer etwas niedriger als hier.');

    double month(double v) => (v / 12 * 100).floor() / 100;
    return NetResult(
      gross: grossMonth,
      wageTax: month(tax),
      soli: month(soli),
      churchTax: month(kist),
      pension: capRv / 12 * rv,
      unemployment: student ? 0 : capRv / 12 * av,
      health: student ? 0 : capKv / 12 * (kvGeneral + additional / 200),
      care: student ? 0 : capKv / 12 * care,
      notes: [
        ...notes,
        if (student) 'Werkstudent: nur Rentenversicherung, keine Kranken-, Pflege- und Arbeitslosenversicherung.',
      ],
    );
  }
}

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

  // the wage tax of a year after § 32a EStG 2026, rounded down to full euros
  static int tariff(double zve) {
    final x = zve.floorToDouble();
    double st;
    if (x <= 12348) {
      st = 0;
    } else if (x <= 17799) {
      final y = (x - 12348) / 10000;
      st = (914.51 * y + 1400) * y;
    } else if (x <= 69878) {
      final z = (x - 17799) / 10000;
      st = (173.10 * z + 2397) * z + 1034.87;
    } else if (x <= 277825) {
      st = 0.42 * x - 11135.63;
    } else {
      st = 0.45 * x - 19470.38;
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
  }) {
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

    // Werbungskosten (at least 1,230 €), Sonderausgaben 36 €, single parents (II)
    final efa = taxClass == 2 ? 4260.0 + 240.0 * math.max(0, children - 1) : 0.0;
    final zve = math.max(0.0, income - math.max(1230.0, werbungskosten) - 36 - efa - vsp);
    final split = taxClass == 3 ? 2 : 1;
    final tax = (tariff(zve / split) * split).toDouble();

    // solidarity surcharge with its threshold and the softening zone
    final free = solzFree * split;
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
      notes.add('Steuerklasse $taxClass rechnet Buddy nicht genau; gerechnet wie Klasse I.');
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

// Light Altersvorsorge: Rentenlücke from a few inputs + depot (not the
// Notgroschen). Not advice — an orientation number so Buddy can talk about it.
import 'package:hive/hive.dart';
import '../models/goal.dart';
import '../models/holding.dart';

class VorsorgeInput {
  final int age; // years
  final int retireAge;
  final int desiredNetCents; // monthly net wanted in retirement
  final int statutoryCents; // expected gesetzliche Rente / month (from DRV or estimate)
  final int bavCents; // Betriebsrente / month
  final int riesterCents; // Riester / Rürup payout estimate / month
  final int extraCapitalCents; // -1 = depot only; >=0 = manual override
  final bool includeGoals; // optional: open goals (except Notgroschen) as capital

  const VorsorgeInput({
    this.age = 30,
    this.retireAge = 67,
    this.desiredNetCents = 200000, // 2.000 €
    this.statutoryCents = 0,
    this.bavCents = 0,
    this.riesterCents = 0,
    this.extraCapitalCents = -1, // -1 = derive
    this.includeGoals = false,
  });

  Map<String, dynamic> toMap() => {
        'age': age,
        'retireAge': retireAge,
        'desiredNetCents': desiredNetCents,
        'statutoryCents': statutoryCents,
        'bavCents': bavCents,
        'riesterCents': riesterCents,
        'extraCapitalCents': extraCapitalCents,
        'includeGoals': includeGoals,
      };

  factory VorsorgeInput.fromMap(Map? m) {
    if (m == null) return const VorsorgeInput();
    return VorsorgeInput(
      age: (m['age'] as num?)?.toInt() ?? 30,
      retireAge: (m['retireAge'] as num?)?.toInt() ?? 67,
      desiredNetCents: (m['desiredNetCents'] as num?)?.toInt() ?? 200000,
      statutoryCents: (m['statutoryCents'] as num?)?.toInt() ?? 0,
      bavCents: (m['bavCents'] as num?)?.toInt() ?? 0,
      riesterCents: (m['riesterCents'] as num?)?.toInt() ?? 0,
      extraCapitalCents: (m['extraCapitalCents'] as num?)?.toInt() ?? -1,
      includeGoals: m['includeGoals'] as bool? ?? false,
    );
  }

  VorsorgeInput copyWith({
    int? age,
    int? retireAge,
    int? desiredNetCents,
    int? statutoryCents,
    int? bavCents,
    int? riesterCents,
    int? extraCapitalCents,
    bool? includeGoals,
  }) =>
      VorsorgeInput(
        age: age ?? this.age,
        retireAge: retireAge ?? this.retireAge,
        desiredNetCents: desiredNetCents ?? this.desiredNetCents,
        statutoryCents: statutoryCents ?? this.statutoryCents,
        bavCents: bavCents ?? this.bavCents,
        riesterCents: riesterCents ?? this.riesterCents,
        extraCapitalCents: extraCapitalCents ?? this.extraCapitalCents,
        includeGoals: includeGoals ?? this.includeGoals,
      );
}

class VorsorgeResult {
  final VorsorgeInput input;
  final int capitalCents; // depot (+ optional goals) or override
  final int capitalAsMonthlyCents; // 25y drawdown at 0 %
  final int coveredMonthlyCents;
  final int gapMonthlyCents;
  final int saveExtraMonthlyCents; // PMT at ~4 % real
  final int yearsLeft;

  const VorsorgeResult({
    required this.input,
    required this.capitalCents,
    required this.capitalAsMonthlyCents,
    required this.coveredMonthlyCents,
    required this.gapMonthlyCents,
    required this.saveExtraMonthlyCents,
    required this.yearsLeft,
  });

  bool get gapClosed => gapMonthlyCents <= 0;
  bool get ready => input.statutoryCents > 0 || input.bavCents > 0 || input.riesterCents > 0;
}

class Vorsorge {
  static const drawYears = 25;
  static const realReturn = 0.04;
  static const estimateShare = 0.45; // rough mid-career share of net → statutory

  static Box get _box => Hive.box('settings');

  static VorsorgeInput load() => VorsorgeInput.fromMap(_box.get('vorsorge') as Map?);

  static Future<void> save(VorsorgeInput input) => _box.put('vorsorge', input.toMap());

  // only after the user entered at least one pension building block
  static bool get configured {
    final m = _box.get('vorsorge');
    if (m is! Map) return false;
    final i = VorsorgeInput.fromMap(m);
    return i.statutoryCents > 0 || i.bavCents > 0 || i.riesterCents > 0;
  }

  static bool _isEmergencyGoal(Goal g) {
    final n = g.name.toLowerCase();
    return n.contains('notgroschen') || n.contains('notreserve') || n.contains('polster');
  }

  static int capitalFrom({required List<Holding> holdings, required List<Goal> goals, required VorsorgeInput input}) {
    if (input.extraCapitalCents >= 0) return input.extraCapitalCents;
    var sum = 0;
    for (final h in holdings) {
      sum += h.valueCents;
    }
    if (input.includeGoals) {
      for (final g in goals) {
        if (!g.reached && !_isEmergencyGoal(g)) sum += g.savedCents;
      }
    }
    return sum;
  }

  // estimate gesetzliche Rente from net salary (very rough; user should replace with DRV)
  static int estimateStatutoryFromNet(int monthlyNetCents) => (monthlyNetCents * estimateShare).round();

  static VorsorgeResult build({
    required VorsorgeInput input,
    required List<Holding> holdings,
    required List<Goal> goals,
  }) {
    final years = (input.retireAge - input.age).clamp(0, 50);
    final capital = capitalFrom(holdings: holdings, goals: goals, input: input);
    final months = drawYears * 12;
    final capitalMonthly = months <= 0 ? 0 : capital ~/ months;
    final covered = input.statutoryCents + input.bavCents + input.riesterCents + capitalMonthly;
    final gap = (input.desiredNetCents - covered).clamp(0, 1 << 30);
    final needCapital = gap * months;
    final saveExtra = years <= 0 || needCapital <= 0
        ? 0
        : _pmt(needCapital, years * 12, realReturn / 12);
    return VorsorgeResult(
      input: input,
      capitalCents: capital,
      capitalAsMonthlyCents: capitalMonthly,
      coveredMonthlyCents: covered,
      gapMonthlyCents: gap,
      saveExtraMonthlyCents: saveExtra,
      yearsLeft: years,
    );
  }

  static int _pmt(int future, int n, double r) {
    if (n <= 0) return future;
    if (r <= 0) return (future / n).ceil();
    final factor = (1 + r);
    var pow = 1.0;
    for (var i = 0; i < n; i++) {
      pow *= factor;
    }
    return ((future * r) / (pow - 1)).ceil();
  }
}

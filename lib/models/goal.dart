// A savings goal: a name, a target amount, how much is put aside already
// and an optional date to reach it by.
class Goal {
  final String id;
  final String name;
  final String emoji;
  final int targetCents;
  int savedCents;
  final DateTime? deadline;
  final DateTime createdAt;

  // saving on autopilot: a fixed amount each month and/or rounding up
  // every expense to the full euro
  int monthlyCents;
  String? lastMonthly; // "2026-10": the month the fixed amount was last added
  bool roundUp;
  DateTime? roundUpSince;
  List<String> roundedIds; // expenses already rounded up

  Goal({
    required this.id,
    required this.name,
    required this.emoji,
    required this.targetCents,
    this.savedCents = 0,
    this.deadline,
    required this.createdAt,
    this.monthlyCents = 0,
    this.lastMonthly,
    this.roundUp = false,
    this.roundUpSince,
    List<String>? roundedIds,
  }) : roundedIds = roundedIds ?? [];

  bool get automated => monthlyCents > 0 || roundUp;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'targetCents': targetCents,
        'savedCents': savedCents,
        'deadline': deadline?.millisecondsSinceEpoch,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'monthlyCents': monthlyCents,
        'lastMonthly': lastMonthly,
        'roundUp': roundUp,
        'roundUpSince': roundUpSince?.millisecondsSinceEpoch,
        'roundedIds': roundedIds,
      };

  factory Goal.fromMap(Map<String, dynamic> m) => Goal(
        id: m['id'],
        name: m['name'],
        emoji: m['emoji'] ?? '🎯',
        targetCents: (m['targetCents'] as num).toInt(),
        savedCents: (m['savedCents'] as num? ?? 0).toInt(),
        deadline: m['deadline'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['deadline']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt']),
        monthlyCents: (m['monthlyCents'] as num? ?? 0).toInt(),
        lastMonthly: m['lastMonthly'] as String?,
        roundUp: m['roundUp'] as bool? ?? false,
        roundUpSince: m['roundUpSince'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['roundUpSince']),
        roundedIds: ((m['roundedIds'] as List?) ?? const []).cast<String>().toList(),
      );

  int get remainingCents => (targetCents - savedCents).clamp(0, targetCents);
  double get progress => targetCents == 0 ? 0 : (savedCents / targetCents).clamp(0.0, 1.0);
  bool get reached => savedCents >= targetCents;

  // whole months left until the deadline (at least 1), or null without one
  int? monthsLeft(DateTime now) {
    final d = deadline;
    if (d == null) return null;
    final months = (d.year - now.year) * 12 + d.month - now.month;
    return months < 1 ? 1 : months;
  }

  // what has to be put aside per month to make the deadline
  int? monthlyNeeded(DateTime now) {
    final m = monthsLeft(now);
    return m == null ? null : (remainingCents / m).ceil();
  }
}

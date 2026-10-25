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

  Goal({
    required this.id,
    required this.name,
    required this.emoji,
    required this.targetCents,
    this.savedCents = 0,
    this.deadline,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'targetCents': targetCents,
        'savedCents': savedCents,
        'deadline': deadline?.millisecondsSinceEpoch,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Goal.fromMap(Map<String, dynamic> m) => Goal(
        id: m['id'],
        name: m['name'],
        emoji: m['emoji'] ?? '🎯',
        targetCents: (m['targetCents'] as num).toInt(),
        savedCents: (m['savedCents'] as num? ?? 0).toInt(),
        deadline: m['deadline'] == null ? null : DateTime.fromMillisecondsSinceEpoch(m['deadline']),
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt']),
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

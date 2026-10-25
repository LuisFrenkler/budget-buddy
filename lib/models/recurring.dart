// A rule that automatically creates a transaction on a fixed schedule
// (e.g. salary monthly, Netflix monthly). Generated transactions are normal
// transactions; the rule itself is never counted as one.
class RecurringRule {
  final String id;
  final int amountCents;
  final String category;
  final bool isIncome;
  final String? note;
  final String interval;     // 'täglich' | 'wöchentlich' | 'monatlich' | 'jährlich'
  final DateTime startDate;  // date of the first occurrence
  DateTime? lastRun;         // last date a transaction was generated for
  bool active;

  RecurringRule({
    required this.id,
    required this.amountCents,
    required this.category,
    required this.isIncome,
    this.note,
    required this.interval,
    required this.startDate,
    this.lastRun,
    this.active = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amountCents': amountCents,
      'category': category,
      'isIncome': isIncome,
      'note': note,
      'interval': interval,
      'startDate': startDate.millisecondsSinceEpoch,
      'lastRun': lastRun?.millisecondsSinceEpoch,
      'active': active,
    };
  }

  factory RecurringRule.fromMap(Map<String, dynamic> map) {
    return RecurringRule(
      id: map['id'],
      amountCents: (map['amountCents'] as num).toInt(),
      category: map['category'],
      isIncome: map['isIncome'],
      note: map['note'],
      interval: map['interval'],
      startDate: DateTime.fromMillisecondsSinceEpoch(map['startDate']),
      lastRun: map['lastRun'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastRun'])
          : null,
      active: map['active'] ?? true,
    );
  }
}

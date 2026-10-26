class Budget {
  final String category;
  final int limitCents;   // budget limit in cents
  int spentCents;         // amount spent in cents (computed from transactions)
  final DateTime startDate;
  final DateTime endDate;

  Budget({
    required this.category,
    required this.limitCents,
    this.spentCents = 0,
    required this.startDate,
    required this.endDate,
  });

  // convert to map for saving to hive
  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'limitCents': limitCents,
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate.millisecondsSinceEpoch,
    };
  }

  // create from hive map
  factory Budget.fromMap(Map<String, dynamic> map) {
    return Budget(
      category: map['category'],
      // read new cent format if present, otherwise migrate the old
      // double-euro format ('limit') from existing stored data
      limitCents: map['limitCents'] != null
          ? (map['limitCents'] as num).toInt()
          : ((map['limit'] as num).toDouble() * 100).round(),
      startDate: DateTime.fromMillisecondsSinceEpoch(map['startDate']),
      endDate: DateTime.fromMillisecondsSinceEpoch(map['endDate']),
    );
  }

  // how much is left (limit minus spent), in cents
  int get remainingCents => limitCents - spentCents;

  // progress as a fraction (0.0 to 1.0)
  double get progress {
    if (limitCents == 0) return 0;
    return (spentCents / limitCents).clamp(0.0, 1.0);
  }

  // spent as a whole percentage, may pass 100; 0 for a budget without limit
  int get percentUsed => limitCents <= 0 ? 0 : (spentCents * 100 / limitCents).round();

  // true if over budget
  bool get isOver => spentCents > limitCents;

  // the month this budget covers
  bool covers(DateTime day) => !day.isBefore(startDate) && day.isBefore(endDate.add(const Duration(days: 1)));

  // formatted date range, e.g. "1.10.–31.10.2026"
  String get dateRange {
    return '${startDate.day}.${startDate.month}.–${endDate.day}.${endDate.month}.${endDate.year}';
  }
}

// German date labels used across the app.
class Dates {
  static const months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
                         'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
  static const shortMonths = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni',
                              'Juli', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.'];

  static const weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];

  // e.g. "Montag, 5. Januar 2026"
  static String long(DateTime d) => '${weekdays[d.weekday - 1]}, ${full(d)}';

  // e.g. "5. Jan."
  static String dayMonth(DateTime d) => '${d.day}. ${shortMonths[d.month - 1]}';

  // e.g. "5. Januar 2026"
  static String full(DateTime d) => '${d.day}. ${months[d.month - 1]} ${d.year}';

  // e.g. "Oktober" in the current year, otherwise "Oktober 2025"
  static String month(DateTime d) =>
      d.year == DateTime.now().year ? months[d.month - 1] : '${months[d.month - 1]} ${d.year}';

  // when a price or sync was fresh: "heute, 14:32", "gestern, 09:05" or "5. Jan."
  static String stand(DateTime d) {
    final day = relativeDay(d);
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return day == 'Heute' || day == 'Gestern' ? '${day.toLowerCase()}, $time' : day;
  }

  // "Heute", "Gestern" or e.g. "5. Jan."
  static String relativeDay(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Gestern';
    return dayMonth(d);
  }
}

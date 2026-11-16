// Date labels used across the app, in the app language.
import '../l10n/l10n.dart';

class Dates {
  static const _deMonths = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
                            'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
  static const _deShort = ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni',
                           'Juli', 'Aug.', 'Sep.', 'Okt.', 'Nov.', 'Dez.'];
  static const _deDays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
  static const _enMonths = ['January', 'February', 'March', 'April', 'May', 'June',
                            'July', 'August', 'September', 'October', 'November', 'December'];
  static const _enShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _enDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  static List<String> get months => L10n.isDe ? _deMonths : _enMonths;
  static List<String> get shortMonths => L10n.isDe ? _deShort : _enShort;
  static List<String> get weekdays => L10n.isDe ? _deDays : _enDays;

  // German "5." vs English "5"
  static String _day(DateTime d) => L10n.isDe ? '${d.day}.' : '${d.day}';

  // e.g. "Montag, 5. Januar 2026"
  static String long(DateTime d) => '${weekdays[d.weekday - 1]}, ${full(d)}';

  // e.g. "5. Jan."
  static String dayMonth(DateTime d) => '${_day(d)} ${shortMonths[d.month - 1]}';

  // e.g. "5. Januar 2026"
  static String full(DateTime d) => '${_day(d)} ${months[d.month - 1]} ${d.year}';

  // e.g. "Oktober" in the current year, otherwise "Oktober 2025"
  static String month(DateTime d) =>
      d.year == DateTime.now().year ? months[d.month - 1] : '${months[d.month - 1]} ${d.year}';

  // when a price or sync was fresh: "heute, 14:32", "gestern, 09:05" or "5. Jan."
  static String stand(DateTime d) {
    final day = relativeDay(d);
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return day == tr('Heute') || day == tr('Gestern') ? '${day.toLowerCase()}, $time' : day;
  }

  // "Heute", "Gestern" or e.g. "5. Jan."
  static String relativeDay(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return tr('Heute');
    if (diff == 1) return tr('Gestern');
    return dayMonth(d);
  }
}

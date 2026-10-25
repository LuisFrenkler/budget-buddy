// Turns a quick note like "Döner 8,50 gestern" or "Gehalt 2.850 am 1.10."
// into a booking, instantly and offline. Buddy (the AI) refines it when
// available; this parser makes the preview appear while typing.
import 'categorizer.dart';

class ParsedBooking {
  final int cents;
  final bool isIncome;
  final String category;
  final String note;
  final DateTime date;
  const ParsedBooking(this.cents, this.isIncome, this.category, this.note, this.date);
}

class QuickParser {
  // everyday words people type, on top of the merchant keywords
  static const _casual = {
    'Essen & Trinken': ['döner', 'pizza', 'burger', 'kaffee', 'coffee', 'essen', 'mittag', 'abendessen', 'frühstück',
      'bier', 'bar', 'kneipe', 'sushi', 'eis', 'snack', 'mensa', 'lieferando'],
    'Lebensmittel': ['einkauf', 'einkaufen', 'supermarkt', 'lebensmittel', 'wocheneinkauf', 'getränke'],
    'Transport': ['tanken', 'benzin', 'diesel', 'taxi', 'bahn', 'ticket', 'zug', 'bus', 'parken', 'flug', 'scooter'],
    'Unterhaltung': ['kino', 'konzert', 'spiel', 'game', 'festival', 'party', 'club', 'streaming'],
    'Wohnen': ['miete', 'strom', 'internet', 'handy', 'möbel', 'deko'],
    'Kleidung': ['schuhe', 'jacke', 'hose', 'shirt', 'kleid', 'pulli', 'klamotten', 'sneaker'],
    'Gesundheit': ['apotheke', 'arzt', 'medikament', 'gym', 'fitness', 'friseur', 'zahnarzt'],
    'Bildung': ['buch', 'bücher', 'kurs', 'uni', 'seminar', 'schule'],
  };
  static const _incomeWords = {
    'Gehalt': ['gehalt', 'lohn'],
    'Nebenjob': ['nebenjob', 'nachhilfe', 'minijob', 'babysitten', 'trinkgeld', 'freelance'],
    'Investition': ['dividende', 'zinsen'],
    'Geschenk': ['geschenk', 'geschenkt', 'geburtstag'],
    'Sonstiges': ['bekommen', 'erhalten', 'zurück', 'erstattung', 'verkauft', 'einnahme'],
  };
  static const _weekdays = ['montag', 'dienstag', 'mittwoch', 'donnerstag', 'freitag', 'samstag', 'sonntag'];
  static const _filler = {'für', 'bei', 'im', 'in', 'am', 'beim', 'euro', 'eur', '€', 'vom', 'von', 'mit', 'und', 'heute',
    'gestern', 'vorgestern', 'letzten', 'letzte', 'letztes'};

  // the amount: "8,50", "8.50", "1.200,50", "12€"; never a date like "1.10."
  static final _amount = RegExp(r'(?<![\d.,])(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d{1,2})|\.(\d{1,2}))?(?![\d.])\s*(?:€|eur\b|euro\b)?',
      caseSensitive: false);
  static final _dayMonth = RegExp(r'(?<!\d)(\d{1,2})\.(\d{1,2})\.(\d{2,4})?');

  static ParsedBooking? parse(String input, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var text = input.trim();
    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    // date first, so "am 3.10." is not read as an amount
    var date = DateTime(today.year, today.month, today.day, 12);
    final dm = _dayMonth.firstMatch(text);
    if (dm != null) {
      final day = int.parse(dm.group(1)!), month = int.parse(dm.group(2)!);
      var year = dm.group(3) == null ? today.year : int.parse(dm.group(3)!);
      if (year < 100) year += 2000;
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        date = DateTime(year, month, day, 12);
        // "am 28.12." typed in January means last December
        if (dm.group(3) == null && date.isAfter(today)) date = DateTime(year - 1, month, day, 12);
      }
      text = text.replaceRange(dm.start, dm.end, ' ');
    } else if (lower.contains('vorgestern')) {
      date = DateTime(date.year, date.month, date.day - 2, 12);
    } else if (lower.contains('gestern')) {
      date = DateTime(date.year, date.month, date.day - 1, 12);
    } else {
      for (int i = 0; i < 7; i++) {
        if (RegExp('\\b${_weekdays[i]}\\b').hasMatch(lower)) {
          // the most recent such day, today included; calendar days, so a
          // daylight-saving change in between cannot shift the hour
          final back = (today.weekday - 1 - i) % 7;
          date = DateTime(date.year, date.month, date.day - back, 12);
          break;
        }
      }
    }

    final m = _amount.firstMatch(text);
    if (m == null) return null;
    final euros = int.parse(m.group(1)!.replaceAll('.', ''));
    final decimals = m.group(2) ?? m.group(3);
    final cents = euros * 100 + (decimals == null ? 0 : int.parse(decimals.padRight(2, '0')));
    if (cents <= 0) return null;
    text = text.replaceRange(m.start, m.end, ' ');

    String? incomeCategory;
    for (final e in _incomeWords.entries) {
      if (e.value.any((w) => RegExp('\\b$w').hasMatch(lower))) {
        incomeCategory = e.key;
        break;
      }
    }
    final isIncome = incomeCategory != null || input.trim().startsWith('+');

    // the note: what is left without filler words
    final words = text
        .replaceAll(RegExp(r'[+€]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_filler.contains(w.toLowerCase()) && !_weekdays.contains(w.toLowerCase()))
        .toList();
    var note = words.join(' ');
    if (note.isNotEmpty) note = note[0].toUpperCase() + note.substring(1);

    String category;
    if (isIncome) {
      category = incomeCategory ?? 'Sonstiges';
    } else {
      category = Categorizer.guess(lower, isIncome: false);
      if (category == 'Sonstiges') {
        for (final e in _casual.entries) {
          if (e.value.any((w) => RegExp('\\b$w').hasMatch(lower))) {
            category = e.key;
            break;
          }
        }
      }
    }
    return ParsedBooking(cents, isIncome, category, note, date);
  }
}

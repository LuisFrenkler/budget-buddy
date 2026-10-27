// Reads the CSV export of a German bank (Sparkasse, ING, DKB, N26,
// comdirect, Volksbank, …) without the user having to prepare anything.
//
// Every bank names and orders its columns differently, adds lines before
// the header, uses ; or , and German or English numbers. So the importer
// looks for the header line itself and picks the columns by their names:
// a date ("Buchungstag", "Buchung", "Date"), an amount ("Betrag", "Umsatz",
// "Amount (EUR)") and a counterparty ("Empfänger", "Auftraggeber",
// "Payee"). The category is guessed like for bank sync, and a merchant the
// user sorted before keeps their category.
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../utils/money.dart';
import 'categorizer.dart';
import 'category_rules.dart';

class BankCsvResult {
  final List<Transaction> transactions;
  final int skipped; // lines that looked like bookings but could not be read
  final int duplicates; // already in the app
  final String? bank; // a recognised bank, for the message
  const BankCsvResult(this.transactions, this.skipped, this.duplicates, this.bank);
}

class BankCsvImporter {
  static const _dateNames = ['buchungstag', 'buchungsdatum', 'buchung', 'datum', 'date', 'valutadatum', 'wertstellung'];
  static const _amountNames = ['betrag (eur)', 'betrag', 'umsatz in eur', 'umsatz', 'amount (eur)', 'amount', 'betrag (€)'];
  static const _partyNames = [
    'name zahlungsbeteiligter',
    'beguenstigter/zahlungspflichtiger',
    'begünstigter/zahlungspflichtiger',
    'auftraggeber / begünstigter',
    'auftraggeber/empfänger',
    'zahlungsempfänger',
    'empfänger',
    'auftraggeber',
    'payee',
    'counterparty',
    'name',
  ];
  static const _purposeNames = ['verwendungszweck', 'buchungstext', 'payment reference', 'beschreibung', 'zweck'];
  static const _typeNames = ['soll/haben', 'soll / haben'];

  static String _clean(String s) => s.trim().replaceAll('"', '').replaceAll('﻿', '').toLowerCase();

  // splits one line at the delimiter, respecting "quoted;fields"
  static List<String> _split(String line, String sep) {
    final out = <String>[];
    final cur = StringBuffer();
    var quoted = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') {
        quoted = !quoted;
      } else if (c == sep && !quoted) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    out.add(cur.toString());
    return out.map((s) => s.trim()).toList();
  }

  static int _find(List<String> header, List<String> names) {
    for (final n in names) {
      final i = header.indexOf(n);
      if (i >= 0) return i;
    }
    for (final n in names) {
      final i = header.indexWhere((h) => h.startsWith(n));
      if (i >= 0) return i;
    }
    return -1;
  }

  // 05.01.2026, 05.01.26, 2026-01-05 or 05/01/2026
  static DateTime? _date(String s) {
    final t = s.replaceAll('"', '').trim();
    var m = RegExp(r'^(\d{1,2})[./](\d{1,2})[./](\d{2,4})$').firstMatch(t);
    if (m != null) {
      var y = int.parse(m.group(3)!);
      if (y < 100) y += 2000;
      return DateTime(y, int.parse(m.group(2)!), int.parse(m.group(1)!));
    }
    m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
    if (m != null) return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    return null;
  }

  static String? _bankOf(String content) {
    final c = content.toLowerCase();
    for (final (key, name) in const [
      ('sparkasse', 'Sparkasse'),
      ('beguenstigter/zahlungspflichtiger', 'Sparkasse'),
      ('ing-diba', 'ING'),
      ('auftraggeber/empfänger', 'ING'),
      ('dkb', 'DKB'),
      ('n26', 'N26'),
      ('payee', 'N26'),
      ('comdirect', 'comdirect'),
      ('volksbank', 'Volksbank'),
      ('name zahlungsbeteiligter', 'Volksbank'),
    ]) {
      if (c.contains(key)) return name;
    }
    return null;
  }

  // true when the content looks like a bank export rather than our own format
  static bool looksLikeBank(String content) {
    final head = content.split('\n').take(30).join('\n').toLowerCase();
    return _amountNames.any(head.contains) && _dateNames.any(head.contains) && !head.startsWith('datum;kategorie;');
  }

  static BankCsvResult parse(String content, {List<Transaction> existing = const []}) {
    final lines = content.replaceAll('\r', '').split('\n');
    // the header: the first of the first 30 lines with a date and an amount column
    var headerAt = -1;
    var sep = ';';
    List<String> header = const [];
    for (var i = 0; i < lines.length && i < 30; i++) {
      for (final s in const [';', ',', '\t']) {
        final h = _split(lines[i], s).map(_clean).toList();
        if (h.length >= 3 && _find(h, _dateNames) >= 0 && _find(h, _amountNames) >= 0) {
          headerAt = i;
          sep = s;
          header = h;
          break;
        }
      }
      if (headerAt >= 0) break;
    }
    if (headerAt < 0) return const BankCsvResult([], 0, 0, null);

    final iDate = _find(header, _dateNames);
    final iAmount = _find(header, _amountNames);
    final iParty = _find(header, _partyNames);
    final iPurpose = _find(header, _purposeNames);
    final iType = _find(header, _typeNames);

    // what is already there, so importing the same file twice adds nothing
    // how often each booking is already there: two equal coffees on one day
    // are two bookings, and only as many as exist count as duplicates
    final known = <String, int>{};
    for (final t in existing) {
      final k = '${t.date.year}-${t.date.month}-${t.date.day}|${t.amountCents}|${t.isIncome}';
      known[k] = (known[k] ?? 0) + 1;
    }
    final out = <Transaction>[];
    var skipped = 0, duplicates = 0;
    for (var i = headerAt + 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final f = _split(lines[i], sep);
      if (f.length <= iAmount || f.length <= iDate) {
        skipped++;
        continue;
      }
      final date = _date(f[iDate]);
      var cents = Money.parseToCents(f[iAmount].replaceAll('"', ''));
      if (date == null || cents == null || cents == 0) {
        skipped++;
        continue;
      }
      // some banks give the sign in its own column ("S" = debit)
      if (iType >= 0 && iType < f.length && f[iType].trim().toUpperCase().startsWith('S')) cents = -cents.abs();
      final income = cents > 0;
      final party = iParty >= 0 && iParty < f.length ? f[iParty].replaceAll('"', '').trim() : '';
      final purpose = iPurpose >= 0 && iPurpose < f.length ? f[iPurpose].replaceAll('"', '').trim() : '';
      final title = party.isNotEmpty ? _tidy(party) : (purpose.isNotEmpty ? _tidy(purpose) : 'Buchung');

      final key = '${date.year}-${date.month}-${date.day}|${cents.abs()}|$income';
      if ((known[key] ?? 0) > 0) {
        known[key] = known[key]! - 1;
        duplicates++;
        continue;
      }
      out.add(Transaction(
        id: 'csv_${const Uuid().v4()}',
        amountCents: cents.abs(),
        category: CategoryRules.forName(title, isIncome: income) ??
            Categorizer.guess('$party $purpose', isIncome: income),
        date: date,
        isIncome: income,
        note: title,
      ));
    }
    return BankCsvResult(out, skipped, duplicates, _bankOf(content));
  }

  // legal forms and short brand names keep their usual spelling
  static const _keep = {'gmbh': 'GmbH', 'ag': 'AG', 'kg': 'KG', 'se': 'SE', 'ug': 'UG', 'db': 'DB', 'dm': 'dm',
    'h&m': 'H&M', 'ab': 'AB', 'bv': 'BV', 'ltd': 'Ltd', 'inc': 'Inc', 'eg': 'eG', 'ev': 'e.V.'};

  static String _word(String w) => _keep[w] ?? (w.isEmpty ? w : w[0].toUpperCase() + w.substring(1));

  // "REWE MARKT GMBH SAGT DANKE 1234" -> "Rewe Markt GmbH"
  static String _tidy(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'\b(sagt danke|vielen dank|fil\.?|filiale)\b.*$', caseSensitive: false), '').trim();
    t = t.replaceAll(RegExp(r'\s\d{3,}.*$'), '').trim();
    if (t.length > 40) t = t.substring(0, 40).trim();
    // all caps reads like shouting: title case it
    if (t == t.toUpperCase() && t.length > 3) {
      t = t.toLowerCase().split(' ').map(_word).join(' ');
    }
    return t.isEmpty ? s.trim() : t;
  }
}

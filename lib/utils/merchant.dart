// Normalize bank titles so PayPal/card rails don't hide the real merchant
// (needed for Abos and readable Konto lists).
class Merchant {
  static final _rails = RegExp(
    r'^(paypal|klarna|sumup|stripe|visa|mastercard|amex|kartenzahlung|lastschrift|sepa|apple pay|google pay)\b',
    caseSensitive: false,
  );

  static final _paypalStar = RegExp(r'paypal\s*\*\s*(.+)', caseSensitive: false);
  static final _noise = RegExp(
    r'\b(sagt danke|vielen dank|fil\.?|filiale|europe|s\.?a\.?r\.?l\.?|gmbh|ltd|inc)\b',
    caseSensitive: false,
  );

  // any mandate / creditor / end-to-end style SEPA label (banks invent spellings,
  // "Mandatsreferenz" as well as "Mandantenreferenz")
  static final _sepaCore = RegExp(
    r'mand(?:at|ant)(?:s|en)?[\s\-]*ref(?:erenz)?|'
    r'mref|'
    r'gläubiger[\s\-]?id|glaeubiger[\s\-]?id|creditor[\s\-]?id|cdtr|'
    r'end[\s\-]?to[\s\-]?end|e2e[\s\-]?ref|eref|'
    r'kundenreferenz|zahlungsreferenz|referenznummer|'
    r'verwendungszweck|svwz|'
    r'sepa[\s\-]?lastschrift|core[\s\-]?direct[\s\-]?debit|'
    r'\biban\b|\bbic\b|abwa\b',
    caseSensitive: false,
  );

  // SEPA label + following token / code
  static final _sepaLabel = RegExp(
    r'\b(?:'
    r'mand(?:at|ant)(?:s|en)?[\s\-]*ref(?:erenz)?\.?|mref|'
    r'gläubiger[\s\-]?id|glaeubiger[\s\-]?id|creditor[\s\-]?id|cdtr|'
    r'end[\s\-]?to[\s\-]?end(?:[\s\-]?(?:id|ref(?:erenz)?))?|e2e[\s\-]?ref\.?|eref|'
    r'kundenreferenz|zahlungsreferenz|referenznummer|'
    r'verwendungszweck|svwz|'
    r'sepa[\s\-]?lastschrift|core[\s\-]?direct[\s\-]?debit|'
    r'iban|bic|abwa'
    r')\b\s*[:.\-=]?\s*[^\s/,|;]*',
    caseSensitive: false,
  );

  static final _sepaOnly = RegExp(
    r'^(?:'
    r'mand(?:at|ant)(?:s|en)?[\s\-]*ref(?:erenz)?\.?|mref|mand(?:at|ant)|'
    r'gläubiger[\s\-]?id|glaeubiger[\s\-]?id|creditor[\s\-]?id|'
    r'kundenreferenz|zahlungsreferenz|referenz(?:nummer)?|verwendungszweck|'
    r'iban|bic|end[\s\-]?to[\s\-]?end|e2e|sepa|lastschrift|bankbuchung|svwz|abwa'
    r')$',
    caseSensitive: false,
  );

  static const _keep = {
    'gmbh': 'GmbH',
    'ag': 'AG',
    'kg': 'KG',
    'se': 'SE',
    'ug': 'UG',
    'db': 'DB',
    'dm': 'dm',
    'h&m': 'H&M',
    'ab': 'AB',
    'bv': 'BV',
    'ltd': 'Ltd',
    'inc': 'Inc',
    'eg': 'eG',
    'ev': 'e.V.',
  };

  static String _word(String w) =>
      _keep[w] ?? (w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}');

  static bool isSepaJunk(String s) {
    final t = s.trim();
    if (t.isEmpty) return true;
    if (_sepaOnly.hasMatch(t)) return true;
    if (_sepaCore.hasMatch(t)) {
      final cleaned = scrub(t);
      if (cleaned.isEmpty || cleaned.length < 3 || _sepaOnly.hasMatch(cleaned)) {
        return true;
      }
      if (RegExp(r'^[\d\W_]+$').hasMatch(cleaned)) return true;
    }
    final first = t.split(RegExp(r'\s+')).first;
    if (_sepaOnly.hasMatch(first)) {
      final rest = t.split(RegExp(r'\s+')).skip(1).join(' ');
      if (rest.isEmpty || RegExp(r'^[\d\W]+$').hasMatch(rest)) return true;
    }
    return false;
  }

  // drop SEPA field labels + their values from bank purpose text
  static String scrub(String s) {
    var t = s;
    for (var i = 0; i < 6; i++) {
      final next = t.replaceAll(_sepaLabel, ' ');
      if (next == t) break;
      t = next;
    }
    t = t.replaceAll(_sepaCore, ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'^[:.\-=]+\s*'), '').trim();
    return t;
  }

  static String tidy(String s) {
    var t = scrub(s);
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t
        .replaceAll(
            RegExp(r'\b(sagt danke|vielen dank|fil\.?|filiale)\b.*$',
                caseSensitive: false),
            '')
        .trim();
    final noNums = t.replaceAll(RegExp(r'\s\d{3,}.*$'), '').trim();
    if (noNums.length >= 3 && !isSepaJunk(noNums)) t = noNums;
    if (t.length > 40) t = t.substring(0, 40).trim();
    if (t == t.toUpperCase() && t.length > 3) {
      t = t.toLowerCase().split(' ').map(_word).join(' ');
    }
    if (isSepaJunk(t)) return '';
    return t.isEmpty ? '' : t;
  }

  // what the UI shows for a stored note (fixes old Mandats-/Mandantenreferenz)
  static String present(String? note, {String fallback = 'Buchung'}) {
    final raw = note?.trim() ?? '';
    if (raw.isEmpty) return fallback;
    if (isSepaJunk(raw)) {
      return fallback == 'Buchung' ? 'Bankbuchung' : fallback;
    }
    final t = tidy(raw);
    if (t.isEmpty) return fallback == 'Buchung' ? 'Bankbuchung' : fallback;
    return t;
  }

  // group key for contracts: stable across PayPal *NETFLIX vs PayPal Europe
  static String key(String note) {
    var t = scrub(note).toLowerCase().trim();
    final star = _paypalStar.firstMatch(t);
    if (star != null) t = star.group(1)!.trim();
    t = t
        .replaceAll(_noise, ' ')
        .replaceAll(RegExp(r'[^a-z0-9äöüß&]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return t;
  }

  static String? _bestChunk(String why) {
    final parts = why
        .split(RegExp(r'[/,|;]|(?:\s{2,})'))
        .map((s) => s.trim())
        .where((s) => s.length > 2 && !isSepaJunk(s));
    for (final p in parts) {
      final t = tidy(p);
      if (t.isNotEmpty) return t;
    }
    final whole = tidy(why);
    return whole.isEmpty ? null : whole;
  }

  // display title from counterparty + purpose
  static String display(
      {required String counterparty, required String purpose}) {
    final party = counterparty.trim();
    final why = scrub(purpose).trim();
    if (party.isNotEmpty &&
        !_rails.hasMatch(party.toLowerCase()) &&
        !isSepaJunk(party)) {
      final t = tidy(party);
      if (t.isNotEmpty) return t;
    }
    if (why.isNotEmpty) {
      final star = _paypalStar.firstMatch(why);
      if (star != null) {
        final t = tidy(star.group(1)!);
        if (t.isNotEmpty) return t;
      }
      final chunk = _bestChunk(why);
      if (chunk != null) return chunk;
    }
    if (party.isNotEmpty && !isSepaJunk(party)) {
      final t = tidy(party);
      if (t.isNotEmpty) return t;
    }
    return 'Bankbuchung';
  }
}

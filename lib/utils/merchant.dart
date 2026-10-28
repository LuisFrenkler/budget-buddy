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

  static String _word(String w) => _keep[w] ?? (w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}');

  static String tidy(String s) {
    var t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    t = t.replaceAll(RegExp(r'\b(sagt danke|vielen dank|fil\.?|filiale)\b.*$', caseSensitive: false), '').trim();
    t = t.replaceAll(RegExp(r'\s\d{3,}.*$'), '').trim();
    if (t.length > 40) t = t.substring(0, 40).trim();
    if (t == t.toUpperCase() && t.length > 3) {
      t = t.toLowerCase().split(' ').map(_word).join(' ');
    }
    return t.isEmpty ? s.trim() : t;
  }

  // group key for contracts: stable across PayPal *NETFLIX vs PayPal Europe
  static String key(String note) {
    var t = note.toLowerCase().trim();
    final star = _paypalStar.firstMatch(t);
    if (star != null) t = star.group(1)!.trim();
    t = t.replaceAll(_noise, ' ').replaceAll(RegExp(r'[^a-z0-9äöüß&]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  // display title from counterparty + purpose
  static String display({required String counterparty, required String purpose}) {
    final party = counterparty.trim();
    final why = purpose.trim();
    if (party.isNotEmpty && !_rails.hasMatch(party.toLowerCase())) return tidy(party);
    // rail or empty party: prefer purpose / PAYPAL *X
    if (why.isNotEmpty) {
      final star = _paypalStar.firstMatch(why);
      if (star != null) return tidy(star.group(1)!);
      // take first meaningful chunk of purpose
      final chunk = why.split(RegExp(r'[/,|]')).map((s) => s.trim()).firstWhere((s) => s.length > 2, orElse: () => why);
      return tidy(chunk);
    }
    if (party.isNotEmpty) return tidy(party);
    return 'Bankbuchung';
  }
}

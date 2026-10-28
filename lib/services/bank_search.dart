// Ranks Enable Banking ASPSPs for the picker. Short queries like "ING" must
// not hit cities that merely contain those letters ("Recklinghausen").
import '../services/backend_service.dart';

class BankSearch {
  // common short names users type vs. the ASPSP's legal name
  static const aliases = <String, List<String>>{
    'dkb': ['deutsche kreditbank', 'dkb'],
    'ing': ['ing-diba', 'ing diba', 'ing-bank', 'ing bank', 'ing'],
    'commerzbank': ['commerzbank'],
    'deutsche bank': ['deutsche bank'],
    'postbank': ['postbank'],
    'comdirect': ['comdirect'],
    'consorsbank': ['consorsbank', 'consors'],
    'n26': ['n26'],
    'c24': ['c24', 'c24 bank'],
    'trade republic': ['trade republic', 'traderepublic'],
    'tr': ['trade republic', 'traderepublic'],
    'scalable': ['scalable capital', 'scalable'],
    'sparkasse': ['sparkasse', 'stadtsparkasse', 'kreissparkasse', 'bezirkssparkasse'],
    'volksbank': ['volksbank', 'raiffeisenbank', 'vr-bank', 'vr bank'],
    'raiffeisen': ['raiffeisenbank', 'volksbank raiffeisen', 'vr-bank'],
    'sparda': ['sparda'],
    'santander': ['santander'],
    'hypovereinsbank': ['hypovereinsbank', 'unicredit'],
    'hvb': ['hypovereinsbank', 'unicredit'],
    'targobank': ['targobank'],
  };

  static List<Bank> filter(List<Bank> banks, String query) {
    final q = _fold(query.trim());
    if (q.isEmpty) return _popularFirst(banks);
    final scored = <(int score, Bank bank)>[];
    for (final b in banks) {
      final s = _score(b, q);
      if (s > 0) scored.add((s, b));
    }
    scored.sort((a, b) {
      final byScore = b.$1.compareTo(a.$1);
      if (byScore != 0) return byScore;
      return a.$2.name.toLowerCase().compareTo(b.$2.name.toLowerCase());
    });
    return [for (final e in scored) e.$2];
  }

  // empty search: well-known retail banks first, then A–Z
  static List<Bank> _popularFirst(List<Bank> banks) {
    const order = [
      'ing',
      'dkb',
      'commerzbank',
      'deutsche bank',
      'comdirect',
      'consorsbank',
      'n26',
      'c24',
      'postbank',
      'trade republic',
      'scalable',
      'sparkasse',
      'volksbank',
    ];
    int rank(Bank b) {
      final hay = _hay(b);
      for (var i = 0; i < order.length; i++) {
        if (_matchesAlias(hay, order[i]) || _wordHas(hay, order[i])) return i;
      }
      return order.length + 1;
    }

    final copy = [...banks];
    copy.sort((a, b) {
      final ra = rank(a), rb = rank(b);
      if (ra != rb) return ra.compareTo(rb);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return copy;
  }

  static int _score(Bank b, String q) {
    final hay = _hay(b);
    final name = _fold(b.name);
    if (name == q) return 1000;
    if (name.startsWith('$q ') || name.startsWith('$q-')) return 900;
    if (_wordHas(hay, q)) return 800;
    // multi-word: every token must match as a word (Sparkasse Köln)
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.length > 1 && tokens.every((t) => _wordHas(hay, t) || _matchesAlias(hay, t))) {
      return 700 + tokens.length * 10;
    }
    if (_matchesAlias(hay, q)) return 650;
    // longer contains is ok ("Commerzbank" in "… AG"); short ones are not
    if (q.length >= 4 && hay.contains(q)) return 200;
    return 0;
  }

  static String _hay(Bank b) {
    final parts = [b.name, if (b.group != null) b.group!, if (b.bic != null) b.bic!];
    return _fold(parts.join(' '));
  }

  static bool _matchesAlias(String hay, String q) {
    final list = aliases[q];
    if (list != null) return list.any((a) => _wordHas(hay, a) || hay.startsWith(a) || hay.contains(' $a'));
    for (final e in aliases.entries) {
      if (!e.value.contains(q)) continue;
      if (e.value.any((a) => _wordHas(hay, a) || hay.contains(a))) return true;
    }
    return false;
  }

  static bool _wordHas(String hay, String needle) {
    if (needle.isEmpty) return false;
    final n = _fold(needle);
    var i = hay.indexOf(n);
    while (i >= 0) {
      final before = i == 0 || !_isWordChar(hay.codeUnitAt(i - 1));
      final after = i + n.length >= hay.length || !_isWordChar(hay.codeUnitAt(i + n.length));
      if (before && after) return true;
      i = hay.indexOf(n, i + 1);
    }
    return false;
  }

  static bool _isWordChar(int c) =>
      (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || c == 0xe4 || c == 0xf6 || c == 0xfc || c == 0xdf;

  static String _fold(String s) => s
      .toLowerCase()
      .replaceAll('ä', 'ae')
      .replaceAll('ö', 'oe')
      .replaceAll('ü', 'ue')
      .replaceAll('ß', 'ss')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

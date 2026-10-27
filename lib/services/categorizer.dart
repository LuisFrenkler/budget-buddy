// Guesses a category for a bank booking from its counterparty and purpose,
// e.g. "REWE Markt GmbH" -> Lebensmittel. Keywords match at the start of a
// word, so "esso" finds "ESSO Station" but not "Espresso".
class Categorizer {
  static const _expense = {
    'Lebensmittel': [
      'rewe', 'edeka', 'lidl', 'aldi', 'netto', 'penny', 'kaufland', 'norma', 'tegut', 'globus',
      'denns', 'alnatura', 'hit markt', 'marktkauf', 'flink', 'picnic',
    ],
    'Essen & Trinken': [
      'lieferando', 'wolt', 'uber eats', 'starbucks', 'mcdonald', 'burger king', 'subway', 'kfc',
      'restaurant', 'cafe', 'café', 'bäckerei', 'backhaus', 'pizza', 'döner', 'vapiano', 'too good to go',
    ],
    'Transport': [
      'db vertrieb', 'deutsche bahn', 'deutschlandticket', 'bvg', 'mvg', 'hvv', 'kvb', 'rmv', 'vrr',
      'flixbus', 'flixtrain', 'shell', 'aral', 'esso', 'jet tankstelle', 'totalenergies', 'tankstelle',
      'uber', 'bolt', 'freenow', 'free now', 'sixt', 'share now', 'miles mobility', 'tier mobility',
      'parkhaus', 'parken', 'adac',
    ],
    'Unterhaltung': [
      'netflix', 'spotify', 'disney', 'prime video', 'dazn', 'sky deutschland', 'wow', 'apple.com',
      'playstation', 'steam', 'nintendo', 'kino', 'cinemaxx', 'cineplex', 'eventim', 'youtube', 'audible',
    ],
    'Wohnen': [
      'miete', 'hausverwaltung', 'wohnungsbau', 'vonovia', 'stadtwerke', 'vattenfall', 'e.on', 'enbw',
      'strom', 'erdgas', 'rundfunk', 'telekom', 'vodafone', 'o2', '1&1', 'congstar', 'ikea', 'obi',
      'hornbach', 'bauhaus', 'hausrat', 'haftpflicht',
    ],
    'Kleidung': [
      'zalando', 'h&m', 'zara', 'about you', 'primark', 'c&a', 'snipes', 'nike', 'adidas', 'uniqlo',
      'peek & cloppenburg', 'deichmann',
    ],
    'Gesundheit': [
      'apotheke', 'docmorris', 'shop apotheke', 'fitness', 'mcfit', 'urban sports', 'john reed', 'arzt',
      'zahnarzt', 'praxis', 'krankenkasse', 'optiker', 'fielmann',
    ],
    'Bildung': [
      'udemy', 'coursera', 'thalia', 'hugendubel', 'universität', 'hochschule', 'semesterbeitrag',
      'studierendenwerk', 'studentenwerk', 'volkshochschule',
    ],
  };

  static const _income = {
    'Gehalt': ['gehalt', 'lohn', 'bezüge', 'besoldung'],
    'Investition': ['dividende', 'zinsen', 'ertrag', 'ausschüttung'],
    'Geschenk': ['geschenk', 'geburtstag'],
  };

  // money between the user's own accounts: savings, a depot, a broker
  static const _transfer = [
    'umbuchung', 'übertrag', 'sparkonto', 'tagesgeld', 'festgeld', 'sparplan', 'trade republic',
    'scalable capital', 'traderepublic', 'eigenes konto',
  ];

  static String guess(String text, {required bool isIncome}) {
    final lower = text.toLowerCase();
    for (final k in _transfer) {
      if (_startsWord(lower, k)) return 'Umbuchung';
    }
    final rules = isIncome ? _income : _expense;
    for (final entry in rules.entries) {
      for (final k in entry.value) {
        if (_startsWord(lower, k)) return entry.key;
      }
    }
    return 'Sonstiges';
  }

  // true when [key] occurs in [text] at the start of a word
  static bool _startsWord(String text, String key) {
    var i = text.indexOf(key);
    while (i >= 0) {
      if (i == 0 || !_isLetter(text.codeUnitAt(i - 1))) return true;
      i = text.indexOf(key, i + 1);
    }
    return false;
  }

  static bool _isLetter(int c) =>
      (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || 'äöüß'.codeUnits.contains(c);
}

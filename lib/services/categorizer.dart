// Guesses a category for a bank booking from its counterparty and purpose,
// e.g. "REWE Markt GmbH" -> Lebensmittel. Keywords match at the start of a
// word, so "esso" finds "ESSO Station" but not "Espresso".
// A card MCC is only used when no keyword hits. Amazon's marketplace sells
// everything, so it stays Sonstiges until the user picks a category; Prime
// and Fresh are specific.
class Categorizer {
  static const _expense = {
    'Lebensmittel': [
      'rewe', 'edeka', 'lidl', 'aldi', 'netto', 'penny', 'kaufland', 'norma', 'tegut', 'globus',
      'denns', 'alnatura', 'hit markt', 'marktkauf', 'flink', 'picnic', 'bringmeister', 'gorillas',
      'getir', 'biopark', 'nahkauf', 'famila', 'budni', 'rossmann', 'dm', 'dm-drogerie', 'dm drogerie',
      'mueller drogerie', 'müller drogerie', 'drogeriemarkt', 'amazon fresh', 'rewe digital', 'edeka24',
      'rewe to go', 'getraenke hoffmann', 'getränke hoffmann', 'beverage', 'cap', 'combi',
    ],
    'Essen & Trinken': [
      'lieferando', 'wolt', 'uber eats', 'ubereats', 'starbucks', 'mcdonald', 'burger king', 'subway', 'kfc',
      'restaurant', 'cafe', 'café', 'cafeteria', 'bäckerei', 'baeckerei', 'backerei', 'backhaus', 'bäcker', 'baecker', 'pizza', 'pizzeria',
      'döner', 'doener', 'vapiano', 'too good to go', 'toogoodtogo', 'nordsee', 'block house',
      'hans im glück', 'five guys', 'dean&david', 'dean & david', 'coffee fellows', 'balzac',
      'backwerk', 'lecrobag', 'sushi', 'imbiss', 'gasthaus', 'brauhaus',
      'dominos', 'domino\'s', 'pizza hut', 'chibo', 'tchibo', 'costa coffee', 'jim block',
    ],
    'Transport': [
      'db vertrieb', 'db fernverkehr', 'db regio', 'db navigator', 'deutsche bahn', 'deutschebahn',
      'deutschlandticket', 'bahn.de', 'bahncard', 'bahn card',
      'bvg', 'mvg', 'hvv', 'kvb', 'rmv', 'vrr', 'vbb', 'ssb', 'kvv',
      'flixbus', 'flixtrain', 'shell', 'aral', 'esso', 'jet', 'jet tankstelle', 'totalenergies', 'tankstelle',
      'omv', 'agip', 'westfalen', 'uber', 'bolt', 'freenow', 'free now', 'sixt', 'share now',
      'miles mobility', 'tier mobility', 'parkhaus', 'parken', 'parking', 'adac', 'lufthansa',
      'eurowings', 'easyjet', 'ryanair', 'booking.com', 'expedia', 'trainline', 'omio', 'blablacar',
      'bla bla car', 'ionity', 'toll collect', 'hem tankstelle', 'star tankstelle', 'q1 tankstelle',
      'clever tanken', 'tankrabatt',
    ],
    'Unterhaltung': [
      'netflix', 'spotify', 'disney+', 'disney plus', 'prime video', 'amazon prime', 'dazn',
      'sky deutschland', 'apple.com/bill', 'apple.com', 'apple music', 'itunes', 'playstation',
      'xbox', 'steam', 'nintendo', 'epic games', 'kino', 'cinemaxx', 'cineplex', 'eventim',
      'ticketmaster', 'kinopolis', 'youtube', 'audible', 'twitch', 'patreon', 'chatgpt', 'openai', 'google one',
      'paramount', 'joyn', 'rtl+', 'wow', 'deezer', 'humble bundle',
      'mediamarkt', 'media markt', 'saturn', 'apple store', 'steam games',
    ],
    'Wohnen': [
      'miete', 'hausverwaltung', 'wohnungsbau', 'vonovia', 'deutsche wohnen', 'leg immobilien',
      'stadtwerke', 'vattenfall', 'e.on', 'enbw', 'strom', 'erdgas', 'gasversorgung', 'rundfunk',
      'beitragsservice', 'telekom', 'vodafone', 'o2', 'o2.de', '1&1', '1und1', 'congstar', 'freenet',
      'ikea', 'obi', 'hornbach', 'bauhaus', 'toom', 'hellweg', 'hausrat', 'haftpflicht',
      'nebenkosten', 'wohnung', 'kaltmiete', 'warmmiete', 'wohnungsmiete', 'hausgeld', 'mietzahlung',
      'rundfunkbeitrag', 'allianz', 'huk coburg', 'huk24', 'ergo versicherung', 'check24',
    ],
    'Kleidung': [
      'zalando', 'h&m', 'zara', 'about you', 'aboutyou', 'primark', 'c&a', 'snipes', 'nike',
      'adidas', 'uniqlo', 'peek & cloppenburg', 'peek&cloppenburg', 'deichmann', 'douglas',
      'sephora', 'asos', 'shein', 'bershka', 'pull&bear', 'new yorker', 's.oliver', 'jd sports',
      'tommy hilfiger', 'hugo boss', 'decathlon', 'sportscheck', 'otto versand',
    ],
    'Gesundheit': [
      'apotheke', 'docmorris', 'shop apotheke', 'shop-apotheke', 'fitness', 'mcfit', 'urban sports',
      'john reed', 'clever fit', 'fitx', 'arzt', 'arztpraxis', 'zahnarzt', 'praxis', 'krankenkasse', 'aok',
      'barmer', 'techniker', 'optiker', 'fielmann', 'apollo optik', 'doctolib', 'sanicare',
      'zur rose', 'medpex', 'tk gmbh', 'dak gesundheit',
    ],
    'Bildung': [
      'udemy', 'coursera', 'skillshare', 'linkedin learning', 'thalia', 'hugendubel',
      'universität', 'universitaet', 'hochschule', 'semesterbeitrag', 'studierendenwerk',
      'studentenwerk', 'volkshochschule', 'duolingo', 'babbel',
    ],
  };

  static const _income = {
    'Gehalt': [
      'gehalt', 'lohn', 'bezüge', 'bezuege', 'besoldung', 'entgelt', 'payroll', 'salary',
      'vergütung', 'verguetung', 'monatsgehalt', 'nettolohn', 'bruttolohn', 'gehaltsabrechnung',
      'lohnabrechnung', 'arbeitsentgelt', 'kindergeld', 'elterngeld', 'bafög', 'bafoeg',
    ],
    'Nebenjob': ['honorar', 'freelance'],
    'Investition': [
      'dividende', 'zinsen', 'ertrag', 'ausschüttung', 'ausschuettung', 'kapitalertrag',
      'depotzinsen', 'tagesgeldzinsen',
    ],
    'Geschenk': ['geschenk', 'geburtstag', 'weihnachten'],
  };

  static const _transfer = [
    'umbuchung', 'übertrag', 'uebertrag', 'sparkonto', 'tagesgeld', 'festgeld', 'sparplan',
    'trade republic', 'traderepublic', 'scalable capital', 'eigenes konto', 'consorsbank',
    'comdirect depot', 'depotübertragung', 'wertpapierkauf', 'wertpapierverkauf', 'pockets',
  ];

  // ISO 18245. Only when the name itself says nothing.
  static const _mccGroups = {
    'Lebensmittel': ['5411', '5422', '5441', '5451', '5499'],
    'Essen & Trinken': ['5462', '5812', '5813', '5814'],
    'Transport': ['4011', '4111', '4112', '4121', '4131', '4511', '4784', '4789', '5541', '5542', '7512', '7523'],
    'Unterhaltung': ['4899', '5735', '5815', '5816', '7832', '7841', '7922', '7929'],
    'Wohnen': ['4814', '4900', '6513'],
    'Kleidung': ['5611', '5621', '5631', '5641', '5651', '5661', '5691', '5699'],
    'Gesundheit': ['5912', '5975', '5976', '8011', '8021', '8041', '8042', '8043', '8062', '8099'],
    'Bildung': ['5192', '5942', '8211', '8220', '8241', '8244', '8249', '8299'],
  };

  static final _mcc = {
    for (final e in _mccGroups.entries)
      for (final code in e.value) code: e.key,
  };

  // short tokens that must not swallow the next letters ("netto" vs "Nettolohn", "shell" vs "Shelly")
  static const _whole = {
    'netto', 'shell', 'esso', 'aldi', 'cafe', 'jet', 'obi', 'wow', 'nike', 'uber', 'kino',
    'o2', 'dm', 'norma', 'penny', 'arzt', 'amazon', 'amzn', 'flink',
  };

  // one chain, many bank spellings. First entry is the key CategoryRules stores.
  static const _brands = [
    ['amazon', 'amzn', 'amznmktp'],
    ['rewe'],
    ['lidl'],
    ['edeka'],
    ['aldi'],
    ['netto'],
    ['spotify'],
    ['netflix'],
    ['shell'],
    ['zalando'],
    ['deutsche bahn', 'db vertrieb', 'db fernverkehr', 'db regio', 'bahn.de', 'bahncard', 'deutschebahn'],
    ['vodafone'],
    ['telekom'],
    ['rossmann'],
    ['dm'],
  ];

  static String guess(String text, {required bool isIncome, String mcc = ''}) {
    final lower = _prep(text);
    for (final k in _transfer) {
      if (_startsWord(lower, k)) return 'Umbuchung';
    }
    final rules = isIncome ? _income : _expense;
    for (final entry in rules.entries) {
      for (final k in entry.value) {
        if (_startsWord(lower, k)) return entry.key;
      }
    }
    if (isIncome) {
      for (final entry in _expense.entries) {
        for (final k in entry.value) {
          if (_startsWord(lower, k)) return entry.key;
        }
      }
    }
    final fromMcc = _fromMcc(mcc);
    if (fromMcc != null) return fromMcc;
    return 'Sonstiges';
  }

  // canonical merchant, so "AMZN Mktp" and "PAYPAL *AMAZON" share one learned category
  static String? brand(String text) {
    final lower = _prep(text);
    for (final group in _brands) {
      for (final k in group) {
        if (_startsWord(lower, k)) return group.first;
      }
    }
    return null;
  }

  static String _prep(String text) => _fold(text.toLowerCase().replaceAll('*', ' ').replaceAll(RegExp(r'\s+'), ' '));

  static String _fold(String s) =>
      s.replaceAll('ä', 'ae').replaceAll('ö', 'oe').replaceAll('ü', 'ue').replaceAll('ß', 'ss');

  static String? _fromMcc(String mcc) {
    final d = mcc.replaceAll(RegExp(r'\D'), '');
    if (d.length < 4) return null;
    return _mcc[d.substring(0, 4)];
  }

  static bool _startsWord(String text, String key) {
    key = _fold(key);
    final end = _whole.contains(key);
    var i = text.indexOf(key);
    while (i >= 0) {
      final before = i == 0 || !_isLetter(text.codeUnitAt(i - 1));
      final after = i + key.length;
      final tail = !end || after >= text.length || !_isLetter(text.codeUnitAt(after));
      if (before && tail) return true;
      i = text.indexOf(key, i + 1);
    }
    return false;
  }

  static bool _isLetter(int c) =>
      (c >= 0x61 && c <= 0x7a) || (c >= 0x30 && c <= 0x39) || 'äöüß&'.codeUnits.contains(c);
}

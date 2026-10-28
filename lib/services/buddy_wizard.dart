// Local setup chat: Vorsorge, a savings goal, or a depot position. Buddy asks
// only for what is still missing, then returns a BuddyEntry. Nothing is
// stored until the user taps the confirm card.
import 'package:hive/hive.dart';
import '../utils/instruments.dart';
import '../utils/money.dart';
import 'buddy_entries.dart';
import 'category_coach.dart';
import 'goals_service.dart';

class WizardTurn {
  final String text;
  final BuddyEntry? proposal;
  final String? quoteFor; // look up a live price, then call quoted()
  final bool open;
  const WizardTurn({this.text = '', this.proposal, this.quoteFor, this.open = false});
}

class BuddyWizard {
  String? kind; // vorsorge, goal, holding, categories
  String? pending;
  String? merchantPending; // categories: which Sonstiges merchant we're assigning

  int? age, retireAge, netCents, statutory, bav, riester;
  String? goalName;
  int? goalCents;
  String? query;
  double? shares;
  String? heldName, heldSymbol, heldType;
  int? manualCents;
  bool _manualPrice = false;

  bool get isOpen => kind != null;

  void reset() {
    kind = null;
    pending = null;
    age = retireAge = netCents = statutory = bav = riester = null;
    goalName = null;
    goalCents = null;
    query = null;
    shares = null;
    heldName = heldSymbol = heldType = null;
    manualCents = null;
    _manualPrice = false;
    merchantPending = null;
  }

  static final _categories = RegExp(
    r'sonstiges\s*(aufräumen|aufraeumen|ordnen)'
    r'|kategorien?\s*(aufräumen|aufraeumen|ordnen|helfen|sortieren)'
    r'|(hilf\w*|räum\w*|raeum\w*).{0,24}(kategor|sonstiges)',
  );

  static final _vorsorge = RegExp(
    r'(rentenrechner|altersvorsorge|vorsorge).{0,48}(einrichten|aufsetzen|ausfüllen|ausfuellen|anlegen|starten)'
    r'|(richte|richt |mach |stell ).{0,48}(rentenrechner|altersvorsorge|vorsorge|\brente\b)'
    r'|(rentenrechner|altersvorsorge).{0,24}(für mich|fuer mich)',
  );

  static final _goal = RegExp(
    r'sparziel.{0,48}(anlegen|erstell|\ban\b)'
    r'|(leg|lege|erstell|anlegen).{0,48}sparziel'
    r'|(leg|lege).{0,40}\bziel\b.{0,24}\ban\b',
  );

  // "Sparziel Urlaub 800" — name and amount, no extra verb
  static final _goalBare = RegExp(r'^sparziel\s+[a-zäöüß].*\d');

  // null when this is a question or a booking, not a setup command
  static String? detect(String text) {
    final raw = text.trim();
    if (raw.isEmpty || raw.endsWith('?')) return null;
    final t = raw.toLowerCase().replaceFirst(RegExp(r'^(bitte\s+|buddy[,:\s]+)'), '');
    if (_categories.hasMatch(t)) return 'categories';
    if (_vorsorge.hasMatch(t)) return 'vorsorge';
    if (_goal.hasMatch(t) || _goalBare.hasMatch(t)) return 'goal';
    if (_isHolding(raw)) return 'holding';
    return null;
  }

  static bool _isHolding(String text) {
    final t = text.toLowerCase();
    if (RegExp(r'gekauft|verkauft|bezahlt|ausgegeben|überwiesen|ueberwiesen|sparziel').hasMatch(t)) return false;
    final add = t.contains('hinzu') || t.contains('hinzufügen') || t.contains('hinzufuegen') || t.contains('ins depot');
    if (!add) return false;
    if (RegExp(r'\b(buchung|ausgabe|einnahme|umsatz)\b').hasMatch(t)) return false;
    final q = parseHolding(text).query;
    if (q.isNotEmpty && Instruments.search(q).isNotEmpty) return true;
    if (RegExp(r'\b(aktie|aktien|etf|krypto|coin)\b').hasMatch(t)) return true;
    // "Füge Döner hinzu" is a booking, not a position
    if (RegExp(r'€|euro').hasMatch(t)) return false;
    return false;
  }

  WizardTurn consume(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const WizardTurn(text: 'Das habe ich nicht verstanden.', open: true);
    if (kind == null) {
      kind = detect(text);
      if (kind == null) return const WizardTurn();
      switch (kind) {
        case 'vorsorge':
          _seedVorsorge(text);
        case 'goal':
          _seedGoal(text);
        case 'holding':
          final h = parseHolding(text);
          query = h.query.isEmpty ? null : h.query;
          shares = h.shares;
        default:
          break;
      }
    } else if (_cancel(text)) {
      reset();
      return const WizardTurn(text: 'Alles klar, ich ändere nichts.');
    } else if (kind == 'categories' && pending == 'catAssign') {
      final parsed = CategoryCoach.parseAssign(text, pending: merchantPending);
      if (parsed.merchant == null || parsed.category == null) {
        return WizardTurn(
          text: 'Sag z. B. „Lebensmittel“ oder „${merchantPending ?? 'REWE'} → Essen & Trinken“.',
          open: true,
        );
      }
      final entry = BuddyEntry(
        type: 'recategorize',
        date: DateTime.now(),
        note: parsed.merchant!,
        category: parsed.category!,
        cents: 1,
      );
      reset();
      return WizardTurn(
        text: '„${parsed.merchant}“ wird **${parsed.category}** — Übernehmen speichert für alle Buchungen.',
        proposal: entry,
      );
    } else if (!_accept(text)) {
      return WizardTurn(text: _reprompt(), open: true);
    }
    return _advance();
  }

  // after a price lookup started by [WizardTurn.quoteFor]
  WizardTurn quoted({Instrument? instrument, int cents = 0, bool live = false, List<Instrument> options = const []}) {
    if (kind != 'holding') return const WizardTurn(text: 'Das Depot lasse ich so.');
    if (instrument == null) {
      if (options.length > 1) {
        pending = 'which';
        final names = options.take(4).map((o) => o.symbol.isEmpty ? o.name : '${o.name} (${o.symbol})').join(', ');
        return WizardTurn(text: 'Da gibt es mehrere: $names. Welches meinst du?', open: true);
      }
      pending = 'query';
      final label = query == null || query!.isEmpty ? 'Das' : '„$query“';
      return WizardTurn(text: '$label habe ich nicht gefunden. Wie heißt es genau, oder nenn den Ticker?', open: true);
    }
    heldName = instrument.name;
    heldSymbol = instrument.symbol;
    heldType = instrument.type;
    if (cents <= 0) {
      pending = 'price';
      return WizardTurn(
        text: 'Den Kurs von ${instrument.name} habe ich nicht bekommen. Was kostet ein Stück ungefähr, in Euro?',
        open: true,
      );
    }
    return _proposeHolding(cents, live: live);
  }

  WizardTurn _advance() {
    switch (kind) {
      case 'categories':
        final fixes = CategoryCoach.autoFixes(limit: 12);
        if (fixes.isNotEmpty) {
          final n = fixes.fold<int>(0, (s, p) => s + p.count);
          final entry = BuddyEntry(
            type: 'recategorize_all',
            date: DateTime.now(),
            note: '${fixes.length} Händler',
            cents: n,
          );
          reset();
          return WizardTurn(
            text: 'Ich kann **$n** Sonstiges-Buchungen bei ${fixes.length} Händlern zuordnen. '
                'Übernehmen speichert — du kannst einzelne danach noch ändern.',
            proposal: entry,
          );
        }
        final left = CategoryCoach.leftovers(limit: 1);
        if (left.isEmpty) {
          reset();
          return const WizardTurn(text: 'Kein Sonstiges offen — alles zugeordnet.');
        }
        pending = 'catAssign';
        merchantPending = left.first.sample;
        return WizardTurn(
          text: 'Wohin gehört „${left.first.sample}“? Schreib die Kategorie, z. B. Lebensmittel.',
          open: true,
        );
      case 'vorsorge':
        if (age == null) return _ask('age', 'Gern. Wie alt bist du?');
        if (retireAge == null) return _ask('retire', 'Mit welchem Alter willst du in Rente? 67 ist der Standard.');
        if (netCents == null) return _ask('net', 'Welches Netto im Monat möchtest du dann? Zum Beispiel 2.000 €.');
        if (statutory == null) {
          return _ask('statutory', 'Was erwartest du an gesetzlicher Rente im Monat? 0 zum Überspringen, „keine“ geht auch.');
        }
        if (bav == null) return _ask('bav', 'Betriebsrente (bAV) im Monat? 0 zum Überspringen.');
        if (riester == null) return _ask('riester', 'Riester oder Rürup im Monat? 0 zum Überspringen.');
        final entry = BuddyEntry(
          type: 'vorsorge',
          date: DateTime.now(),
          age: age!,
          retireAge: retireAge!,
          cents: netCents!,
          statutoryCents: statutory!,
          bavCents: bav!,
          riesterCents: riester!,
        );
        reset();
        return WizardTurn(
          text: 'So richte ich den Rentenrechner ein. Erst der Tipp auf Übernehmen speichert.',
          proposal: entry,
        );
      case 'goal':
        if (goalName == null || goalName!.isEmpty) return _ask('goalName', 'Wie soll das Sparziel heißen?');
        if (goalCents == null) return _ask('goalCents', 'Wie viel Euro soll „$goalName“ werden?');
        final name = goalName!;
        final exists = _goalsOpen && GoalsService.all().any((g) => g.name.toLowerCase() == name.toLowerCase());
        final entry = BuddyEntry(
          type: 'goal',
          date: DateTime.now(),
          note: name,
          cents: goalCents!,
          emoji: emojiFor(name),
        );
        reset();
        return WizardTurn(
          text: exists
              ? 'Du hast schon ein Ziel „$name“. Übernehmen legt ein weiteres an.'
              : 'So lege ich das Sparziel an. Erst der Tipp auf Übernehmen speichert.',
          proposal: entry,
        );
      case 'holding':
        if (manualCents != null && heldName != null) return _proposeHolding(manualCents!, live: false);
        if (query == null || query!.isEmpty) {
          return _ask('query', 'Welches Wertpapier soll ins Depot? Zum Beispiel Apple oder AAPL.');
        }
        if (shares == null) return _ask('shares', 'Wie viele Stück $query soll ich eintragen?');
        pending = 'quote';
        return WizardTurn(quoteFor: query, open: true);
      default:
        reset();
        return const WizardTurn();
    }
  }

  // the first question of a run says how to stop; later ones stay short
  WizardTurn _ask(String slot, String text) {
    final first = pending == null;
    pending = slot;
    return WizardTurn(text: first ? '$text „Abbrechen“ stoppt.' : text, open: true);
  }

  WizardTurn _proposeHolding(int cents, {required bool live}) {
    final entry = BuddyEntry(
      type: 'holding',
      date: DateTime.now(),
      name: heldName ?? query ?? '',
      symbol: heldSymbol ?? '',
      shares: shares ?? 0,
      price: cents / 100,
      instrumentType: heldType ?? '',
      note: live ? 'Live-Kurs' : (_manualPrice ? 'Dein Kurs' : 'Richtkurs'),
      livePrice: live,
    );
    reset();
    return WizardTurn(
      text: live
          ? 'So trage ich es ein, zum Live-Kurs. Erst der Tipp auf Übernehmen speichert.'
          : 'So trage ich es ein. Erst der Tipp auf Übernehmen speichert.',
      proposal: entry,
    );
  }

  bool _accept(String text) {
    switch (pending) {
      case 'age':
        final n = _int(text);
        if (n == null || n < 15 || n > 80) return false;
        age = n;
        return true;
      case 'retire':
        if (RegExp(r'standard|normal|üblich|ueblich').hasMatch(text.toLowerCase())) {
          retireAge = 67;
          return true;
        }
        final n = _int(text);
        if (n == null || n < 50 || n > 80) return false;
        if (age != null && n <= age!) return false;
        retireAge = n;
        return true;
      case 'net':
        final c = _money(text);
        if (c == null || c <= 0) return false;
        netCents = c;
        return true;
      case 'statutory' || 'bav' || 'riester':
        final none = _none(text);
        final c = none ? 0 : _money(text);
        if (c == null || c < 0) return false;
        if (pending == 'statutory') statutory = c;
        if (pending == 'bav') bav = c;
        if (pending == 'riester') riester = c;
        return true;
      case 'goalName':
        final words = _title(text.replaceAll(RegExp(r'[€]'), '').replaceAll(RegExp(r'\d[\d.,]*'), ' '));
        if (words.length < 2) return false;
        goalName = words;
        final money = _money(text);
        if (money != null && money > 0) goalCents = money;
        return true;
      case 'goalCents':
        final c = _money(text);
        if (c == null || c <= 0) return false;
        goalCents = c;
        return true;
      case 'shares':
        final s = _sharesOf(text);
        if (s == null || s <= 0) return false;
        shares = s;
        return true;
      case 'query' || 'which':
        final h = parseHolding(text);
        final next = h.query.isEmpty ? text.trim() : h.query;
        if (next.length < 2) return false;
        query = next;
        if (h.shares != null) shares = h.shares;
        return true;
      case 'price':
        final c = _money(text);
        if (c == null || c <= 0) return false;
        manualCents = c;
        _manualPrice = true;
        return true;
      default:
        return false;
    }
  }

  String _reprompt() => switch (pending) {
        'age' => 'Schreib dein Alter als Zahl, zum Beispiel 34.',
        'retire' => 'Mit welchem Alter? Zum Beispiel 67.',
        'net' => 'Ein Betrag in Euro, zum Beispiel 2.000.',
        'statutory' || 'bav' || 'riester' => 'Ein Betrag in Euro, oder „keine“.',
        'goalName' => 'Wie soll das Ziel heißen? Zum Beispiel Urlaub.',
        'goalCents' => 'Wie viel Euro? Zum Beispiel 800.',
        'shares' => 'Wie viele Stück? Zum Beispiel 2 oder 0,5.',
        'price' => 'Ein Kurs in Euro, zum Beispiel 190.',
        _ => 'Das habe ich nicht verstanden.',
      };

  void _seedVorsorge(String text) {
    final t = text.toLowerCase();
    final ageM = RegExp(r'(?:ich bin|bin|alter)\s*(\d{1,2})|(\d{1,2})\s*jahre').firstMatch(t);
    if (ageM != null) {
      final n = int.parse((ageM.group(1) ?? ageM.group(2))!);
      if (n >= 15 && n <= 80) age = n;
    }
    final ret = RegExp(r'(?:rente|rentenalter).{0,16}(\d{2})|(?:mit|ab)\s*(\d{2})\s*(?:in rente|jahren)').firstMatch(t);
    if (ret != null) {
      final n = int.parse((ret.group(1) ?? ret.group(2))!);
      if (n >= 50 && n <= 80 && (age == null || n > age!)) retireAge = n;
    }
    final net = RegExp(r'(\d[\d.]*)\s*(?:€|euro)?\s*netto|netto\s*(?:von|:)?\s*(\d[\d.]*)').firstMatch(t);
    if (net != null) netCents = _money(net.group(1) ?? net.group(2) ?? '');
    statutory = _pillar(t, RegExp(r'gesetzlich(?:e rente)?'));
    bav = _pillar(t, RegExp(r'betriebsrente|\bbav\b'));
    riester = _pillar(t, RegExp(r'riester|rürup|ruerup'));
  }

  // a pension pillar mentioned as "keine" or with an amount; null if not mentioned
  // null when the pillar is not mentioned, so the wizard still asks
  int? _pillar(String t, RegExp label) {
    final m = label.firstMatch(t);
    if (m == null) return null;
    final slice = t.substring((m.start - 14).clamp(0, t.length), (m.end + 18).clamp(0, t.length));
    final money = _money(slice);
    if (money != null && money > 0) return money;
    if (_none(slice) || money == 0) return 0;
    return null;
  }

  void _seedGoal(String text) {
    final parsed = parseGoal(text);
    goalName = parsed.name;
    goalCents = parsed.cents;
  }

  static ({String? name, int? cents}) parseGoal(String text) {
    // € is not a word character, so no \b after it ("800€ an" would miss)
    final amount = RegExp(
      r'(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:,\d{1,2})?)\s*(?:€|eur|euro)(?!\w)',
      caseSensitive: false,
    ).firstMatch(text) ??
        RegExp(r'\b(\d{1,3}(?:\.\d{3})+|\d{3,})\b').firstMatch(text);
    final cents = amount == null ? null : _money(amount.group(1)!);
    var rest = text;
    if (amount != null) rest = rest.replaceRange(amount.start, amount.end, ' ');
    rest = rest.replaceAll('€', ' ');
    rest = rest.replaceAll(
      RegExp(
        r'\b(leg|lege|ein|eine|einen|sparziel|ziel|anlegen|an|bitte|mal|mir|für|fuer|das|den|dem|neues|neu|mit|von|euro)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    rest = rest.replaceAll(RegExp(r'\s+'), ' ').trim();
    final name = rest.isEmpty ? null : _title(rest);
    return (name: name, cents: cents);
  }

  static ({String query, double? shares}) parseHolding(String text) {
    var shares = _sharesOf(
      RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:stück|stueck|stk\.?|anteile)\b', caseSensitive: false).firstMatch(text)?.group(1) ?? '',
    );
    var q = text.replaceAll(
      RegExp(r'\d+(?:[.,]\d+)?\s*(?:stück|stueck|stk\.?|anteile)\b', caseSensitive: false),
      ' ',
    );
    if (shares == null) {
      final n = RegExp(r'\b(\d+(?:[.,]\d+)?)\b').firstMatch(q);
      if (n != null) {
        final v = _sharesOf(n.group(1)!);
        if (v != null && v > 0 && v < 100000) {
          shares = v;
          q = q.replaceFirst(n.group(0)!, ' ');
        }
      }
    }
    q = q.replaceAll(
      RegExp(
        r'\b(füge|fuege|hinzu|hinzufügen|hinzufuegen|bitte|mal|mir|die|der|das|den|ins|in|depot|aktien|aktie|etf|krypto|coin|pack|packe|nimm|trag|trage|ein|eine|einen)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
    return (query: q, shares: shares);
  }

  static String emojiFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('urlaub') || n.contains('reise')) return '🏖️';
    if (n.contains('notgroschen') || n.contains('reserve') || n.contains('polster')) return '🛟';
    if (n.contains('handy') || n.contains('iphone')) return '📱';
    if (n.contains('auto') || n.contains('wagen')) return '🚗';
    if (n.contains('wohn') || n.contains('haus')) return '🏠';
    return '🎯';
  }

  static bool get _goalsOpen {
    try {
      return Hive.isBoxOpen('goals');
    } catch (_) {
      return false;
    }
  }

  static bool _cancel(String text) => RegExp(
        r'^(abbrechen|abbruch|stopp|stop|vergiss es|lass es|doch nicht|nein danke)\.?$',
      ).hasMatch(text.toLowerCase().trim());

  static bool _none(String text) {
    final t = text.toLowerCase();
    if (RegExp(r'\d').hasMatch(t) && !RegExp(r'\b0\b').hasMatch(t)) return false;
    return RegExp(r'\b(keine|keiner|keins|kein|nichts|nein|weiß nicht|weiss nicht|keine ahnung|null)\b').hasMatch(t);
  }

  static int? _int(String text) {
    final m = RegExp(r'\d{1,3}').firstMatch(text);
    return m == null ? null : int.tryParse(m.group(0)!);
  }

  static int? _money(String text) {
    if (text.trim().isEmpty) return null;
    final m = RegExp(r'(\d{1,3}(?:\.\d{3})+(?:,\d{1,2})?|\d+(?:,\d{1,2})?)').firstMatch(text);
    if (m == null) return null;
    return Money.parseToCents(m.group(1)!);
  }

  static double? _sharesOf(String text) {
    final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(text.trim());
    if (m == null) return null;
    return double.tryParse(m.group(0)!.replaceAll(',', '.'));
  }

  static String _title(String s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) {
        if (w == w.toLowerCase() && w.isNotEmpty) return '${w[0].toUpperCase()}${w.substring(1)}';
        return w;
      }).join(' ');
}

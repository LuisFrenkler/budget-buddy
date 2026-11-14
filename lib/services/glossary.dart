// Money words explained right where they come up. Buddy's answers mark the
// first time a term appears; one tap shows two or three plain sentences.
// Education as an ingredient, not a course.
//
// Facts here are general and for Germany. Numbers that change by law are
// either left out or named with the year they hold for.
import '../l10n/l10n.dart';

// term and text are German keys, shown in the app language
class GlossaryTerm {
  final String _term;
  final String _text;
  final List<String> also; // other spellings that mean the same
  const GlossaryTerm(this._term, this._text, {this.also = const []});
  String get term => tr(_term);
  String get text => tr(_text);
  // German and app-language spellings, for finding the term in a text
  List<String> get words => {_term, term, ...also}.toList();
}

class Glossary {
  static const terms = <GlossaryTerm>[
    GlossaryTerm('Brutto', 'Dein Gehalt, bevor Steuern und Sozialabgaben abgehen. Das steht im Arbeitsvertrag.',
        also: ['Bruttogehalt', 'brutto']),
    GlossaryTerm('Netto', 'Was nach Steuern und Sozialabgaben wirklich auf deinem Konto ankommt.',
        also: ['Nettogehalt', 'netto']),
    GlossaryTerm('Steuerklasse',
        'Bestimmt, wie viel Lohnsteuer jeden Monat einbehalten wird. Ledige haben Klasse I. Was du am Ende wirklich zahlst, klärt die Steuererklärung.',
        also: ['Steuerklassen', 'Lohnsteuerklasse']),
    GlossaryTerm('Lohnsteuer',
        'Die Einkommensteuer, die dein Arbeitgeber jeden Monat direkt vom Gehalt abzieht und ans Finanzamt zahlt.'),
    GlossaryTerm('Sozialabgaben',
        'Beiträge zur Renten-, Kranken-, Pflege- und Arbeitslosenversicherung. Als Angestellte oder Angestellter zahlst du davon grob ein Fünftel deines Bruttos, den Rest legt dein Arbeitgeber drauf.',
        also: ['Sozialversicherung', 'Sozialversicherungsbeiträge']),
    GlossaryTerm('Zusatzbeitrag',
        'Der Teil des Krankenkassenbeitrags, den jede Kasse selbst festlegt. Er wird zwischen dir und dem Arbeitgeber geteilt. Ein Kassenwechsel kann sich lohnen.'),
    GlossaryTerm('Kirchensteuer',
        'Zahlen nur Kirchenmitglieder: 8 oder 9 Prozent der Lohnsteuer, je nach Bundesland.'),
    GlossaryTerm('Solidaritätszuschlag',
        'Ein Zuschlag auf die Einkommensteuer. Für die meisten Beschäftigten fällt er seit 2021 weg, bei Kapitalerträgen gibt es ihn weiter.',
        also: ['Soli']),
    GlossaryTerm('Betriebsrente',
        'Altersvorsorge über deinen Arbeitgeber. Ein Teil des Bruttos fließt in einen Vertrag, oft mit Zuschuss vom Arbeitgeber. Wichtig sind die Kosten des Vertrags und was bei einem Jobwechsel passiert.',
        also: ['bAV', 'betriebliche Altersvorsorge']),
    GlossaryTerm('Entgeltumwandlung',
        'Du wandelst einen Teil deines Bruttos in Betriebsrente um. Spart dein Arbeitgeber dadurch Sozialabgaben, muss er in der Regel 15 Prozent dazugeben.'),
    GlossaryTerm('Vermögenswirksame Leistungen',
        'Ein Zuschuss deines Arbeitgebers für einen Sparvertrag, oft bis zu 40 Euro im Monat, je nach Arbeits- oder Tarifvertrag. Wer nicht fragt, verschenkt ihn manchmal.',
        also: ['VL']),
    GlossaryTerm('Notgroschen',
        'Geld für Unerwartetes, das du sofort erreichst, zum Beispiel auf einem Tagesgeldkonto. Faustregel: drei Monatsausgaben, bei unsicherem Job eher mehr.',
        also: ['Notgroschens', 'Notreserve', 'Notfallreserve']),
    GlossaryTerm('Tagesgeld',
        'Ein Sparkonto mit Zinsen, von dem du jederzeit abheben kannst. Gut für den Notgroschen.',
        also: ['Tagesgeldkonto']),
    GlossaryTerm('Sparrate', 'Der feste Betrag, den du jeden Monat zur Seite legst, am besten direkt nach dem Gehaltseingang.',
        also: ['Sparquote']),
    GlossaryTerm('ETF',
        'Ein börsengehandelter Fonds, der einen Index nachbildet, also viele Unternehmen auf einmal. Meist günstig und breit gestreut. Schwankungen gehören dazu.',
        also: ['ETFs', 'Indexfonds']),
    GlossaryTerm('TER', 'Die laufenden Kosten eines Fonds pro Jahr, in Prozent. Je niedriger, desto mehr bleibt bei dir.'),
    GlossaryTerm('Sparplan', 'Du kaufst automatisch jeden Monat für einen festen Betrag Anteile, zum Beispiel an einem ETF.',
        also: ['Sparpläne', 'ETF-Sparplan']),
    GlossaryTerm('Altersvorsorgedepot',
        'Ein geplantes, staatlich gefördertes Depot für die Altersvorsorge. Nach aktuellem Plan startet es am 1. Januar 2027, Details können sich noch ändern.'),
    GlossaryTerm('Rentenlücke',
        'Der Unterschied zwischen dem, was du im Alter brauchst, und dem, was die gesetzliche Rente voraussichtlich zahlt.'),
    GlossaryTerm('Zinseszins',
        'Zinsen, die selbst wieder Zinsen bringen. Darum macht früh anfangen über viele Jahre so viel aus.'),
    GlossaryTerm('Inflation', 'Steigende Preise. Geld, das nur herumliegt, kann dadurch jedes Jahr etwas weniger kaufen.'),
    GlossaryTerm('Fixkosten', 'Was jeden Monat sicher weggeht: Miete, Verträge, Versicherungen, Abos.'),
    GlossaryTerm('Dispo',
        'Der Überziehungsrahmen deines Girokontos. Praktisch, aber teuer: die Zinsen sind meist deutlich höher als bei einem normalen Kredit.',
        also: ['Dispokredit']),
    GlossaryTerm('Schufa',
        'Eine Auskunftei, die speichert, ob du Rechnungen und Kredite zahlst. Vermieter und Banken fragen dort nach.'),
    GlossaryTerm('Mietkaution',
        'Eine Sicherheit für den Vermieter, höchstens drei Monatskaltmieten. Du darfst sie in drei Raten zahlen.',
        also: ['Kaution']),
    GlossaryTerm('Nebenkosten',
        'Kosten rund um die Wohnung, die zur Kaltmiete dazukommen, etwa Heizung, Wasser und Müll. Einmal im Jahr wird abgerechnet.'),
    GlossaryTerm('Werbungskosten',
        'Ausgaben für deinen Job, die du in der Steuererklärung angibst, etwa Fahrtkosten oder Arbeitsmittel. Eine Pauschale bekommst du ohnehin.'),
    GlossaryTerm('Steuererklärung',
        'Damit rechnest du mit dem Finanzamt dein Jahr ab. Im ersten Job gibt es oft Geld zurück, weil im ersten Jahr meist nicht zwölf volle Monate gearbeitet werden.'),
    GlossaryTerm('Sparerpauschbetrag',
        'Bis zu 1.000 Euro Kapitalerträge im Jahr bleiben steuerfrei (Paare 2.000 Euro). Dafür stellst du bei deiner Bank einen Freistellungsauftrag.',
        also: ['Freistellungsauftrag']),
    GlossaryTerm('Abgeltungsteuer',
        'Die Steuer auf Zinsen, Dividenden und Kursgewinne: 25 Prozent plus Soli und gegebenenfalls Kirchensteuer, nach dem Sparerpauschbetrag.'),
  ];

  // rebuilt when the app language changes, so English terms are found too
  static String? _lang;
  static Map<String, GlossaryTerm> _words = {};
  static RegExp _regex = RegExp(r'(?!)');

  static Map<String, GlossaryTerm> get _byWord {
    if (_lang != L10n.lang.value) {
      _lang = L10n.lang.value;
      _words = {
        for (final t in terms)
          for (final w in t.words) w.toLowerCase(): t,
      };
      // longest first, so "ETF-Sparplan" wins over "ETF"
      final words = _words.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
      _regex = RegExp('(?<![\\wÄÖÜäöüß-])(${words.map(RegExp.escape).join('|')})(?![\\wÄÖÜäöüß])', caseSensitive: false);
    }
    return _words;
  }

  static GlossaryTerm? lookup(String word) => _byWord[word.toLowerCase().trim()];

  static RegExp get _pattern {
    _byWord;
    return _regex;
  }

  // where terms start in [text]: each term once, at most [max] per answer
  static List<({int start, int end, GlossaryTerm term})> find(String text, {int max = 3}) {
    final seen = <String>{};
    final out = <({int start, int end, GlossaryTerm term})>[];
    for (final m in _pattern.allMatches(text)) {
      final term = lookup(m.group(1)!);
      if (term == null || !seen.add(term.term)) continue;
      // "netto" in "vermoegen.netto" style words or small "netto" adjectives are fine too
      out.add((start: m.start, end: m.end, term: term));
      if (out.length >= max) break;
    }
    return out;
  }
}

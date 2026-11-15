// "Was kannst du alles?": Buddy explains himself, with examples to tap. On the
// device, without AI, so the answer is instant and costs no question.
import '../l10n/l10n.dart';

class BuddyHelp {
  static final _ask = RegExp(
      r'^\s*(was kannst du( alles)?|was kann buddy|wie hilfst du mir|hilfe|what can you do|what do you do|help)\s*[?!.]*\s*$',
      caseSensitive: false);

  static bool matches(String q) => _ask.hasMatch(q);

  static ({String text, List<String> chips}) answer({bool guest = false}) {
    final text = guest
        ? tr('Ohne Konto erkläre ich Begriffe und Regeln. Zum Beispiel:\n\n'
            '- **Brutto und Netto:** was vom Gehalt bleibt\n'
            '- **Erster Job:** Abrechnung, Notgroschen, Sparrate\n'
            '- **Begriffe:** ETF, Steuerklasse, Schufa, Dispo\n\n'
            'Mit einem kostenlosen Konto rechne ich mit deinen Zahlen.\n\n'
            'Nächster Schritt: Frag mich, was von 3.000 € brutto netto bleibt.')
        : tr('Ich rechne mit deinen Zahlen. Zum Beispiel:\n\n'
            '- **Monat:** was bis Monatsende frei ist\n'
            '- **Sparen:** Ziele, Notgroschen, Sparrate\n'
            '- **Verträge:** Frist und Kündigung\n'
            '- **Gehalt:** Brutto-Netto, Abrechnung, Steuer\n'
            '- **Plan:** Woche, Monatsabschluss, Rente\n\n'
            'Gespeichert wird erst, wenn du auf Übernehmen tippst.\n\n'
            'Nächster Schritt: Frag mich, was diesen Monat noch frei ist.');
    final chips = guest
        ? [tr('Was bleibt von 3.000 € brutto netto?'), tr('Wie viel Notgroschen brauche ich?'), tr('Was ist ein ETF-Sparplan?')]
        : [
            tr('Wie viel ist diesen Monat noch frei?'),
            tr('Welche Abos könnte ich kündigen?'),
            tr('Lohnt sich für mich eine Steuererklärung?'),
          ];
    return (text: text, chips: chips);
  }
}

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
        ? tr('Ich bin Buddy, dein Coach fürs Geld. Ohne Konto erkläre ich dir Begriffe und Regeln, zum Beispiel:\n\n'
            '- **Brutto und Netto:** was von deinem Gehalt bleibt, nach den Regeln 2026\n'
            '- **Erster Job:** Abrechnung, Betriebsrente, Notgroschen, Sparrate\n'
            '- **Begriffe:** ETF, Steuerklasse, Schufa, Dispo\n\n'
            'Mit einem kostenlosen Konto rechne ich mit deinen echten Zahlen.\n\n'
            'Nächster Schritt: Frag mich, was von 3.000 € brutto netto bleibt.')
        : tr('Ich rechne mit deinen echten Zahlen und sag dir, was als Nächstes dran ist. Zum Beispiel:\n\n'
            '- **Dein Monat:** was bis Monatsende frei ist, und ob du dir etwas leisten kannst\n'
            '- **Sparen:** Sparziele, Notgroschen, Sparrate nach dem Gehalt, Abos und Bankgebühren, die zu viel kosten\n'
            '- **Verträge:** Kündigungsfristen ausrechnen und das Schreiben vorbereiten\n'
            '- **Gehalt und Steuer:** Brutto-Netto 2026, deine Abrechnung prüfen (Foto reicht), Steuererstattung schätzen\n'
            '- **Planen:** Wochenplan, Monatsabschluss, Rentenlücke grob\n\n'
            'Ich schlage vor, du entscheidest: Gespeichert wird erst, wenn du auf Übernehmen tippst, und fast alles kannst du zurücknehmen.\n\n'
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

import 'package:budget_buddy/services/buddy_voice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Buddy reads the answer, not the markup', () {
    final said = BuddyVoice.speakable('**58,30 €** für Lebensmittel.\n\n- Rewe\n- Lidl\n\n'
        'Nächster Schritt: Budget setzen.\n[merken: Kauft bei Rewe]\n[weiter: Mehr? | Weniger?]');
    expect(said, '58,30 € für Lebensmittel. Rewe Lidl. Nächster Schritt: Budget setzen.');
  });
}

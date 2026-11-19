// A setting asked for by name works on the device, without the model, and a
// question that only mentions a language is no order.
import 'package:budget_buddy/services/buddy_proposals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  (String, String)? order(String q) {
    final p = BuddyProposal.settingFrom(q);
    return p == null ? null : ('${p.data['was']}', '${p.data['wert']}');
  }

  test('orders are understood in German and English', () {
    expect(order('stell die app auf englisch'), ('sprache', 'en'));
    expect(order('Stell die App bitte wieder auf Deutsch'), ('sprache', 'de'));
    expect(order('switch the app to English'), ('sprache', 'en'));
    expect(order('Schalte den Dunkelmodus an'), ('design', 'dunkel'));
    expect(order('Mach den Dunkelmodus aus'), ('design', 'hell'));
    expect(order('Mach die App hell'), ('design', 'hell'));
    expect(order('Stell auf Beträge verbergen'), ('betraege_verbergen', 'an'));
    expect(order('Mach die Beträge wieder sichtbar'), ('betraege_verbergen', 'aus'));
  });

  test('a question that only mentions the word is no order', () {
    expect(order('Was heißt Steuerklasse auf Englisch?'), isNull);
    expect(order('Antworte auf Englisch'), isNull);
    expect(order('Warum ist mein Konto so dunkel im Minus?'), isNull);
    expect(order('Wie viel ist diesen Monat noch frei?'), isNull);
  });
}

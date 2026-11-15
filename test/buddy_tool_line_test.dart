import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => L10n.lang.value = 'de');

  test('a tool status is one short line', () {
    L10n.lang.value = 'de';
    expect(buddyToolLine('Konten'), 'Prüft Konten…');
    expect(buddyToolLine('deine Konten'), 'Prüft Konten…');
    expect(
        buddyToolLine('deine Zahlen noch einmal'), 'Prüft Zahlen noch einmal…');
    L10n.lang.value = 'en';
    expect(buddyToolLine('Konten'), 'Checking accounts…');
    expect(buddyToolLine('ob es passt'), 'Checking affordability…');
  });
}

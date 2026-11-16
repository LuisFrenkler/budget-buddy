// The server serves the legal pages from the app's legal texts, so they must
// stay plain Dart: if Flutter, Hive or intl sneak in again, this file no
// longer compiles and the server would not start (that happened once).
import 'package:test/test.dart';

import '../../lib/legal/legal_texts.dart';

void main() {
  test('the legal texts load without Flutter, in German by default', () {
    expect(LegalTexts.privacy.title, 'Datenschutzerklärung');
    expect(LegalTexts.privacy.sections, isNotEmpty);
  });
}

// The data overview must not say anything the privacy policy does not:
// every fact it names stands in the policy, every section exists, and
// what is switched on follows the app.
import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/legal/data_map.dart';
import 'package:budget_buddy/legal/legal_texts.dart';
import 'package:budget_buddy/screens/data_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

String _policy() => LegalTexts.privacy.sections.map((s) => '${s.heading}\n${s.body}').join('\n');

void main() {
  setUp(() => L10n.lang.value = 'de');

  for (final provider in ['anthropic', 'google']) {
    test('every fact stands in the privacy policy ($provider)', () {
      final policy = _policy();
      for (final f in DataMap.flows(DataStatus(aiProvider: provider, signedIn: true, aiConsent: true))) {
        expect(LegalTexts.privacy.sections.any((s) => s.heading.startsWith('${f.section}.')), isTrue,
            reason: '${f.id}: section ${f.section} missing');
        for (final fact in f.facts) {
          expect(policy.contains(fact), isTrue, reason: '${f.id}: "$fact" is not in the privacy policy');
        }
      }
    });
  }

  test('ids are unique and the always-on ones are on', () {
    final flows = DataMap.flows(const DataStatus());
    expect(flows.map((f) => f.id).toSet().length, flows.length);
    expect(flows.where((f) => f.active).map((f) => f.id), ['device', 'journal']);
  });

  test('what is on follows the app', () {
    final on = DataMap.flows(const DataStatus(signedIn: true, bankLinked: true, aiConsent: true, memories: 3))
        .where((f) => f.active)
        .map((f) => f.id);
    expect(on, containsAll(['account', 'copy', 'bank', 'ai', 'memory']));
    expect(on, isNot(contains('depot')));
    // consent without an account sends nothing
    expect(DataMap.flows(const DataStatus(aiConsent: true)).firstWhere((f) => f.id == 'ai').active, isFalse);
  });

  test('the provider shown is the one that answers', () {
    final g = DataMap.flows(const DataStatus(aiProvider: 'google')).firstWhere((f) => f.id == 'ai');
    expect(g.where, contains('Google'));
    final a = DataMap.flows(const DataStatus()).firstWhere((f) => f.id == 'ai');
    expect(a.where, contains('Anthropic'));
  });

  test('Buddy answers privacy questions from the list, in both languages', () {
    expect(DataMap.matches('Wer hat Zugriff auf meine Daten?'), isTrue);
    expect(DataMap.matches('Wo liegen meine Daten eigentlich?'), isTrue);
    expect(DataMap.matches('Who can see my data?'), isTrue);
    expect(DataMap.matches('Wie viel habe ich ausgegeben?'), isFalse);
    final a = DataMap.answer(const DataStatus(signedIn: true, bankLinked: true));
    expect(a, contains('Enable Banking'));
    expect(a, contains('AES-256'));
    expect(a, contains('Aus oder nicht genutzt'));
    expect(a, contains('Nächster Schritt'));
  });

  testWidgets('the screen shows what is on first', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DataScreen(status: DataStatus(signedIn: true, bankLinked: true))));
    expect(find.text('Gerade aktiv'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('flow-bank')), 200);
    // the bank is on: above the heading of the ones that are off
    await tester.scrollUntilVisible(find.text('Nur wenn du es nutzt'), 200);
    final offHeading = tester.getTopLeft(find.text('Nur wenn du es nutzt')).dy;
    final bank = find.byKey(const Key('flow-bank'));
    if (bank.evaluate().isNotEmpty) expect(tester.getTopLeft(bank).dy, lessThan(offHeading));
    await tester.scrollUntilVisible(find.byKey(const Key('flow-whatsapp')), 200);
    expect(find.byKey(const Key('flow-whatsapp')), findsOneWidget);
  });
}

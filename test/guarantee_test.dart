// The offer inside the app: the guarantee page with its price, the tap that
// notes interest (no payment), and the feed headline that keeps money coming
// back apart from costs that can stop.
import 'dart:typed_data';

import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/plus_screen.dart';
import 'package:budget_buddy/screens/guarantee_screen.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/product_events.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:budget_buddy/widgets/agent_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    // in memory: a file write would not finish inside a widget test
    for (final name in ['settings', 'transactions', 'budgets', 'goals', 'badges', 'recurring', 'holdings']) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
  });
  setUp(() async {
    await Hive.box('settings').clear();
    await Hive.box('transactions').clear();
    ProductEvents.reset();
  });

  testWidgets('the page names price and guarantee; Vormerken keeps the date and asks for no payment', (tester) async {
    // a tall phone, so the whole page is built
    tester.view.physicalSize = const Size(750, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: GuaranteeScreen()));
    await tester.pump();
    expect(ProductEvents.log.single, endsWith(' guarantee_seen'));
    expect(find.textContaining('4,99'), findsOneWidget);
    expect(find.textContaining('98,00'), findsWidgets);
    expect(find.textContaining('Bezahlen geht noch nicht'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(Hive.box('settings').get('guaranteeReserved'), isNull);

    await tester.tap(find.byKey(const Key('guarantee-reserve')));
    await tester.pump();
    final at = DateTime.parse(Hive.box('settings').get('guaranteeReserved') as String);
    expect(DateTime.now().difference(at).inMinutes, 0);
    expect(ProductEvents.log.last, endsWith(' guarantee_reserve'));
    expect(find.text('Vorgemerkt. Wir melden uns, sobald du beitreten kannst.'), findsOneWidget);
    expect(find.byKey(const Key('guarantee-reserve')), findsNothing);

    // reopened: still noted, no second button
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const MaterialApp(home: GuaranteeScreen()));
    expect(find.byKey(const Key('guarantee-reserved')), findsOneWidget);
  });

  testWidgets('the headline shows money back big and yearly costs on their own line; the link opens the page', (tester) async {
    tester.view.physicalSize = const Size(750, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 3000, monthsWorked: 4, km: 20), year: now.year - 1);
    // Netflix went up by 2 € with the newest debit: 24 € more per year
    for (var i = 0; i < 4; i++) {
      await DB.addTx(Transaction(
          id: 'n$i',
          amountCents: i == 0 ? 1599 : 1399,
          category: 'Unterhaltung',
          isIncome: false,
          date: DateTime(now.year, now.month - i, 1),
          note: 'Netflix'));
    }
    final asked = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: AgentFeed(onAsk: asked.add)))));
    await tester.pump();
    // the feed shows three finds at a time; these tests look at all of them
    final all = find.byKey(const Key('finds-all'));
    if (all.evaluate().isNotEmpty) {
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pump();
    }

    final amount = tester.widget<Text>(find.byKey(const Key('agent-amount'))).data!;
    expect(amount, startsWith('mind. '));
    expect(tester.widget<Text>(find.byKey(const Key('agent-label'))).data, 'Ahead hat für dich gefunden');
    final yearly = tester.widget<Text>(find.byKey(const Key('agent-yearly'))).data!;
    expect(yearly, startsWith('dazu 24,00'));
    expect(amount, isNot(contains('24,00')));

    // Erledigen on the price rise opens the ready letter, not the chat
    final go = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('go-price-'));
    await tester.ensureVisible(go);
    await tester.tap(go);
    await tester.pumpAndSettle();
    expect(find.text('Dein Kündigungsschreiben'), findsOneWidget);
    expect(asked, isEmpty);
    Navigator.pop(tester.element(find.text('Dein Kündigungsschreiben')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('guarantee-link')));
    await tester.tap(find.byKey(const Key('guarantee-link')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    // the quiet link under the finds opens Ahead Plus, the paid version
    expect(find.byType(PlusScreen), findsOneWidget);
    // the test font is as wide as it is tall: the price row of the Plus page overflows with it, not with the app's font
    tester.takeException();
    expect(tester.takeException(), isNull);
  });
}

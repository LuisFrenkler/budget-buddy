// Motion: the tokens, reduced motion, and the two moments that use them
// first: a find put away with "Später" and the refund result arriving.
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/refund_check_screen.dart';
import 'package:budget_buddy/services/ahead_agent.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/product_events.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:budget_buddy/utils/motion.dart';
import 'package:budget_buddy/widgets/agent_feed.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  final haptics = <String>[];

  setUpAll(() async {
    // in memory: a file write would not finish inside a widget test
    for (final name in ['settings', 'transactions', 'budgets', 'goals', 'badges', 'recurring', 'holdings', 'splits']) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
  });
  setUp(() async {
    await Hive.box('settings').clear();
    await Hive.box('transactions').clear();
    ProductEvents.reset();
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'HapticFeedback.vibrate') haptics.add('${call.arguments}'.split('.').last);
      return null;
    });
  });

  Finder keyStarts(String prefix) =>
      find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith(prefix));

  // a tax find with money in it and a price rise, as in guarantee_test
  Future<void> feed(WidgetTester tester, {bool reduce = false}) async {
    tester.view.physicalSize = const Size(750, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 3000, monthsWorked: 4, km: 20), year: now.year - 1);
    for (var i = 0; i < 4; i++) {
      await DB.addTx(Transaction(
          id: 'n$i',
          amountCents: i == 0 ? 1599 : 1399,
          category: 'Unterhaltung',
          isIncome: false,
          date: DateTime(now.year, now.month - i, 1),
          note: 'Netflix'));
    }
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduce), child: child!),
        home: Scaffold(body: SingleChildScrollView(child: AgentFeed(onAsk: (_) {})))));
    await tester.pump();
    // the feed shows three finds at a time; these tests look at all of them
    final all = find.byKey(const Key('finds-all'));
    if (all.evaluate().isNotEmpty) {
      await tester.ensureVisible(all);
      await tester.tap(all);
      await tester.pump();
    }
  }

  testWidgets('the tokens stay under 300 ms and movement gets no time under reduced motion', (tester) async {
    for (final d in [Motion.press, Motion.fast, Motion.base, Motion.reveal]) {
      expect(d, lessThan(const Duration(milliseconds: 300)));
    }
    expect(Motion.pressScale, inInclusiveRange(0.95, 0.98));
    for (final reduce in [true, false]) {
      late BuildContext context;
      await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Builder(builder: (c) {
            context = c;
            return const SizedBox();
          })));
      expect(Motion.reduce(context), reduce);
      expect(Motion.move(context, Motion.base), reduce ? Duration.zero : Motion.base);
      expect(Motion.move(context, Motion.reveal), reduce ? Duration.zero : Motion.reveal);
    }
  });

  testWidgets('"Später": one haptic, one snooze on a double tap, the card leaves and the headline follows',
      (tester) async {
    await feed(tester);
    final writes = <BoxEvent>[];
    final sub = Hive.box('settings').watch(key: 'agentSnoozed').listen(writes.add);
    addTearDown(sub.cancel);
    final later = keyStarts('later-tax-').first;
    final id = (tester.widget(later).key as ValueKey<String>).value.substring('later-'.length);
    final card = find.byKey(Key('find-$id'));
    final height = tester.getSize(card).height;
    expect(tester.getSize(card).width, tester.getSize(find.byType(AgentFeed)).width);
    String amount() => tester.widget<Text>(find.byKey(const Key('agent-amount'))).data!;
    final before = amount();
    expect(tester.hasRunningAnimations, isFalse); // the first paint stays still

    await tester.tap(later);
    await tester.tap(later, warnIfMissed: false);
    await tester.pump();
    expect(haptics, ['lightImpact']);
    expect(writes, hasLength(1));
    expect(AheadAgent.snoozed.keys, [id]);
    // the headline answers at once, and never shows two amounts on top of each other
    expect(amount(), isNot(before));
    expect(find.byKey(const Key('agent-label')), findsOneWidget);
    // the card is still there while it leaves; the next one slides under the finger and must not go too
    expect(card, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getSize(card).height, lessThan(height));
    await tester.tap(keyStarts('later-tax-').at(1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(card, findsNothing);
    expect(keyStarts('find-price-'), findsOneWidget);
    expect(writes, hasLength(1));
    expect(haptics, ['lightImpact']);
    await tester.pumpAndSettle(); // nothing runs on for ever (the ink and the caret finish too)
    // after the exit the next find can be put away as usual
    await tester.tap(keyStarts('later-tax-').first);
    await tester.pump(const Duration(milliseconds: 600));
    expect(AheadAgent.snoozed, hasLength(2));
    expect(haptics, ['lightImpact', 'lightImpact']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Später" under reduced motion: no collapse to watch, the card is closed with the next frame',
      (tester) async {
    await feed(tester, reduce: true);
    final cards = keyStarts('find-tax-').evaluate().length;
    await tester.tap(keyStarts('later-tax-').first);
    await tester.pump();
    expect(tester.getSize(keyStarts('find-tax-').first).height, 0);
    expect(AheadAgent.snoozed, hasLength(1));
    expect(haptics, ['lightImpact']);
    await tester.pump(const Duration(milliseconds: 600));
    expect(keyStarts('find-tax-'), findsNWidgets(cards - 1));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a held "Ja, los" lets its card sink a little and come back', (tester) async {
    await feed(tester);
    final go = keyStarts('go-tax-').first;
    double scale() =>
        tester.widget<AnimatedScale>(find.ancestor(of: go, matching: find.byType(AnimatedScale)).first).scale;
    final hold = await tester.startGesture(tester.getCenter(go));
    await tester.pump(const Duration(milliseconds: 200)); // past the wait that tells a press from a scroll
    expect(scale(), Motion.pressScale);
    await hold.cancel();
    await tester.pump();
    expect(scale(), 1);
    await tester.pumpAndSettle();
    expect(haptics, isEmpty);
  });

  testWidgets('"Ja, los" on a tax find: one haptic with the tap, and the page opens without waiting', (tester) async {
    await feed(tester);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
    await tester.tap(keyStarts('go-tax-').first);
    // no frame in between: nothing holds the page back
    expect(haptics, ['lightImpact']);
    expect(navigator.canPop(), isTrue);
  });

  testWidgets('the refund result arrives: haptic with its first frame, the final state after the transition',
      (tester) async {
    await tester.pumpWidget(MaterialApp(home: RefundCheckScreen(now: DateTime(2026, 11, 17))));
    expect(tester.hasRunningAnimations, isFalse); // the first question does not animate in
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('refund-gross')), '3000');
    await tester.pump();
    await tester.tap(find.byKey(const Key('refund-step-next')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(haptics, isEmpty);

    await tester.enterText(find.byKey(const Key('refund-km')), '40');
    await tester.tap(find.byKey(const Key('refund-check')));
    expect(haptics, isEmpty); // not before the number is there
    await tester.pump();
    expect(haptics, ['mediumImpact']);
    final headline = find.textContaining('für die offenen Jahre');
    expect(headline, findsOneWidget);
    Opacity fade() => tester.widget(find.ancestor(of: headline, matching: find.byType(Opacity)).first);
    expect(fade().opacity, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(fade().opacity, inExclusiveRange(0.5, 1));
    await tester.pump(const Duration(milliseconds: 600));
    expect(fade().opacity, 1);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.byKey(const Key('refund-steps')), findsNothing);
    expect(haptics, ['mediumImpact']);

    // back: the last question again, no bounce and nothing left running
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byKey(const Key('refund-km')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle(); // nothing runs on for ever (the ink and the caret finish too)
    expect(tester.takeException(), isNull);
  });
}

// Renders the Buddy screens to PNGs for a visual check and the store/landing
// shots. Not part of the test suite:
//   flutter test tool/screenshots_test.dart
// Pictures land in build/screens/.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/screens/buddy_memory_screen.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/tax_screen.dart';
import 'package:budget_buddy/screens/transaction_screen.dart';
import 'package:budget_buddy/screens/contracts_screen.dart';
import 'package:budget_buddy/screens/data_screen.dart';
import 'package:budget_buddy/legal/data_map.dart';
import 'package:budget_buddy/screens/goals_screen.dart';
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:budget_buddy/services/bank_sync.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/utils/money.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/screens/home_screen.dart';
import 'package:budget_buddy/screens/auth_screens.dart';
import 'package:budget_buddy/screens/invite_screen.dart';
import 'package:budget_buddy/services/account_service.dart';
import 'package:budget_buddy/services/buddy_history.dart';
import 'package:budget_buddy/services/buddy_service.dart';
import 'package:budget_buddy/services/buddy_memory.dart';
import 'package:budget_buddy/services/demo_data.dart';
import 'package:budget_buddy/services/invite_service.dart';
import 'package:budget_buddy/services/life_stages.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:budget_buddy/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:budget_buddy/services/buddy_proposals.dart';
import 'package:budget_buddy/widgets/buddy_chart.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

final _key = GlobalKey();
// flutter test tool/screenshots_test.dart --dart-define=LANG_CODE=en for English shots
const _lang = String.fromEnvironment('LANG_CODE', defaultValue: 'de');

Future<void> _shot(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 600));
  await expectLater(find.byKey(_key), matchesGoldenFile('../build/screens${_lang == 'de' ? '' : '/$_lang'}/$name.png'));
  // a sharp 3x copy for the landing page and the stores
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = 'build/screens/3x${_lang == 'de' ? '' : '/$_lang'}';
    Directory(dir).createSync(recursive: true);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _pump(WidgetTester tester, Widget home, {bool dark = true}) async {
  ThemeController.isDark.value = dark;
  L10n.lang.value = _lang;
  BuddyScreen.debugStatus = tr('KI an');
  tester.view.physicalSize = const Size(1170, 2532); // 390 x 844
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(dark),
      locale: _lang == 'de' ? const Locale('de', 'DE') : const Locale('en', 'IE'),
      supportedLocales: const [Locale('de', 'DE'), Locale('en', 'IE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.pump();
  await tester.tap(find.byTooltip(tr('Senden')));
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
  // let Hive finish writing the chat for real, outside the fake clock
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
}

void main() {
  setUpAll(() async {
    L10n.lang.value = _lang;
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
    final display = FontLoader('Bricolage');
    for (final w in ['Light', 'Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      display.addFont(rootBundle.load('assets/fonts/BricolageGrotesque-$w.ttf'));
    }
    await display.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(
          File('${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
              .readAsBytesSync())));
    await icons.load();
    final roboto = FontLoader('Roboto');
    for (final w in ['Regular', 'Medium', 'Bold']) {
      roboto.addFont(Future.value(ByteData.sublistView(File(
              '${Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter'}/bin/cache/artifacts/material_fonts/Roboto-$w.ttf')
          .readAsBytesSync())));
    }
    await roboto.load();
    Hive.init(Directory.systemTemp.createTempSync('shots').path);
    for (final name in ['transactions', 'settings', 'recurring', 'badges', 'budgets', 'holdings', 'goals', 'splits']) {
      await Hive.openBox(name);
    }
  });

  testWidgets('01 guest welcome', (tester) async {
    await _pump(tester, const BuddyScreen(guest: true));
    await _shot(tester, '01_guest_welcome');
  });

  testWidgets('02 guest chat', (tester) async {
    await _pump(tester, const BuddyScreen(guest: true));
    await _ask(tester, tr('Wie viel Notgroschen brauche ich?'));
    await _ask(tester, tr('Lohnt sich die Betriebsrente?'));
    await _shot(tester, '02_guest_chat');
    await tester.runAsync(() => BuddyHistory.clear(guest: true));
  });

  testWidgets('03 coach welcome with life stage', (tester) async {
    await tester.runAsync(() async {
      await DemoData.load();
      await Hive.box('settings').put('account', {'id': 'u1', 'name': 'Luis', 'email': 'luis@example.com'});
    });
    AccountService.current.value = Account.fromJson({'id': 'u1', 'name': 'Luis', 'email': 'luis@example.com'});
    await tester.runAsync(() async {
      await LifeStages.choose(LifeStages.firstJob);
      await LifeStages.setDone(LifeStages.firstJob, LifeStages.firstJob.steps[0], true);
      await LifeStages.setDone(LifeStages.firstJob, LifeStages.firstJob.steps[1], true);
    });
    await _pump(tester, const BuddyScreen(tab: true));
    await _shot(tester, '03_coach_welcome');
  });

  testWidgets('19 onboarding', (tester) async {
    await tester.runAsync(() async {
      await Hive.box('settings').put('account', {'id': 'u1', 'name': 'Luis', 'email': 'luis@example.com'});
    });
    AccountService.current.value = Account.fromJson({'id': 'u1', 'name': 'Luis', 'email': 'luis@example.com'});
    await _pump(tester, const BuddyScreen(tab: true));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 500));
    await _shot(tester, '19_onboarding_start');
    for (final chip in [tr('Erster Job'), tr('Am Monatsende'), tr('Notgroschen'), Money.format(300000)]) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(chip).last);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pump(const Duration(seconds: 1));
    await _shot(tester, '19_onboarding');
  });

  testWidgets('04 coach chat', (tester) async {
    await tester.runAsync(() => BuddyHistory.save([
      SavedMessage(true, 'Ich hab im Oktober meinen ersten Job angefangen. Wie viel sollte ich sparen?',
          DateTime.now().subtract(const Duration(minutes: 3))),
      SavedMessage(
          false,
          '**Starte mit 300 € im Monat**, das sind 15 Prozent deines Nettos.\n\n'
              '- Zuerst den Notgroschen auf 4.500 € bringen, dann einen ETF-Sparplan.\n'
              '- Frag nach der Betriebsrente, der Zuschuss ist geschenktes Geld.\n\n'
              'Nächster Schritt: Dauerauftrag am Zahltag einrichten, dann denkst du nicht mehr dran.',
          DateTime.now().subtract(const Duration(minutes: 3))),
    ]));
    await _pump(tester, const BuddyScreen(tab: true));
    await _ask(tester, _lang == 'de' ? 'Merk dir, dass mein Gehalt am 28. kommt' : 'Remember that my salary arrives on the 28th');
    await _ask(tester, _lang == 'de' ? 'Sparziel Notgroschen 4500' : 'Savings goal emergency fund 4500');
    await _shot(tester, '04_coach_chat');
    await tester.runAsync(() => BuddyHistory.clear());
  });

  testWidgets('05 memory', (tester) async {
    await tester.runAsync(() async {
      await BuddyMemory.add('Hat im Oktober den ersten Job angefangen');
      await BuddyMemory.add('Gehalt kommt am 28.');
      await BuddyMemory.add('Spart auf eine eigene Wohnung');
    });
    await _pump(tester, const BuddyMemoryScreen());
    await _shot(tester, '05_memory');
  });

  testWidgets('23 where your data is', (tester) async {
    await _pump(tester, const DataScreen(status: DataStatus(signedIn: true, bankLinked: true, aiConsent: true, memories: 2)));
    await _shot(tester, '23_data');
  });

  testWidgets('22 goal reached', (tester) async {
    final done = Goal(
        id: 'g1', name: tr('Notgroschen'), emoji: '🛟', targetCents: 300000, savedCents: 300000,
        createdAt: DateTime(2026), monthlyCents: 20000);
    await tester.runAsync(() => GoalsService.save(done));
    await _pump(tester, Builder(builder: (context) {
      return Scaffold(body: Center(child: FilledButton(onPressed: () => celebrateGoal(context, done), child: const Text('go'))));
    }));
    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 900));
    await _shot(tester, '22_goal_reached');
  });

  testWidgets('21 contract tip', (tester) async {
    await tester.runAsync(() async {
      for (final m in [8, 9, 10, 11]) {
        await DB.addTx(Transaction(
            id: 'nf$m', amountCents: 1399, category: 'Unterhaltung', date: DateTime(2026, m, 3), isIncome: false, note: 'Netflix'));
      }
    });
    await _pump(tester, const ContractsScreen());
    await tester.tap(find.text('Netflix').first);
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '21_contract_tip');
  });

  testWidgets('20 booking explained', (tester) async {
    final id = '${BankSync.prefix}paypal-netflix';
    await tester.runAsync(() => DB.addTx(Transaction(
        id: id,
        amountCents: 1399,
        category: 'Unterhaltung',
        date: DateTime(2026, 11, 3),
        isIncome: false,
        note: 'Netflix',
        raw: 'PayPal Europe S.a.r.l. et Cie S.C.A PP.8231.PP . NETFLIX, Ihr Einkauf bei NETFLIX '
            'Mandatsref. 4GJ2224BYP3MA Gläubiger-ID LU96ZZZ0000000000000000058')));
    await _pump(tester, TransactionScreen(id: id));
    await _shot(tester, '20_booking');
  });

  testWidgets('18 tax', (tester) async {
    await tester.runAsync(() async {
      await TaxEstimate.saveProfile(
          const TaxProfile(grossMonth: 3500, monthsWorked: 4, km: 18, officeDaysPerWeek: 3, homeDaysPerWeek: 2));
      for (final t in [
        Transaction(id: 'tx1', amountCents: 4990, category: 'Bildung', date: DateTime(2026, 9, 12), isIncome: false, note: 'Udemy Kurs'),
        Transaction(id: 'tx2', amountCents: 2499, category: 'Bildung', date: DateTime(2026, 10, 3), isIncome: false, note: 'Fachbuch Thalia'),
        Transaction(
            id: 'tx3', amountCents: 38900, category: 'Wohnen', date: DateTime(2026, 8, 28), isIncome: false, note: 'Umzugsunternehmen'),
      ]) {
        await DB.addTx(t);
      }
    });
    await _pump(tester, TaxScreen(now: DateTime(2026, 11, 15)));
    await _shot(tester, '18_tax');
  });

  testWidgets('06 share card', (tester) async {
    await _pump(
        tester,
        const Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: ShareCard(
                ShareCardData(
                  kicker: 'Abo-Check',
                  headline: 'Buddy hat 7 Abos und Verträge gefunden: 1.296 € im Jahr.',
                  body: '- **Fitnessstudio**: 34,90 € im Monat\n- **Streaming**: 13,99 € im Monat\n'
                      '- **Handy**: 19,99 € im Monat\n\nNächster Schritt: Einmal durchgehen, was du wirklich nutzt.',
                  text: '',
                ),
                hide: true,
              ),
            ),
          ),
        ));
    await _shot(tester, '06_share_card');
  });

  testWidgets('07 invite', (tester) async {
    InviteService.info.value = const InviteInfo('K7Q2M9', 'https://ahead.app/?ref=K7Q2M9', 1, 3, 5, 5);
    await _pump(tester, const InviteScreen());
    await _shot(tester, '07_invite');
  });

  testWidgets('08 light mode chat', (tester) async {
    await tester.runAsync(() => BuddyHistory.save([
      SavedMessage(true, _lang == 'de' ? 'Was ist eine Betriebsrente?' : 'What is a company pension?', DateTime.now()),
      SavedMessage(
          false,
          _lang == 'de'
              ? '**Altersvorsorge über deinen Arbeitgeber**, oft mit Zuschuss.\n\n'
                  '1. Ein Teil deines Bruttos fließt in einen Vertrag.\n'
                  '2. Spart der Arbeitgeber Sozialabgaben, gibt er meist 15 Prozent dazu.\n\n'
                  'Nächster Schritt: Frag die Personalabteilung nach Zuschuss und Kosten.'
              : '**Retirement savings through your employer**, often with a top-up.\n\n'
                  '1. Part of your gross pay goes into a plan.\n'
                  '2. If your employer saves social contributions, they usually add 15 percent.\n\n'
                  'Next step: Ask HR about the top-up and the costs.',
          DateTime.now()),
    ]));
    await _pump(tester, const BuddyScreen(tab: true), dark: false);
    await _shot(tester, '08_light_chat');
    // close the chat first: its check-in timers would keep the test waiting
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    // a Hive write awaited inside runAsync here never returns (fake clock):
    // clear without waiting, the next test starts from its own state anyway
    unawaited(BuddyHistory.clear());
  });

  testWidgets('09 nav on overview', (tester) async {
    await _pump(tester, const HomeScreen());
    HomeScreen.goTab.value = 0;
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, '09_nav_overview');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });

  for (final (n, tab) in [(10, 0), (11, 1), (12, 2), (13, 3)]) {
    testWidgets('$n light tab $tab', (tester) async {
      await _pump(tester, const HomeScreen(), dark: false);
      HomeScreen.goTab.value = tab;
      await tester.pump(const Duration(milliseconds: 800));
      await _shot(tester, '${n}_light_tab$tab');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  }

  testWidgets('14 start choice', (tester) async {
    await _pump(tester, const StartChoiceScreen());
    await _shot(tester, '14_start_choice');
  });

  testWidgets('17 buddy charts', (tester) async {
    await _pump(
        tester,
        Scaffold(
          body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              BuddyChartCard(BuddyChart(ChartKind.months, tr('Einnahmen und Ausgaben'), [
                (label: tr('Jun'), a: 253000, b: 171000),
                (label: tr('Jul'), a: 235000, b: 189000),
                (label: tr('Aug'), a: 253000, b: 162000),
                (label: tr('Sep'), a: 235000, b: 241000),
                (label: tr('Okt'), a: 253000, b: 158000),
                (label: tr('Nov'), a: 0, b: 96000),
              ])),
              BuddyChartCard(BuddyChart(ChartKind.categories, tr('Ausgaben nach Kategorie'), [
                (label: tr('Wohnen'), a: 78000, b: 0),
                (label: tr('Lebensmittel'), a: 21240, b: 0),
                (label: tr('Shopping'), a: 7735, b: 0),
                (label: tr('Essen gehen'), a: 7500, b: 0),
              ])),
              BuddyChartCard(BuddyChart(ChartKind.plan, tr('Sparplan bis {m} {y}', {'m': tr('Juli'), 'y': 2027}), [
                (label: tr('Nov'), a: 45000, b: 120000),
                (label: tr('Dez'), a: 55000, b: 120000),
                (label: tr('Jan'), a: 65000, b: 120000),
                (label: tr('Feb'), a: 75000, b: 120000),
                (label: tr('Mär'), a: 85000, b: 120000),
                (label: tr('Apr'), a: 95000, b: 120000),
                (label: tr('Mai'), a: 105000, b: 120000),
                (label: tr('Jun'), a: 115000, b: 120000),
                (label: tr('Jul'), a: 120000, b: 120000),
              ])),
            ]),
          ),
        ),
        dark: false);
    await _shot(tester, '17_buddy_charts');
  });

  testWidgets('15 sign up', (tester) async {
    await _pump(tester, const SignUpScreen());
    await _shot(tester, '15_sign_up');
  });

  testWidgets('16 sign up light', (tester) async {
    await _pump(tester, const SignUpScreen(), dark: false);
    await _shot(tester, '16_sign_up_light');
  });

  // the two phones on the landing page: the guest start, and the start with the three questions after sign-up
  testWidgets('landing guest finds', (tester) async {
    // the fresh start: the three questions as a promise and the two ways in
    await tester.runAsync(() => Hive.box('settings').delete('refundCheck'));
    await _pump(tester, const BuddyScreen(guest: true));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, 'landing_guest_finds');
  });

  testWidgets('landing agent feed', (tester) async {
    await tester.runAsync(() async {
      await DemoData.load();
      await Hive.box('settings').put('account', {'id': 'u1', 'name': 'Lena', 'email': 'lena@example.com'});
      await Hive.box('settings')
          .put('refundCheck', {'startYear': 2022, 'startMonth': 9, 'grossMonth': 3000.0, 'km': 20.0});
      await TaxEstimate.adoptRefundCheck(now: DateTime.now());
    });
    AccountService.current.value = Account.fromJson({'id': 'u1', 'name': 'Lena', 'email': 'lena@example.com'});
    await _pump(tester, const BuddyScreen(tab: true));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, 'landing_agent_feed');
  });

  // the phone in the landing page's hero: Ahead at work, a question answered from the person's numbers
  // and the next step it offers. A prepared conversation in the real chat screen.
  testWidgets('landing agent chat', (tester) async {
    final de = _lang == 'de';
    await tester.runAsync(() async {
      await DemoData.load();
      await Hive.box('settings').put('account', {'id': 'u1', 'name': 'Lena', 'email': 'lena@example.com'});
      await LifeStages.choose(LifeStages.firstJob);
      final t = DateTime.now().subtract(const Duration(minutes: 2));
      await BuddyHistory.save([
        SavedMessage(true, de ? 'Wo verliere ich gerade Geld?' : 'Where am I losing money right now?', t),
        SavedMessage(
            false,
            de
                ? '**Vier Verträge kosten dich 1.414,56 € im Jahr.** Das Fitnessstudio nutzt du seit März nicht mehr.\n\n'
                    '- Fitnessstudio: 34,90 €\n- Deutschlandticket: 58,00 €\n- Netflix: 13,99 €\n- Spotify: 10,99 €\n\n'
                    'Nächster Schritt: Fitnessstudio kündigen. Das Schreiben habe ich vorbereitet.'
                : '**Four contracts cost you €1,414.56 a year.** You have not used the gym since March.\n\n'
                    '- Gym: €34.90\n- Deutschlandticket: €58.00\n- Netflix: €13.99\n- Spotify: €10.99\n\n'
                    'Next step: Cancel the gym. I have prepared the letter.',
            t),
      ]);
    });
    AccountService.current.value = Account.fromJson({'id': 'u1', 'name': 'Lena', 'email': 'lena@example.com'});
    await _pump(tester, const BuddyScreen(tab: true));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 600));
    // from the start to the conversation
    await tester.tap(find.byKey(const Key('feed-toggle')));
    await tester.pump(const Duration(milliseconds: 600));
    await _shot(tester, 'landing_agent_chat');
    await tester.runAsync(() => BuddyHistory.clear());
  });
}

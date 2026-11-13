// Renders the Buddy screens to PNGs for a visual check and the store/landing
// shots. Not part of the test suite:
//   flutter test tool/screenshots_test.dart
// Pictures land in build/screens/.
import 'dart:io';

import 'package:budget_buddy/screens/buddy_memory_screen.dart';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/screens/invite_screen.dart';
import 'package:budget_buddy/services/account_service.dart';
import 'package:budget_buddy/services/buddy_history.dart';
import 'package:budget_buddy/services/buddy_memory.dart';
import 'package:budget_buddy/services/demo_data.dart';
import 'package:budget_buddy/services/invite_service.dart';
import 'package:budget_buddy/services/life_stages.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:budget_buddy/widgets/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

final _key = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 600));
  await expectLater(find.byKey(_key), matchesGoldenFile('../build/screens/$name.png'));
}

Future<void> _pump(WidgetTester tester, Widget home, {bool dark = true}) async {
  ThemeController.isDark.value = dark;
  tester.view.physicalSize = const Size(1170, 2532); // 390 x 844
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(RepaintBoundary(
    key: _key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme(dark),
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _ask(WidgetTester tester, String q) async {
  await tester.enterText(find.byType(TextField), q);
  await tester.pump();
  await tester.tap(find.bySemanticsLabel('Senden'));
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(seconds: 1));
  // let Hive finish writing the chat for real, outside the fake clock
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
    }
    await inter.load();
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
    await _ask(tester, 'Wie viel Notgroschen brauche ich?');
    await _ask(tester, 'Lohnt sich die Betriebsrente?');
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
    await _ask(tester, 'Merk dir, dass mein Gehalt am 28. kommt');
    await _ask(tester, 'Sparziel Notgroschen 4500');
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
      SavedMessage(true, 'Was ist eine Betriebsrente?', DateTime.now()),
      SavedMessage(
          false,
          '**Altersvorsorge über deinen Arbeitgeber**, oft mit Zuschuss.\n\n'
              '1. Ein Teil deines Bruttos fließt in einen Vertrag.\n'
              '2. Spart der Arbeitgeber Sozialabgaben, gibt er meist 15 Prozent dazu.\n\n'
              'Nächster Schritt: Frag die Personalabteilung nach Zuschuss und Kosten.',
          DateTime.now()),
    ]));
    await _pump(tester, const BuddyScreen(tab: true), dark: false);
    await _shot(tester, '08_light_chat');
    await tester.runAsync(() => BuddyHistory.clear());
  });
}

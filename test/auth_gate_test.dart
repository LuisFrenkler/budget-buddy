import 'dart:io';
import 'package:budget_buddy/screens/auth_gate.dart';
import 'package:budget_buddy/services/auth_service.dart';
import 'package:budget_buddy/services/settings_service.dart';
import 'package:budget_buddy/widgets/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('gate').path);
    await Hive.openBox('settings');
    await Settings.setAppLockEnabled(true);
    AuthService.debugAvailable = () async => true;
    AuthService.debugAuthenticate = () async => true;
  });

  testWidgets('balance covered in the app switcher; a quick switch does not lock', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AuthGate(child: Text('14.188,82 €'))));
    await tester.pumpAndSettle();
    expect(find.text('14.188,82 €'), findsOneWidget);

    // leaving the app: the logo covers the balance
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byType(BrandMark), findsOneWidget);

    // back within the grace period: shown again without asking
    var asked = 0;
    AuthService.debugAuthenticate = () async {
      asked++;
      return true;
    };
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(BrandMark), findsNothing);
    expect(find.text('14.188,82 €'), findsOneWidget);
    expect(asked, 0);
  });

  testWidgets('the lock covers pages opened on top of the home screen', (tester) async {
    final key = GlobalKey<NavigatorState>();
    var ok = false;
    AuthService.debugAuthenticate = () async => ok;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: key,
      builder: (context, child) => AuthGate(child: child!),
      home: const Text('Start'),
    ));
    await tester.pumpAndSettle();
    // still locked: a page pushed on top (e.g. from a notification) stays hidden
    key.currentState!.push(MaterialPageRoute(builder: (_) => const Text('Verträge 897,88 €')));
    await tester.pumpAndSettle();
    expect(find.text('BudgetBuddy ist gesperrt'), findsOneWidget);
    expect(find.text('Verträge 897,88 €', skipOffstage: false), findsOneWidget); // kept, not shown
    expect(find.text('Verträge 897,88 €').hitTestable(), findsNothing);

    // unlocking returns to exactly that page
    ok = true;
    await tester.tap(find.text('Entsperren'));
    await tester.pumpAndSettle();
    expect(find.text('BudgetBuddy ist gesperrt'), findsNothing);
    expect(find.text('Verträge 897,88 €').hitTestable(), findsOneWidget);
  });
}

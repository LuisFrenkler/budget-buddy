import 'package:budget_buddy/screens/auth_screens.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Hive.init('test_chat_first');
    for (final name in [
      'transactions',
      'budgets',
      'badges',
      'holdings',
      'recurring',
      'settings',
      'goals',
      'splits',
    ]) {
      await Hive.openBox(name);
    }
    ThemeController.isDark.value = true;
  });

  testWidgets('unsigned welcome opens Buddy chat, not a login carousel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme(true),
        home: const WelcomeScreen(),
      ),
    );
    await tester.pump(); // first frame; Buddy live() may still be pending
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Hallo, ich bin Buddy.'), findsOneWidget);
    expect(find.text('Konto'), findsOneWidget); // header CTA
    expect(find.text('Anmelden'), findsWidgets);
    expect(find.text('Kann ich mir 800 € Urlaub leisten?'), findsOneWidget);
    expect(find.text('Zeig mir Beispieldaten'), findsOneWidget);
    // no old carousel marketing slide
    expect(find.text('Erfassen, wie\ndu sprichst.'), findsNothing);
  });
}

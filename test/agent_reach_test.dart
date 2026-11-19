// The agent reaches the whole app: it opens every place (with and without the
// model), and every change it proposes is applied only after the tap and can
// be taken back from the log.
import 'dart:io';

import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/models/budget.dart';
import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/models/transaction.dart';
import 'package:budget_buddy/screens/buddy_actions.dart';
import 'package:budget_buddy/screens/buddy_screen.dart';
import 'package:budget_buddy/services/account_service.dart';
import 'package:budget_buddy/services/app_nav.dart';
import 'package:budget_buddy/services/buddy_app_guide.dart';
import 'package:budget_buddy/services/buddy_help.dart';
import 'package:budget_buddy/services/buddy_log.dart';
import 'package:budget_buddy/services/buddy_service.dart';
import 'package:budget_buddy/services/buddy_tools.dart';
import 'package:budget_buddy/services/contracts.dart';
import 'package:budget_buddy/services/db.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:budget_buddy/services/money_accounts.dart';
import 'package:budget_buddy/services/settings_service.dart';
import 'package:budget_buddy/utils/money.dart';
import 'package:budget_buddy/utils/theme.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const boxes = ['settings', 'transactions', 'budgets', 'goals'];
  final now = DateTime(2026, 11, 14);

  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('agentreach').path);
    for (final b in boxes) {
      await Hive.openBox(b);
    }
  });

  setUp(() async {
    for (final b in boxes) {
      await Hive.box(b).clear();
    }
    AppNav.go.value = null;
    L10n.lang.value = 'de';
    Money.masked = false;
    Settings.hideAmounts.value = false;
    ThemeController.isDark.value = true;
    AccountService.current.value = const Account('1', 'ada@ahead.app', 'Ada Lovelace');
    await DB.addTx(Transaction(
        id: 'g', amountCents: 240000, category: 'Gehalt', date: DateTime(2026, 10, 28), isIncome: true, note: 'Gehalt'));
    await DB.addTx(Transaction(
        id: 'r', amountCents: 6230, category: 'Lebensmittel', date: DateTime(2026, 11, 3), isIncome: false, note: 'Rewe'));
  });

  tearDownAll(() {
    AccountService.current.value = null;
    L10n.lang.value = 'de';
  });

  BuddyTools tools({Map<String, dynamic> snapshot = const {}}) => BuddyTools(tx: DB.getTx(), snapshot: snapshot, now: now);

  // the card the tool shows, applied and logged like a tap on the button
  Future<String> confirm(BuddyTools t) => t.proposals.single.apply(now: now);
  Future<String> takeBack() => BuddyLog.undo(BuddyLog.all().first.id);

  group('go', () {
    test('the open tool takes the person to a place, with the tax year', () {
      final r = tools().run('oeffnen', {'ort': 'steuer', 'jahr': 2024});
      expect(r['geoeffnet'], 'steuer');
      expect(AppNav.go.value, (place: 'steuer', year: 2024));
    });

    test('a place that does not exist opens nothing and says which exist', () {
      final r = tools().run('oeffnen', {'ort': 'mond'});
      expect(r['fehler'], contains('vertraege'));
      expect(AppNav.go.value, isNull);
    });

    test('the server offers exactly the places the app can open', () {
      final server = File('backend/lib/agent.dart').readAsStringSync();
      final list = RegExp(r'static const places = \[(.*?)\];', dotAll: true).firstMatch(server)!.group(1)!;
      expect(RegExp(r"'([a-z_]+)'").allMatches(list).map((m) => m.group(1)).toSet(), AppNav.places);
    });

    test('"Öffne …" opens the place without the model', () async {
      final said = await BuddyService.ask([const ChatMessage(true, 'Öffne meine Verträge')], live: false).join();
      expect(said, contains('Verträge & Abos'));
      expect(AppNav.go.value, (place: 'vertraege', year: null));
    });

    test('the sentences people use, and the ones that stay questions', () {
      expect(BuddyAppGuide.go('Zeig mir das Depot')?.place, 'depot');
      expect(BuddyAppGuide.go('Geh zu den Einstellungen')?.place, 'profil');
      expect(BuddyAppGuide.go('Geh bitte zu meinen Verträgen.')?.place, 'vertraege');
      expect(BuddyAppGuide.go('Öffne die Steuer 2024'), (place: 'steuer', year: 2024));
      expect(BuddyAppGuide.go('Show me my goals')?.place, 'ziele');
      expect(BuddyAppGuide.go('Open settings')?.place, 'profil');
      for (final q in ['Zeig mir meine Ausgaben im Mai', 'Show my accounts', 'Zeig mein Nettovermögen', 'Öffne den Mond']) {
        expect(BuddyAppGuide.matches(q), isFalse, reason: q);
      }
      // every place has at least its own name as a word
      for (final place in AppNav.places) {
        expect(BuddyAppGuide.label(place), isNot(place), reason: place);
      }
    });

    test('before sign-up nothing opens and the answer says why', () async {
      AccountService.current.value = null;
      final said = await BuddyService.ask([const ChatMessage(true, 'Zeig mir das Depot')], live: false).join();
      expect(said, contains('nicht angemeldet'));
      expect(AppNav.go.value, isNull);
      expect(BuddyAppGuide.placeOf('Wo finde ich Verträge?'), isNull);
    });

    testWidgets('a "Wo finde ich …?" answer gets a button that opens the place', (tester) async {
      final place = BuddyAppGuide.placeOf('Wo finde ich Verträge?')!;
      expect(place, 'vertraege');
      expect(BuddyAppGuide.placeOf('Wo ist der Notgroschen?'), 'vermoegen');
      final action = BuddyActions.open(place);
      expect(action.label, 'Verträge & Abos öffnen');
      await tester.pumpWidget(const SizedBox());
      action.run(tester.element(find.byType(SizedBox)));
      expect(AppNav.go.value?.place, 'vertraege');
    });

    test('the status line of the open tool says what happens', () {
      expect(buddyToolLine('Seite'), 'Öffnet die Seite…');
    });
  });

  group('change, always after the tap, with a way back', () {
    test('a budget that exists is changed, and goes back to its old limit', () async {
      await DB.addBudget(Budget(
          category: 'Lebensmittel', limitCents: 25000, startDate: DateTime(2026, 11, 1), endDate: DateTime(2026, 11, 30)));
      final t = tools()..run('budget_vorschlagen', {'kategorie': 'Lebensmittel', 'betrag': 300});
      expect(DB.getBudgets().single.limitCents, 25000);
      await confirm(t);
      expect(DB.getBudgets().single.limitCents, 30000);
      await takeBack();
      expect(DB.getBudgets().single.limitCents, 25000);
    });

    test('one booking gets another category and amount', () async {
      final t = tools();
      final r = t.run('buchung_aendern_vorschlagen',
          {'suchtext': 'rewe', 'datum': '2026-11-03', 'kategorie': 'Unterhaltung', 'betrag': 60});
      expect(r['karte'], 'gezeigt');
      expect(t.proposals.single.detail, contains('Lebensmittel → Unterhaltung'));
      Transaction rewe() => DB.getTx().firstWhere((x) => x.id == 'r');
      expect(rewe().category, 'Lebensmittel');
      await confirm(t);
      expect(rewe().category, 'Unterhaltung');
      expect(rewe().amountCents, 6000);
      expect(rewe().note, 'Rewe');
      await takeBack();
      expect(rewe().category, 'Lebensmittel');
      expect(rewe().amountCents, 6230);
    });

    test('a booking that is not there, an unknown category and no change are refused', () {
      expect(tools().run('buchung_aendern_vorschlagen', {'suchtext': 'Aldi', 'kategorie': 'Unterhaltung'})['fehler'],
          contains('keine Buchung'));
      expect(tools().run('buchung_aendern_vorschlagen', {'suchtext': 'Rewe', 'kategorie': 'Quatsch'})['fehler'],
          contains('Unterhaltung'));
      expect(tools().run('buchung_aendern_vorschlagen', {'suchtext': 'Rewe'})['fehler'], contains('nichts zu ändern'));
    });

    test('a booking is deleted and comes back', () async {
      final t = tools()..run('buchung_loeschen_vorschlagen', {'suchtext': 'Rewe'});
      expect(t.proposals.single.confirm, 'Löschen');
      expect(DB.getTx().length, 2);
      await confirm(t);
      expect(DB.getTx().map((x) => x.id), ['g']);
      await takeBack();
      expect(DB.getTx().map((x) => x.id).toSet(), {'g', 'r'});
    });

    test('a savings goal gets a new target and rate', () async {
      await GoalsService.save(
          Goal(id: 'u', name: 'Urlaub', emoji: '🎯', targetCents: 80000, savedCents: 10000, createdAt: now, monthlyCents: 5000));
      final t = tools()..run('sparziel_aendern_vorschlagen', {'ziel': 'Urlaub', 'betrag': 1200, 'monatlich': 100, 'bis': '2027-07'});
      expect(GoalsService.all().single.targetCents, 80000);
      await confirm(t);
      final g = GoalsService.all().single;
      expect((g.targetCents, g.monthlyCents, g.deadline, g.savedCents), (120000, 10000, DateTime(2027, 7, 31), 10000));
      await takeBack();
      final back = GoalsService.all().single;
      expect((back.targetCents, back.monthlyCents, back.deadline), (80000, 5000, null));
    });

    test('the balance of an account kept by hand is set', () async {
      int balance() => MoneyAccounts.balanceOf(MoneyAccounts.main, DB.getTx());
      expect(balance(), 233770);
      final t = tools()..run('kontostand_vorschlagen', {'betrag': 1500});
      expect(balance(), 233770);
      await confirm(t);
      expect(balance(), 150000);
      await takeBack();
      expect(balance(), 233770);
    });

    test('an account that comes from the bank keeps the bank\'s balance', () async {
      await Settings.setBankState('linked');
      expect(tools().run('kontostand_vorschlagen', {'betrag': 1500})['fehler'], contains('Bank'));
    });

    test('a regular payment that is no contract is hidden', () async {
      final t = tools(snapshot: const {
        'vertraegeUndAbos': [
          {'name': 'FitX', 'proMonat': 24.99}
        ]
      });
      expect(t.run('vertrag_ausblenden_vorschlagen', {'anbieter': 'Netflix'})['fehler'], isNotNull);
      t.run('vertrag_ausblenden_vorschlagen', {'anbieter': 'fitx'});
      expect(Contracts.hidden, isEmpty);
      await confirm(t);
      expect(Contracts.hidden, isNotEmpty);
      await takeBack();
      expect(Contracts.hidden, isEmpty);
    });

    test('settings: light mode, English and hidden amounts', () async {
      var t = tools()..run('einstellung_vorschlagen', {'was': 'design', 'wert': 'hell'});
      expect(Settings.darkMode, isTrue);
      await confirm(t);
      expect((Settings.darkMode, ThemeController.isDark.value), (false, false));
      await takeBack();
      expect((Settings.darkMode, ThemeController.isDark.value), (true, true));

      t = tools()..run('einstellung_vorschlagen', {'was': 'betraege_verbergen', 'wert': 'an'});
      await confirm(t);
      expect((Settings.hideAmounts.value, Money.masked), (true, true));
      await takeBack();
      expect((Settings.hideAmounts.value, Money.masked), (false, false));

      t = tools()..run('einstellung_vorschlagen', {'was': 'sprache', 'wert': 'en'});
      expect(t.proposals.single.detail, 'English');
      await confirm(t);
      expect(L10n.lang.value, 'en');
      await takeBack();
      expect(L10n.lang.value, 'de');

      expect(tools().run('einstellung_vorschlagen', {'was': 'design', 'wert': 'en'})['fehler'], contains('hell oder dunkel'));
    });
  });

  group('ask', () {
    test('what Ahead found on its own, and the price with the guarantee', () {
      final found = tools().run('funde', {});
      expect(found['funde'], isList);
      expect(found['schonZurueckgeholt'], 0);
      final m = tools(snapshot: const {
        'plus': {'aktiv': false}
      }).run('mitgliedschaft', {});
      expect(m['preis'], {'proMonat': 4.99, 'proJahr': 49.0});
      expect(m['garantie']['mindestensZurueck'], 98.0);
      expect(m['plus'], {'aktiv': false});
    });

    test('"Was kannst du alles?" names ask, go and change', () {
      final text = BuddyHelp.answer().text;
      for (final line in ['**Fragen:**', '**Hinbringen:**', '**Ändern:**', 'Übernehmen']) {
        expect(text, contains(line));
      }
    });
  });
}

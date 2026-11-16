import 'package:budget_buddy/l10n/l10n.dart';
import 'package:budget_buddy/services/account_service.dart';
import 'package:budget_buddy/services/buddy_app_guide.dart';
import 'package:budget_buddy/services/finance_snapshot.dart';
import 'package:budget_buddy/services/guest_buddy.dart';
import 'package:budget_buddy/services/local_buddy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    L10n.lang.value = 'de';
    AccountService.current.value = null;
  });
  tearDown(() {
    L10n.lang.value = 'de';
    AccountService.current.value = null;
  });

  test('password, in German and English', () {
    expect(BuddyAppGuide.matches('Kann ich mein Passwort ändern?'), isTrue);
    expect(BuddyAppGuide.matches('How do I change my password?'), isTrue);
    final out = BuddyAppGuide.answerOrNull('Kann ich mein Passwort ändern?')!;
    expect(out, contains('nicht angemeldet'));
    expect(out, contains('Profil › Konto erstellen'));
    expect(out, contains('Nächster Schritt:'));
    expect(out, isNot(contains('@')));
    AccountService.current.value = const Account('1', 'ada@ahead.app', 'Ada Lovelace');
    final inn = BuddyAppGuide.answerOrNull('Wie ändere ich mein Passwort?')!;
    expect(inn, contains('Profil › Mein Konto › Sicherheit › Passwort ändern'));
    expect(inn, contains('Nächster Schritt:'));
    expect(inn, isNot(contains('ada@ahead.app')));
    L10n.lang.value = 'en';
    AccountService.current.value = null;
    final en = BuddyAppGuide.answerOrNull('How do I change my password?')!;
    expect(en, contains("You're not signed in"));
    expect(en, contains('My account › Security › Change password'));
    expect(en, contains('Next step:'));
  });

  test('account name uses real fields and never invents one', () {
    expect(BuddyAppGuide.matches('Wie heißt mein Account?'), isTrue);
    expect(BuddyAppGuide.matches("What's my account name?"), isTrue);
    expect(BuddyAppGuide.matches("What's my email?"), isTrue);
    final out = BuddyAppGuide.answerOrNull('Wie heißt mein Account?')!;
    expect(out, contains('nicht angemeldet'));
    expect(out, isNot(contains('@')));
    AccountService.current.value = const Account('1', 'ada@ahead.app', 'Ada Lovelace');
    final inn = BuddyAppGuide.answerOrNull('Wie heißt mein Account?')!;
    expect(inn, contains('**Ada**'));
    expect(inn, contains('ada@ahead.app'));
    expect(inn, isNot(contains('Lovelace')));
    expect(inn, contains('Profil › Mein Konto'));
    AccountService.current.value = const Account('2', 'ada@ahead.app', '');
    expect(BuddyAppGuide.answerOrNull("What's my email?"), contains('**ada@ahead.app**'));
    expect(BuddyAppGuide.answerOrNull("What's my email?"), isNot(contains('null')));
    L10n.lang.value = 'en';
    AccountService.current.value = null;
    final en = BuddyAppGuide.answerOrNull("What's my account name?")!;
    expect(en, contains("You're not signed in"));
    expect(en, contains('Next step:'));
    AccountService.current.value = const Account('1', 'ada@ahead.app', 'Ada Lovelace');
    final named = BuddyAppGuide.answerOrNull("What's my email?")!;
    expect(named, contains('**Ada**'));
    expect(named, contains('ada@ahead.app'));
    expect(named, contains('Profile › My account'));
  });

  test('export and delete account, in German and English', () {
    expect(BuddyAppGuide.matches('Wo finde ich den Datenexport?'), isTrue);
    expect(BuddyAppGuide.matches('How do I export my data?'), isTrue);
    expect(BuddyAppGuide.matches('Wie lösche ich mein Konto?'), isTrue);
    expect(BuddyAppGuide.matches('How do I delete my account?'), isTrue);
    final exp = BuddyAppGuide.answerOrNull('Wo finde ich den Datenexport?')!;
    expect(exp, contains('Profil › Erweitert › Import, Export & Backup › Als CSV exportieren'));
    expect(exp, contains('Nächster Schritt:'));
    final gone = BuddyAppGuide.answerOrNull('Wie lösche ich mein Konto?')!;
    expect(gone, contains('nicht angemeldet'));
    expect(gone, isNot(contains('@')));
    AccountService.current.value = const Account('1', 'ada@ahead.app', 'Ada Lovelace');
    final del = BuddyAppGuide.answerOrNull('Konto löschen')!;
    expect(del, contains('Profil › Mein Konto › Konto löschen'));
    expect(del, contains('Nächster Schritt:'));
    L10n.lang.value = 'en';
    AccountService.current.value = null;
    final expEn = BuddyAppGuide.answerOrNull('How do I export my data?')!;
    expect(expEn, contains('Profile › Advanced › Import, export & backup › Export as CSV'));
    expect(expEn, contains('Next step:'));
    final delEn = BuddyAppGuide.answerOrNull('How do I delete my account?')!;
    expect(delEn, contains("You're not signed in"));
    expect(delEn, contains('Next step:'));
    AccountService.current.value = const Account('1', 'ada@ahead.app', 'Ada Lovelace');
    expect(BuddyAppGuide.answerOrNull('delete my account'), contains('Profile › My account › Delete account'));
  });

  test('other product questions get a path, money questions do not', () {
    expect(BuddyAppGuide.answerOrNull('Wo finde ich Plus'), contains('Ahead Plus'));
    expect(BuddyAppGuide.answerOrNull('Wo finde ich Datenschutz?'), contains('Datenschutzerklärung'));
    expect(BuddyAppGuide.answerOrNull('Wie schalte ich KI an/aus?'), contains('Buddy mit KI'));
    expect(BuddyAppGuide.answerOrNull('Was ist Ahead?'), contains('**Ahead**'));
    expect(BuddyAppGuide.answerOrNull('Was ist Buddy?'), contains('**Buddy**'));
    expect(BuddyAppGuide.answerOrNull('Wie melde ich mich ab?'), contains('abgemeldet'));
    expect(BuddyAppGuide.answerOrNull('Wo ist der Notgroschen?'), contains('Vermögen & Absicherung'));
    expect(BuddyAppGuide.answerOrNull('Wo finde ich Verträge?'), contains('Verträge & Abos'));
    expect(BuddyAppGuide.answerOrNull('Wo ist Geteilt?'), contains('Geteilte Ausgaben'));
    for (final q in [
      'Wie viel Notgroschen brauche ich?',
      'Welche Abos habe ich?',
      'Was kannst du alles?',
      'Wo liegen meine Daten?',
      'Habe ich Plus?',
      'What is my net worth?',
      'How is my emergency fund?',
    ]) {
      expect(BuddyAppGuide.matches(q), isFalse, reason: q);
    }
  });

  test('local and guest paths answer before the money engines', () {
    final s = FinanceSnapshot(
      today: DateTime(2026, 11, 15),
      balanceCents: 0,
      depotCents: 0,
      months: const [],
      topMerchants: const [],
      budgets: const [],
      contracts: const [],
      holdings: const [],
    );
    expect(LocalBuddy.answer('Kann ich mein Passwort ändern?', s), contains('Passwort ändern'));
    expect(GuestBuddy.offline('How do I change my password?'), contains('Passwort ändern'));
    L10n.lang.value = 'en';
    expect(GuestBuddy.offline('How do I change my password?'), contains('Change password'));
    expect(LocalBuddy.answer('Where do I export my data?', s), contains('Export as CSV'));
  });
}

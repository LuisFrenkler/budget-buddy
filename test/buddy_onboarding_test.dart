import 'dart:io';

import 'package:budget_buddy/services/buddy_memory.dart';
import 'package:budget_buddy/services/buddy_onboarding.dart';
import 'package:budget_buddy/services/life_stages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('onboarding').path);
    await Hive.openBox('settings');
  });
  setUp(() async => Hive.box('settings').clear());

  test('three tapped answers: life stage, payday, first goal as a card', () async {
    expect(BuddyOnboarding.shouldStart(), isTrue);
    final first = await BuddyOnboarding.start();
    expect(first.chips, contains('Erster Job'));
    expect(BuddyOnboarding.shouldStart(), isFalse);

    final payday = (await BuddyOnboarding.answer('Erster Job'))!;
    expect(LifeStages.current?.name, 'Erster Job');
    expect(payday.chips, contains('Am Monatsende'));

    final goal = (await BuddyOnboarding.answer('Am Monatsende'))!;
    expect(BuddyMemory.all().single.text, contains('28.'));
    expect(goal.chips, contains('Notgroschen'));

    final amount = (await BuddyOnboarding.answer('Notgroschen'))!;
    expect(amount.chips.first, contains('1.500'));

    final done = (await BuddyOnboarding.answer('3.000 €'))!;
    expect(done.done, isTrue);
    expect(done.goal!.note, 'Notgroschen');
    expect(done.goal!.cents, 300000);
    expect(BuddyOnboarding.active, isFalse);
  });

  test('"Etwas anderes" asks for the name, a typed day counts too', () async {
    await BuddyOnboarding.start();
    await BuddyOnboarding.answer('Nichts davon');
    expect(LifeStages.current, isNull);
    await BuddyOnboarding.answer('am 25.');
    expect(BuddyMemory.all().single.text, contains('25.'));
    final ask = (await BuddyOnboarding.answer('Etwas anderes'))!;
    expect(ask.text, contains('Wofür'));
    final amount = (await BuddyOnboarding.answer('Laptop'))!;
    expect(amount.text, contains('Laptop'));
    final again = (await BuddyOnboarding.answer('weiß nicht'))!;
    expect(again.done, isFalse);
    expect((await BuddyOnboarding.answer('1200'))!.goal!.cents, 120000);
  });

  test('"Später" and a real question end it, and it never comes back', () async {
    await BuddyOnboarding.start();
    expect((await BuddyOnboarding.answer('Später'))!.done, isTrue);
    expect(BuddyOnboarding.shouldStart(), isFalse);

    await Hive.box('settings').clear();
    await BuddyOnboarding.start();
    expect(await BuddyOnboarding.answer('Wie viel habe ich diesen Monat schon ausgegeben?'), isNull);
    expect(BuddyOnboarding.active, isFalse);
  });

  test('someone who already told Buddy things is not asked again', () async {
    await BuddyMemory.add('Gehalt kommt am 28.');
    expect(BuddyOnboarding.shouldStart(), isFalse);
  });
}

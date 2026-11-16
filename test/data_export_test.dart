// "Alle meine Daten": one readable file with everything the app keeps.
import 'dart:convert';
import 'dart:io';

import 'package:budget_buddy/legal/data_map.dart';
import 'package:budget_buddy/services/data_export.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('export');
    Hive.init(dir.path);
    for (final b in ['transactions', 'budgets', 'badges', 'holdings', 'recurring', 'goals', 'splits', 'settings']) {
      await Hive.openBox(b);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('device data, Buddy, payslips and where each kind lives', () async {
    await Hive.box('transactions').put('t1', {'id': 't1', 'amountCents': 1200, 'category': 'Lebensmittel', 'date': '2026-11-01T00:00:00.000', 'isIncome': false});
    await Hive.box('settings').put('buddyJournal', [
      {'q': 'Wie viel ist frei?', 'next': 'Budget prüfen'}
    ]);
    await Hive.box('settings').put('payslips', [
      {'brutto': 3000.0, 'monat': '2026-10'}
    ]);
    final j = jsonDecode(DataExport.build(status: const DataStatus(bankLinked: true), now: DateTime(2026, 11, 15)))
        as Map<String, dynamic>;
    expect(j['erstellt'], startsWith('2026-11-15'));
    expect((j['aufDiesemGeraet']['transactions'] as List).single['id'], 't1');
    expect((j['buddy']['notizen'] as List).single['q'], 'Wie viel ist frei?');
    expect((j['buddy']['gehaltsabrechnungen'] as List).single['brutto'], 3000.0);
    final where = j['woDieDatenLiegen'] as List;
    expect(where.firstWhere((x) => '${x['wo']}'.contains('Enable Banking'))['aktiv'], isTrue);
    expect(j['hinweis'], contains('verschlüsselte Kopie'));
    expect(j.containsKey('konto'), isFalse);
  });

  test('with the server part when it came', () {
    final j = jsonDecode(DataExport.build(status: const DataStatus(), server: {
      'konto': {'email': 'a@b.de'}
    })) as Map<String, dynamic>;
    expect(j['aufUnseremServer']['konto']['email'], 'a@b.de');
    expect(j['hinweis'], contains('aufUnseremServer'));
  });
}

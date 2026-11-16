import 'dart:io';

import 'package:budget_buddy/models/goal.dart';
import 'package:budget_buddy/services/goals_service.dart';
import 'package:budget_buddy/services/life_progress.dart';
import 'package:budget_buddy/services/life_stages.dart';
import 'package:budget_buddy/services/tax_estimate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() async {
    Hive.init(Directory.systemTemp.createTempSync('lifeprogress').path);
    for (final b in ['settings', 'goals', 'splits']) {
      await Hive.openBox(b);
    }
  });
  setUp(() async {
    for (final b in ['settings', 'goals', 'splits']) {
      await Hive.box(b).clear();
    }
  });

  LifeStep step(String id) => LifeStages.firstJob.steps.firstWhere((s) => s.id == id);

  test('what the app sees done is ticked off once', () async {
    await GoalsService.save(Goal(
        id: 'n', name: 'Notgroschen', emoji: '🛟', targetCents: 300000, createdAt: DateTime(2026, 11), monthlyCents: 15000));
    await TaxEstimate.saveProfile(const TaxProfile(grossMonth: 3000));
    await LifeProgress.payslipChecked();
    final fresh = await LifeProgress.sync();
    for (final id in ['gehalt', 'notgroschen', 'sparrate', 'steuer']) {
      expect(LifeStages.isDone(LifeStages.firstJob, step(id)), isTrue, reason: id);
    }
    expect(fresh.length, 4);
    expect(LifeStages.isDone(LifeStages.firstJob, step('betriebsrente')), isFalse);
  });

  test('a step unticked by hand stays unticked', () async {
    await LifeProgress.payslipChecked();
    await LifeProgress.sync();
    await LifeStages.setDone(LifeStages.firstJob, step('gehalt'), false);
    expect(await LifeProgress.sync(), isEmpty);
    expect(LifeStages.isDone(LifeStages.firstJob, step('gehalt')), isFalse);
  });
}

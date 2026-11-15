import 'package:budget_buddy/services/product_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(ProductEvents.reset);

  test('a non-zero euro amount activates once, a mask or zero does not', () async {
    expect(ProductEvents.hasFigure('•••••• €'), isFalse);
    expect(ProductEvents.hasFigure('0,00 € sind frei.'), isFalse);
    expect(ProductEvents.hasFigure('Frag mich was.'), isFalse);
    expect(ProductEvents.hasFigure('340 € sind frei.'), isTrue);
    expect(ProductEvents.hasFigure('€4.99 im Monat'), isTrue);

    await ProductEvents.noteAnswer('0,00 €', now: DateTime(2026, 11, 1));
    await ProductEvents.noteAnswer('Frag mich was.', now: DateTime(2026, 11, 1));
    expect(ProductEvents.log, isEmpty);

    await ProductEvents.noteAnswer('340 € sind frei.', now: DateTime(2026, 11, 1));
    await ProductEvents.noteAnswer('12 € nochmal', now: DateTime(2026, 11, 2));
    expect(ProductEvents.log, ['2026-11-01 activated']);
  });

  test('D1 and D7 are calendar days after activation, including the DST Sunday', () async {
    await ProductEvents.noteAnswer('10 €', now: DateTime(2026, 3, 28));
    await ProductEvents.noteOpen(now: DateTime(2026, 3, 28, 23));
    await ProductEvents.noteOpen(now: DateTime(2026, 3, 29, 1));
    await ProductEvents.noteOpen(now: DateTime(2026, 3, 29, 18));
    await ProductEvents.noteOpen(now: DateTime(2026, 4, 4));
    expect(ProductEvents.log, ['2026-03-28 activated', '2026-03-29 d1', '2026-04-04 d7']);
  });

  test('a trial is not a payment, and a free-text name is dropped', () async {
    await ProductEvents.notePlus(trial: true, charged: false, now: DateTime(2026, 11, 3));
    await ProductEvents.notePlus(trial: true, charged: false, now: DateTime(2026, 11, 4));
    await ProductEvents.notePlus(trial: false, charged: true, now: DateTime(2026, 11, 10));
    await ProductEvents.track('a@b.de');
    expect(ProductEvents.log, ['2026-11-03 trial_start', '2026-11-10 paid']);
  });

  test('remote stays off until send is set, and send gets only the name and the day', () async {
    final got = <String>[];
    await ProductEvents.track(ProductEvents.bankConnect, now: DateTime(2026, 11, 5));
    expect(got, isEmpty);
    ProductEvents.send = (name, day) async => got.add('$day $name');
    ProductEvents.reset();
    ProductEvents.send = (name, day) async => got.add('$day $name');
    await ProductEvents.track(ProductEvents.bankConnect, now: DateTime(2026, 11, 5));
    await ProductEvents.track(ProductEvents.bankConnect, now: DateTime(2026, 11, 6));
    expect(got, ['2026-11-05 bank_connect']);
  });
}

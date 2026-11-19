import 'package:budget_buddy/services/ahead_agent.dart';
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

  test('a find counts once per kind and sends the kind, never the id', () async {
    final got = <String>[];
    ProductEvents.send = (name, day) async => got.add(name);
    ProductEvents.sendKind = (name, kind) async => got.add('$name $kind');
    final day = DateTime(2026, 11, 5);
    await ProductEvents.track(ProductEvents.findShown, kind: ProductEvents.kindOf('price-Netflix-2026-11-01'), now: day);
    await ProductEvents.track(ProductEvents.findShown, kind: ProductEvents.kindOf('price-Spotify-2026-11-02'), now: day);
    await ProductEvents.track(ProductEvents.findShown, kind: ProductEvents.kindOf('tax-2025'), now: day);
    await ProductEvents.track(ProductEvents.findYesMoney, kind: 'priceUp', now: day);
    // an id the list does not know, or free text, counts as the plain event
    await ProductEvents.track(ProductEvents.findLater, kind: ProductEvents.kindOf('something-new-7'), now: day);
    await ProductEvents.track(ProductEvents.findLater, kind: 'Netflix 12,99', now: day);
    expect(got, ['find_shown priceUp', 'find_shown tax', 'find_yes_money priceUp', 'find_later']);
    expect(ProductEvents.log.first, '2026-11-05 find_shown priceUp');
  });

  test('without sendKind a find still counts by name', () async {
    final got = <String>[];
    ProductEvents.send = (name, day) async => got.add(name);
    await ProductEvents.track(ProductEvents.findShown, kind: 'tax');
    expect(got, ['find_shown']);
  });

  test('the kinds are the agent\'s finds: tax, its money kinds and the contracts look', () {
    // the account about to go below zero is a find of its own kind
    expect(ProductEvents.kinds, {'tax', 'contracts', 'overdraft', ...AheadAgent.moneyKinds.map((k) => k.name)});
    expect(ProductEvents.kindOf('tax-check'), 'tax');
    expect(ProductEvents.kindOf('contracts'), 'contracts');
    expect(ProductEvents.kindOf('abo-tip-2026-netflix'), 'subTip');
    expect(ProductEvents.kindOf('budget-over-food'), isNull);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/screens/depot_screen.dart';
import 'package:budget_buddy/widgets/instrument_avatar.dart';

void main() {
  test('ETFs of one fund house get different initials', () {
    expect(InstrumentAvatar.initials('iShares Core MSCI World'), 'W');
    expect(InstrumentAvatar.initials('iShares Core S&P 500'), 'S5');
    expect(InstrumentAvatar.initials('Apple'), 'A');
    expect(InstrumentAvatar.initials('Bitcoin'), 'B');
    expect(InstrumentAvatar.initials(''), '?');
  });

  test('allocation percentages always add up to 100', () {
    expect(wholePercents([1, 1, 1]), [34, 33, 33]);
    expect(wholePercents([5700, 4480, 2900, 2600, 2100]).fold<int>(0, (a, b) => a + b), 100);
    expect(wholePercents([0, 0]), [0, 0]);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/utils/amount_input.dart';

String type(String keys) {
  var s = '';
  for (final k in keys.split(' ')) {
    s = AmountInput.press(s, k);
  }
  return s;
}

void main() {
  group('AmountInput', () {
    test('builds an amount from key presses', () {
      expect(type('1 2 , 5'), '12,5');
      expect(type('1 2 , 5 0 9'), '12,50'); // max two decimals
      expect(type(', 5'), '0,5'); // comma first adds a leading zero
      expect(type('0 0 7'), '7'); // no leading zeros
      expect(type('1 , , 2'), '1,2'); // only one comma
      expect(type('1 2 del'), '1');
      expect(type('del'), '');
    });

    test('limits the number of euro digits', () {
      expect(type('1 2 3 4 5 6 7 8 9'), '1234567');
    });

    test('display adds thousands separators', () {
      expect(AmountInput.display(''), '0');
      expect(AmountInput.display('1234567'), '1.234.567');
      expect(AmountInput.display('1250,5'), '1.250,5');
      expect(AmountInput.display('999'), '999');
    });

    test('converts to and from cents', () {
      expect(AmountInput.cents('12,5'), 1250);
      expect(AmountInput.cents('12,'), 1200);
      expect(AmountInput.cents('0,07'), 7);
      expect(AmountInput.cents(''), 0);
      expect(AmountInput.fromCents(1250), '12,5');
      expect(AmountInput.fromCents(1200), '12');
      expect(AmountInput.fromCents(1207), '12,07');
    });
  });
}

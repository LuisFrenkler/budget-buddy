import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/screens/add_holding_screen.dart';

void main() {
  group('share counts', () {
    test('editing keeps every decimal, so saving unchanged keeps the exact count', () {
      for (final v in [0.123456, 0.00012345, 12.5, 3.0, 1000.0]) {
        expect(AddHoldingScreen.parseShares(AddHoldingScreen.trimNum(v)), v);
      }
      expect(AddHoldingScreen.trimNum(3), '3');
      expect(AddHoldingScreen.trimNum(0.123456), '0,123456');
    });

    test('German input like in the price fields', () {
      expect(AddHoldingScreen.parseShares('1.000'), 1000);
      expect(AddHoldingScreen.parseShares('1.000,5'), 1000.5);
      expect(AddHoldingScreen.parseShares('0,25'), 0.25);
      expect(AddHoldingScreen.parseShares('0.25'), 0.25);
      expect(AddHoldingScreen.parseShares(' 12 '), 12);
      expect(AddHoldingScreen.parseShares('abc'), isNull);
    });
  });
}

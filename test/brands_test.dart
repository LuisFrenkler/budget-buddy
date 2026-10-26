import 'package:budget_buddy/utils/brands.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('known merchants and instruments are recognised', () {
    expect(Brands.of('Netflix')!.mark, 'N');
    expect(Brands.of('ALDI SÜD Filiale 123')!.mark, 'A');
    expect(Brands.of('Lieferando.de')!.mark, 'L');
    expect(Brands.of('DB Fernverkehr')!.mark, 'DB');
    expect(Brands.of('Bitcoin')!.mark, '₿');
    expect(Brands.of('iShares Core MSCI World')!.mark, 'iS');
  });

  test('unknown or empty names fall back to the category', () {
    expect(Brands.of('Café'), isNull);
    expect(Brands.of('Miete'), isNull);
    expect(Brands.of(''), isNull);
    expect(Brands.of(null), isNull);
    // "db" only as a word, not inside another one
    expect(Brands.of('Feedback'), isNull);
  });
}

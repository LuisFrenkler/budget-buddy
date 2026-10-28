import 'package:budget_buddy_backend/enable_banking.dart';
import 'package:test/test.dart';

void main() {
  test('bank amount strings become integer cents without float', () {
    expect(EnableBanking.amountToCents('12.34'), 1234);
    expect(EnableBanking.amountToCents('12,34'), 1234);
    expect(EnableBanking.amountToCents('-0.10'), -10);
    expect(EnableBanking.amountToCents('0.1'), 10);
    expect(EnableBanking.amountToCents('100'), 10000);
    expect(EnableBanking.amountToCents('+3.005'), 300); // extra digits truncated
    expect(EnableBanking.amountToCents(''), 0);
    expect(EnableBanking.amountToCents('null'), 0);
  });
}

import 'package:budget_buddy_backend/enable_banking.dart';
import 'package:test/test.dart';

void main() {
  test('merchant category and salary booking text are kept off the title', () {
    final card = EnableBanking.parseTx({
      'booking_date': '2026-10-01',
      'transaction_amount': {'amount': '24.00'},
      'credit_debit_indicator': 'DBIT',
      'creditor': {'name': 'Mueller'},
      'remittance_information': ['POS'],
      'merchant_category_code': '5812',
      'bank_transaction_code': {'description': 'Kartenzahlung'},
      'transaction_id': 't1',
    });
    expect(card!.counterparty, 'Mueller');
    expect(card.purpose, 'POS');
    expect(card.mcc, '5812');
    expect(card.hint, 'Kartenzahlung');
    expect(card.amountCents, -2400);

    final pay = EnableBanking.parseTx({
      'booking_date': '2026-10-01',
      'transaction_amount': {'amount': '2500.00'},
      'credit_debit_indicator': 'CRDT',
      'debtor': {'name': 'Musterfirma GmbH'},
      'remittance_information': ['10/2026'],
      'bank_transaction_code': {'description': 'LOHN/GEHALT'},
      'entry_reference': 'e1',
    });
    expect(pay!.hint, 'LOHN/GEHALT');
    expect(pay.purpose, '10/2026');
    expect(pay.amountCents, 250000);
    expect(pay.id, 'e1');
  });
}

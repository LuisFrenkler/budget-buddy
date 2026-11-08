import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/utils/merchant.dart';

void main() {
  test('never titles a booking Mandats-/Mandantenreferenz', () {
    expect(
      Merchant.display(
        counterparty: '',
        purpose: 'Mandatsreferenz: XR-99-123456 Gläubiger-ID: DE12ZZZ',
      ),
      'Bankbuchung',
    );
    expect(Merchant.present('Mandatsreferenz'), 'Bankbuchung');
    expect(Merchant.present('Mandatsreferenz 1234567890'), 'Bankbuchung');
    expect(Merchant.present('Mandantenreferenz'), 'Bankbuchung');
    expect(Merchant.present('MREF:ABC99'), 'Bankbuchung');
    expect(Merchant.isSepaJunk('Mandantenreferenz XR-1'), isTrue);
  });

  test('keeps the merchant when SEPA junk sits in the purpose', () {
    expect(
      Merchant.display(
        counterparty: 'PayPal Europe',
        purpose: 'PAYPAL *NETFLIX Mandatsreferenz: ABC123',
      ),
      'Netflix',
    );
    expect(
      Merchant.display(
        counterparty: '',
        purpose: 'REWE SAGT DANKE 1234 Mandatsreferenz XR99',
      ),
      'Rewe',
    );
  });

  test('prefers a real counterparty over purpose noise', () {
    expect(
      Merchant.display(
        counterparty: 'Spotify AB',
        purpose: 'Mandatsreferenz: 55 Gläubiger-ID: DE00',
      ),
      'Spotify AB',
    );
  });

  test('present leaves normal titles alone', () {
    expect(Merchant.present('REWE Markt'), 'REWE Markt');
    expect(Merchant.present(null), 'Buchung');
  });
}

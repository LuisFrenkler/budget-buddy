// Signed in means signed in: the checkout never asks someone with an account
// to create one, also in the web preview without a server.
import 'package:budget_buddy/screens/checkout_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('who sees what at the checkout', () {
    expect(checkoutGate(blocked: false, demo: false, signedIn: false), CheckoutGate.pay);
    // the web preview: try Plus for free, never a sign-up or a payment form
    expect(checkoutGate(blocked: true, demo: true, signedIn: true), CheckoutGate.preview);
    expect(checkoutGate(blocked: true, demo: true, signedIn: false), CheckoutGate.preview);
    // no server reachable: signed in waits for the server, only without an account the sign-up
    expect(checkoutGate(blocked: true, demo: false, signedIn: true), CheckoutGate.offline);
    expect(checkoutGate(blocked: true, demo: false, signedIn: false), CheckoutGate.signUp);
  });
}

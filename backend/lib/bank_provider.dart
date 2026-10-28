// What the server needs from a bank data provider. Two implementations:
// EnableBanking (real banks via PSD2) and DemoBank (no credentials needed).

class BankAccount {
  final String uid;
  final String? iban;
  final String? name;
  const BankAccount(this.uid, {this.iban, this.name});

  Map<String, dynamic> toJson() => {'uid': uid, 'iban': iban, 'name': name};
}

class BankSession {
  final String id;
  final List<BankAccount> accounts;
  final DateTime validUntil;
  const BankSession(this.id, this.accounts, this.validUntil);
}

// one booked transaction, already normalized: signed cents, plain text
class BankTx {
  final String id;
  final DateTime date;
  final int amountCents; // positive = money in, negative = money out
  final String counterparty;
  final String purpose;
  final String mcc; // ISO 18245, '' when the bank sends none
  final String hint; // booking-code text, not part of the displayed title
  const BankTx(this.id, this.date, this.amountCents, this.counterparty, this.purpose, {this.mcc = '', this.hint = ''});

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': '${date.year}-${_two(date.month)}-${_two(date.day)}',
        'amountCents': amountCents,
        'counterparty': counterparty,
        'purpose': purpose,
        'mcc': mcc,
        'hint': hint,
      };

  static String _two(int n) => n.toString().padLeft(2, '0');
}

abstract class BankProvider {
  // 'live' or 'demo', shown in the app
  String get mode;

  // banks a user can pick, as {id, name, logo}
  Future<List<Map<String, dynamic>>> institutions(String country);

  // starts the consent flow and returns the link the user has to open
  Future<String> startAuth({
    required String institution,
    required String country,
    required String state,
    required String redirectUrl,
  });

  // exchanges the code from the bank's redirect for a session
  Future<BankSession> createSession(String code);

  // current balance of one account in cents
  Future<int> balance(String accountUid);

  // booked transactions of one account since [from]
  Future<List<BankTx>> transactions(String accountUid, DateTime from);

  // revokes the consent
  Future<void> endSession(String sessionId);
}

// One place money is kept: a current account, a savings account, cash.
// The first one ("main") is the account the app always had; its starting
// balance stays in Settings.openingBalanceCents.
class MoneyAccount {
  static const main = 'main';
  static const kinds = {'giro': 'Girokonto', 'spar': 'Sparkonto', 'bar': 'Bargeld'};

  final String id;
  final String name;
  final String kind; // a key of [kinds]
  final int openingCents; // balance before the first booking here (unused for main)
  final String? bank; // the bank's name for a linked account
  final String? iban;
  final String? link; // the bank link it syncs through; null = kept by hand

  const MoneyAccount({
    required this.id,
    required this.name,
    this.kind = 'giro',
    this.openingCents = 0,
    this.bank,
    this.iban,
    this.link,
  });

  bool get isMain => id == main;

  MoneyAccount copyWith({String? name, String? kind, int? openingCents, String? bank, String? iban, String? link}) =>
      MoneyAccount(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        openingCents: openingCents ?? this.openingCents,
        bank: bank ?? this.bank,
        iban: iban ?? this.iban,
        link: link ?? this.link,
      );

  // the same account no longer synced (its bank was disconnected)
  MoneyAccount unlinked() => MoneyAccount(id: id, name: name, kind: kind, openingCents: openingCents, bank: bank, iban: iban);

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind,
        'openingCents': openingCents,
        if (bank != null) 'bank': bank,
        if (iban != null) 'iban': iban,
        if (link != null) 'link': link,
      };

  factory MoneyAccount.fromMap(Map m) => MoneyAccount(
        id: '${m['id']}',
        name: '${m['name'] ?? 'Konto'}',
        kind: kinds.containsKey(m['kind']) ? m['kind'] as String : 'giro',
        openingCents: (m['openingCents'] as num?)?.toInt() ?? 0,
        bank: m['bank'] as String?,
        iban: m['iban'] as String?,
        link: m['link'] as String?,
      );

  // savings and overnight money accounts by their name at the bank
  static String guessKind(String name) {
    final n = name.toLowerCase();
    if (RegExp(r'spar|tagesgeld|festgeld|extra-konto|extrakonto|zins').hasMatch(n)) return 'spar';
    return 'giro';
  }
}

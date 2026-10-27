// A single portfolio position (a stock, ETF, crypto, ...).
//
// Prices are stored as integer cents (like the rest of the app). `shares` is a
// quantity and may be fractional, so it is a double; every money value derived
// from it is rounded to whole cents at the edge.
class Holding {
  final String id;
  final String name;            // e.g. "Apple"
  final String symbol;          // e.g. "AAPL" (optional, may be empty)
  final String type;            // 'Aktie' | 'ETF' | 'Krypto' | 'Sonstiges'
  final double shares;          // quantity held (supports fractional shares)
  final int buyPriceCents;      // average buy price per share, in cents
  final int currentPriceCents;  // latest known price per share, in cents
  // when that price came live from a market source; null for a price that was
  // typed in, imported or taken from the built-in reference list
  final DateTime? priceAt;

  Holding({
    required this.id,
    required this.name,
    required this.symbol,
    required this.type,
    required this.shares,
    required this.buyPriceCents,
    required this.currentPriceCents,
    this.priceAt,
  });

  // the same position with a fresh live price
  Holding withLivePrice(int cents, DateTime at) => Holding(
        id: id,
        name: name,
        symbol: symbol,
        type: type,
        shares: shares,
        buyPriceCents: buyPriceCents,
        currentPriceCents: cents,
        priceAt: at,
      );

  // total amount originally invested, in cents
  int get investedCents => (shares * buyPriceCents).round();

  // current market value, in cents
  int get valueCents => (shares * currentPriceCents).round();

  // absolute gain or loss, in cents (negative = loss)
  int get gainCents => valueCents - investedCents;

  // gain or loss as a percentage of the invested amount
  double get gainPercent =>
      investedCents == 0 ? 0 : gainCents / investedCents * 100;

  // true if the position is at or above break-even
  bool get isUp => gainCents >= 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'symbol': symbol,
      'type': type,
      'shares': shares,
      'buyPriceCents': buyPriceCents,
      'currentPriceCents': currentPriceCents,
      if (priceAt != null) 'priceAt': priceAt!.millisecondsSinceEpoch,
    };
  }

  factory Holding.fromMap(Map<String, dynamic> map) {
    return Holding(
      id: map['id'],
      name: map['name'],
      symbol: map['symbol'] ?? '',
      type: map['type'] ?? 'Aktie',
      shares: (map['shares'] as num).toDouble(),
      buyPriceCents: (map['buyPriceCents'] as num).toInt(),
      currentPriceCents: (map['currentPriceCents'] as num).toInt(),
      priceAt: map['priceAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((map['priceAt'] as num).toInt()),
    );
  }
}

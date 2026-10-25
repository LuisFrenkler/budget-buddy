// Reconstructs the current depot from a Trade Republic "Transaction export"
// CSV (comma-separated, quoted). Trade Republic only exports transactions, so
// we aggregate BUY/SELL rows per instrument into net positions with an average
// buy price.
import 'package:uuid/uuid.dart';
import '../models/holding.dart';
import 'holdings_csv_importer.dart';

class _Agg {
  final String name;
  final String symbol;
  final String type;
  double netShares = 0;
  double buyShares = 0;
  double buyCost = 0;
  double lastPrice = 0;
  _Agg(this.name, this.symbol, this.type);
}

class TradeRepublicImporter {
  static const _uuid = Uuid();

  // true if the CSV header looks like a Trade Republic export
  static bool looksLikeTradeRepublic(String content) {
    final first = content.split('\n').isEmpty ? '' : content.split('\n').first.toLowerCase();
    return first.contains('asset_class') && first.contains('shares');
  }

  static String _mapClass(String cls) {
    final c = cls.toUpperCase();
    if (c.contains('CRYPTO')) return 'Krypto';
    if (c.contains('FUND') || c.contains('ETF')) return 'ETF';
    if (c.contains('STOCK') || c.contains('EQUITY') || c.contains('SHARE')) return 'Aktie';
    return 'Sonstiges';
  }

  static HoldingsImportResult parse(String content) {
    final rows = _parseCsv(content);
    if (rows.length < 2) return const HoldingsImportResult([], 0);

    final header = rows.first.map((e) => e.toLowerCase().trim()).toList();
    int col(String n) => header.indexOf(n);
    final iType = col('type');
    final iClass = col('asset_class');
    final iName = col('name');
    final iSym = col('symbol');
    final iShares = col('shares');
    final iPrice = col('price');
    if (iType < 0 || iName < 0 || iShares < 0 || iPrice < 0) {
      return const HoldingsImportResult([], 0);
    }

    final agg = <String, _Agg>{};
    int skipped = 0;

    for (int r = 1; r < rows.length; r++) {
      final row = rows[r];
      if (row.length <= iPrice) continue;

      final type = row[iType].toUpperCase();
      if (type != 'BUY' && type != 'SELL') continue; // ignore cash/dividends/etc

      final name = row[iName].trim();
      final shares = double.tryParse(row[iShares].trim());
      final price = double.tryParse(row[iPrice].trim());
      if (name.isEmpty || shares == null || price == null) {
        skipped++;
        continue;
      }

      final symbol = iSym >= 0 ? row[iSym].trim() : '';
      final cls = iClass >= 0 ? row[iClass] : '';
      final key = symbol.isNotEmpty ? symbol : name;

      final a = agg.putIfAbsent(key, () => _Agg(name, symbol, _mapClass(cls)));
      if (shares > 0) {
        a.buyShares += shares;
        a.buyCost += shares * price;
      } else if (shares < 0 && a.buyShares > 0) {
        // moving-average cost: a sell removes shares at the current avg cost,
        // so the remaining cost basis (and thus the gain) stays correct
        final avg = a.buyCost / a.buyShares;
        final reduce = (-shares) > a.buyShares ? a.buyShares : -shares;
        a.buyShares -= reduce;
        a.buyCost -= avg * reduce;
      }
      a.netShares += shares; // buys are positive, sells negative
      if (price > 0) a.lastPrice = price; // rows are chronological -> latest price
    }

    final holdings = <Holding>[];
    agg.forEach((_, a) {
      if (a.netShares <= 1e-9) return; // fully sold / not held anymore
      final avgBuy = a.buyShares > 0 ? a.buyCost / a.buyShares : a.lastPrice;
      holdings.add(Holding(
        id: _uuid.v4(),
        name: a.name,
        symbol: a.symbol,
        type: a.type,
        shares: a.netShares,
        buyPriceCents: (avgBuy * 100).round(),
        currentPriceCents: (a.lastPrice * 100).round(),
      ));
    });

    holdings.sort((x, y) => y.valueCents.compareTo(x.valueCents));
    return HoldingsImportResult(holdings, skipped);
  }

  // minimal RFC-4180-ish CSV parser (handles quoted fields with commas)
  static List<List<String>> _parseCsv(String content) {
    final rows = <List<String>>[];
    for (final raw in content.split('\n')) {
      final line = raw.replaceAll('\r', '');
      if (line.isEmpty) continue;
      final fields = <String>[];
      final sb = StringBuffer();
      bool inQuotes = false;
      for (int i = 0; i < line.length; i++) {
        final c = line[i];
        if (c == '"') {
          if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
            sb.write('"');
            i++;
          } else {
            inQuotes = !inQuotes;
          }
        } else if (c == ',' && !inQuotes) {
          fields.add(sb.toString());
          sb.clear();
        } else {
          sb.write(c);
        }
      }
      fields.add(sb.toString());
      rows.add(fields);
    }
    return rows;
  }
}

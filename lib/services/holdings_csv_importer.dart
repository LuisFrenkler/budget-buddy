// Imports portfolio positions from a CSV file (a broker export or a manually
// prepared list) — a no-backend way to "connect" an existing depot.
//
// Expected format (one position per line, header skipped):
//   Name;Symbol;Typ;Anzahl;Kaufpreis;AktuellerKurs
//   Apple;AAPL;Aktie;10;150,00;180,00
//
// Typ is one of: Aktie, ETF, Krypto, Sonstiges. AktuellerKurs is optional; if
// missing it falls back to the buy price.
import 'package:uuid/uuid.dart';
import '../models/holding.dart';
import '../utils/money.dart';

class HoldingsImportResult {
  final List<Holding> holdings;
  final int skipped;
  const HoldingsImportResult(this.holdings, this.skipped);
}

class HoldingsCsvImporter {
  static const _uuid = Uuid();
  static const _types = ['Aktie', 'ETF', 'Krypto', 'Sonstiges'];

  static HoldingsImportResult parse(String content) {
    final lines = content.split('\n');
    final holdings = <Holding>[];
    int skipped = 0;

    for (int i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final h = parseLine(line);
      if (h != null) {
        holdings.add(h);
      } else {
        skipped++;
      }
    }
    return HoldingsImportResult(holdings, skipped);
  }

  static Holding? parseLine(String line) {
    if (line.isEmpty) return null;
    final parts = line.split(';');
    if (parts.length < 5) return null;

    try {
      final name = parts[0].trim();
      if (name.isEmpty) return null;

      final symbol = parts[1].trim();

      // match the type case-insensitively; default to Aktie
      final rawType = parts[2].trim().toLowerCase();
      final type = _types.firstWhere(
          (t) => t.toLowerCase() == rawType, orElse: () => 'Aktie');

      // "1.234,5" is German with a thousands dot; without a comma a dot is
      // the decimal point, so crypto amounts like 0.001 stay what they are
      final rawShares = parts[3].trim();
      final shares = double.tryParse(
          rawShares.contains(',') ? rawShares.replaceAll('.', '').replaceAll(',', '.') : rawShares);
      if (shares == null || shares <= 0) return null;

      final buyCents = Money.parseToCents(parts[4]);
      if (buyCents == null || buyCents <= 0) return null;

      final hasCurrent = parts.length > 5 && parts[5].trim().isNotEmpty;
      final currentCents = hasCurrent ? Money.parseToCents(parts[5]) : buyCents;
      if (currentCents == null || currentCents <= 0) return null;

      return Holding(
        id: _uuid.v4(),
        name: name,
        symbol: symbol,
        type: type,
        shares: shares,
        buyPriceCents: buyCents,
        currentPriceCents: currentCents,
      );
    } catch (_) {
      return null;
    }
  }
}

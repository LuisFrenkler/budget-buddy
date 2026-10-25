// A built-in list of well-known instruments so the user can pick a real
// stock/ETF/crypto. Symbols use Yahoo Finance notation (US plain, German .DE,
// Amsterdam .AS, Paris .PA, etc.) so PriceService can fetch live quotes.
//
// refCents is a recent reference price in EUR cents, used to pre-fill the
// current price the instant an instrument is selected; PriceService upgrades it
// to a true live value where reachable.
class Instrument {
  final String name;
  final String symbol;
  final String type; // 'Aktie' | 'ETF' | 'Krypto'
  final int refCents;
  const Instrument(this.name, this.symbol, this.type, this.refCents);
}

class Instruments {
  static const list = <Instrument>[
    // --- US tech / large caps ---
    Instrument('Apple', 'AAPL', 'Aktie', 26000),
    Instrument('Microsoft', 'MSFT', 'Aktie', 42000),
    Instrument('Amazon', 'AMZN', 'Aktie', 18000),
    Instrument('Alphabet (Google)', 'GOOGL', 'Aktie', 17000),
    Instrument('Nvidia', 'NVDA', 'Aktie', 11000),
    Instrument('Tesla', 'TSLA', 'Aktie', 23000),
    Instrument('Meta (Facebook)', 'META', 'Aktie', 48000),
    Instrument('Netflix', 'NFLX', 'Aktie', 62000),
    Instrument('Broadcom', 'AVGO', 'Aktie', 15000),
    Instrument('AMD', 'AMD', 'Aktie', 14000),
    Instrument('Intel', 'INTC', 'Aktie', 3000),
    Instrument('Adobe', 'ADBE', 'Aktie', 50000),
    Instrument('Salesforce', 'CRM', 'Aktie', 26000),
    Instrument('Oracle', 'ORCL', 'Aktie', 13000),
    Instrument('IBM', 'IBM', 'Aktie', 20000),
    Instrument('Cisco', 'CSCO', 'Aktie', 5000),
    Instrument('Qualcomm', 'QCOM', 'Aktie', 16000),
    Instrument('PayPal', 'PYPL', 'Aktie', 7000),
    Instrument('Uber', 'UBER', 'Aktie', 7000),
    Instrument('Palantir', 'PLTR', 'Aktie', 3000),
    // --- US other ---
    Instrument('Coca-Cola', 'KO', 'Aktie', 6000),
    Instrument('PepsiCo', 'PEP', 'Aktie', 15000),
    Instrument('McDonald\'s', 'MCD', 'Aktie', 26000),
    Instrument('Starbucks', 'SBUX', 'Aktie', 8000),
    Instrument('Nike', 'NKE', 'Aktie', 7000),
    Instrument('Walt Disney', 'DIS', 'Aktie', 9000),
    Instrument('Visa', 'V', 'Aktie', 26000),
    Instrument('Mastercard', 'MA', 'Aktie', 45000),
    Instrument('JPMorgan Chase', 'JPM', 'Aktie', 20000),
    Instrument('Bank of America', 'BAC', 'Aktie', 4000),
    Instrument('Berkshire Hathaway B', 'BRK-B', 'Aktie', 40000),
    Instrument('Johnson & Johnson', 'JNJ', 'Aktie', 15000),
    Instrument('Pfizer', 'PFE', 'Aktie', 2500),
    Instrument('Walmart', 'WMT', 'Aktie', 8000),
    Instrument('Procter & Gamble', 'PG', 'Aktie', 15000),
    Instrument('ExxonMobil', 'XOM', 'Aktie', 11000),
    Instrument('Boeing', 'BA', 'Aktie', 17000),
    // --- German DAX ---
    Instrument('SAP', 'SAP', 'Aktie', 19000),
    Instrument('Siemens', 'SIE.DE', 'Aktie', 17500),
    Instrument('Allianz', 'ALV.DE', 'Aktie', 28000),
    Instrument('Volkswagen Vz.', 'VOW3.DE', 'Aktie', 11000),
    Instrument('Mercedes-Benz', 'MBG.DE', 'Aktie', 6500),
    Instrument('BMW', 'BMW.DE', 'Aktie', 9000),
    Instrument('Porsche AG', 'P911.DE', 'Aktie', 6000),
    Instrument('BASF', 'BAS.DE', 'Aktie', 4800),
    Instrument('Deutsche Telekom', 'DTE.DE', 'Aktie', 2800),
    Instrument('Adidas', 'ADS.DE', 'Aktie', 22000),
    Instrument('Deutsche Bank', 'DBK.DE', 'Aktie', 1600),
    Instrument('Bayer', 'BAYN.DE', 'Aktie', 2800),
    Instrument('Infineon', 'IFX.DE', 'Aktie', 3500),
    Instrument('Siemens Healthineers', 'SHL.DE', 'Aktie', 5000),
    Instrument('Münchener Rück', 'MUV2.DE', 'Aktie', 46000),
    Instrument('DHL Group', 'DHL.DE', 'Aktie', 4000),
    Instrument('Airbus', 'AIR.DE', 'Aktie', 16000),
    Instrument('Rheinmetall', 'RHM.DE', 'Aktie', 50000),
    Instrument('E.ON', 'EOAN.DE', 'Aktie', 1300),
    Instrument('RWE', 'RWE.DE', 'Aktie', 3300),
    Instrument('Merck KGaA', 'MRK.DE', 'Aktie', 16000),
    Instrument('Zalando', 'ZAL.DE', 'Aktie', 3000),
    // --- Europe / other ---
    Instrument('ASML', 'ASML', 'Aktie', 90000),
    Instrument('LVMH', 'MC.PA', 'Aktie', 65000),
    Instrument('Nestlé', 'NESN.SW', 'Aktie', 9000),
    Instrument('Novo Nordisk', 'NVO', 'Aktie', 10000),
    Instrument('Shell', 'SHEL.L', 'Aktie', 3000),
    Instrument('TotalEnergies', 'TTE.PA', 'Aktie', 6000),
    Instrument('Ferrari', 'RACE', 'Aktie', 40000),
    // --- ETFs ---
    Instrument('iShares Core MSCI World', 'IWDA.AS', 'ETF', 9500),
    Instrument('Vanguard FTSE All-World', 'VWCE.DE', 'ETF', 11500),
    Instrument('iShares Core S&P 500', 'SXR8.DE', 'ETF', 56000),
    Instrument('iShares Nasdaq 100', 'SXRV.DE', 'ETF', 90000),
    Instrument('Xtrackers MSCI World', 'XDWD.DE', 'ETF', 10000),
    Instrument('Vanguard S&P 500', 'VUSA.AS', 'ETF', 10000),
    Instrument('iShares MSCI EM IMI', 'EUNM.DE', 'ETF', 3600),
    Instrument('Xtrackers MSCI EM', 'XMME.DE', 'ETF', 5500),
    Instrument('iShares STOXX Europe 600', 'EXSA.DE', 'ETF', 5500),
    // --- Crypto (live via CoinGecko) ---
    Instrument('Bitcoin', 'BTC', 'Krypto', 5800000),
    Instrument('Ethereum', 'ETH', 'Krypto', 320000),
    Instrument('Solana', 'SOL', 'Krypto', 14000),
    Instrument('Cardano', 'ADA', 'Krypto', 40),
    Instrument('XRP', 'XRP', 'Krypto', 50),
    Instrument('Dogecoin', 'DOGE', 'Krypto', 12),
    Instrument('Polkadot', 'DOT', 'Krypto', 600),
    Instrument('Litecoin', 'LTC', 'Krypto', 8000),
  ];

  // case-insensitive filter on name or symbol
  static List<Instrument> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list
        .where((i) => i.name.toLowerCase().contains(q) || i.symbol.toLowerCase().contains(q))
        .toList();
  }
}

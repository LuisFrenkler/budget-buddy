// Cheaper ways to keep a subscription you already have: the same provider's
// plan with ads, a yearly plan, a family or duo plan to share, a student
// price. Only the kind of saving, no prices: prices change often and differ
// by country, Buddy points the way and the person checks the current offer.
import '../l10n/l10n.dart';

class SubTip {
  final String provider;
  final List<String> ways; // werbung, jahresabo, teilen, student
  const SubTip(this.provider, this.ways);

  String get text => tr('Bei {x} geht es oft günstiger: {y}.', {
        'x': provider,
        'y': ways.map(_way).join(', '),
      });

  static String _way(String w) => switch (w) {
        'werbung' => tr('ein Abo mit Werbung'),
        'jahresabo' => tr('jährlich statt monatlich zahlen'),
        'teilen' => tr('ein Familien- oder Duo-Abo teilen'),
        'student' => tr('ein Studierenden-Tarif'),
        _ => w,
      };
}

class SubTips {
  static final _known = <(RegExp, String, List<String>)>[
    (RegExp(r'netflix', caseSensitive: false), 'Netflix', ['werbung', 'teilen']),
    (RegExp(r'spotify', caseSensitive: false), 'Spotify', ['teilen', 'student']),
    (RegExp(r'disney', caseSensitive: false), 'Disney+', ['werbung', 'jahresabo']),
    (RegExp(r'amazon prime|prime video|amzn prime', caseSensitive: false), 'Amazon Prime', ['jahresabo', 'student']),
    (RegExp(r'youtube', caseSensitive: false), 'YouTube Premium', ['teilen', 'student']),
    (RegExp(r'apple music', caseSensitive: false), 'Apple Music', ['teilen', 'student']),
    (RegExp(r'icloud|apple one', caseSensitive: false), 'iCloud/Apple One', ['teilen']),
    (RegExp(r'dazn', caseSensitive: false), 'DAZN', ['jahresabo']),
    (RegExp(r'wow\b|sky\b', caseSensitive: false), 'WOW/Sky', ['jahresabo']),
    (RegExp(r'adobe', caseSensitive: false), 'Adobe', ['jahresabo', 'student']),
    (RegExp(r'microsoft 365|office 365', caseSensitive: false), 'Microsoft 365', ['jahresabo', 'teilen']),
    (RegExp(r'chatgpt|openai', caseSensitive: false), 'ChatGPT', ['jahresabo']),
    (RegExp(r'duolingo', caseSensitive: false), 'Duolingo', ['jahresabo', 'teilen']),
    (RegExp(r'audible', caseSensitive: false), 'Audible', ['jahresabo']),
    (RegExp(r'deezer', caseSensitive: false), 'Deezer', ['teilen', 'student']),
    (RegExp(r'paramount', caseSensitive: false), 'Paramount+', ['jahresabo']),
  ];

  static SubTip? forName(String name) {
    for (final (re, provider, ways) in _known) {
      if (re.hasMatch(name)) return SubTip(provider, ways);
    }
    return null;
  }
}

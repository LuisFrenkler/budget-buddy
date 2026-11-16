// Suggested Buddy questions. [pick] leads with a euro answer, then the snapshot.
// The empty chat uses [openers]: those three when a forecast exists, otherwise
// one salary question that still comes back with a figure.
import 'package:flutter/material.dart';
import 'category_coach.dart';
import 'finance_snapshot.dart';
import '../l10n/l10n.dart';

typedef BuddyChip = ({IconData icon, String text});

class BuddySuggestions {
  /// First value: a euro answer. Surfaced before deeper wealth topics.
  static List<BuddyChip> get activation => [
        (icon: Icons.account_balance_wallet_rounded, text: tr('Wie viel ist diesen Monat noch frei?')),
        (icon: Icons.savings_rounded, text: tr('Wo kann ich sparen?')),
        (icon: Icons.flight_takeoff_rounded, text: tr('Kann ich mir 800 € Urlaub leisten?')),
      ];

  /// Empty chat. [hasNumbers] is a forecast we can answer from.
  static List<BuddyChip> openers({required bool hasNumbers}) => hasNumbers
      ? activation
      : [
          (icon: Icons.payments_rounded, text: tr('Was bleibt von 3.000 € brutto netto?')),
        ];

  /// Always available, but after activation and live context.
  static List<BuddyChip> get deeper => [
        (icon: Icons.receipt_long_rounded, text: tr('Welche Abos und Verträge habe ich?')),
        (icon: Icons.account_balance_rounded, text: tr('Zeig mein Nettovermögen')),
        (icon: Icons.group_rounded, text: tr('Was schuldet mir die WG?')),
        (icon: Icons.elderly_rounded, text: tr('Richte meine Vorsorge ein')),
      ];

  /// @deprecated use [activation] — kept for callers that still name anchors.
  static List<BuddyChip> get anchors => activation;

  static List<BuddyChip> get fallback => [
        ...activation,
        ...deeper,
      ];

  /// Up to [max] chips: activation, then context-specific, then deeper, no duplicates.
  static List<BuddyChip> pick(FinanceSnapshot s, {int max = 6}) {
    final out = <BuddyChip>[];
    void add(BuddyChip c) {
      if (out.length >= max) return;
      if (out.any((x) => x.text == c.text)) return;
      out.add(c);
    }

    for (final a in activation) {
      add(a);
    }

    final misc = CategoryCoach.miscCount();
    if (misc >= 1) {
      add((icon: Icons.category_rounded, text: tr('Sonstiges aufräumen')));
    }

    for (final sp in s.splits) {
      if (sp.myCents == 0) continue;
      if (sp.myCents > 0) {
        add((
          icon: Icons.group_rounded,
          text: tr('Wer schuldet mir noch Geld in {x}?', {'x': sp.name}),
        ));
      } else {
        add((
          icon: Icons.group_rounded,
          text: tr('Wen muss ich in {x} noch ausgleichen?', {'x': sp.name}),
        ));
      }
    }

    if (s.depotCents > 0) {
      add((
        icon: Icons.show_chart_rounded,
        text: tr('Wie steht mein Depot?'),
      ));
    }

    if (s.vorsorge != null) {
      final v = s.vorsorge!;
      if (!v.gapClosed && v.gapMonthlyCents > 0) {
        add((
          icon: Icons.elderly_rounded,
          text: tr('Wie schließe ich meine Rentenlücke?'),
        ));
      } else {
        add((
          icon: Icons.elderly_rounded,
          text: tr('Wie steht meine Altersvorsorge?'),
        ));
      }
    }

    if (s.emergencyTargetCents != null && s.emergencyTargetCents! > 0) {
      final missing = s.emergencyTargetCents! - s.emergencyHaveCents;
      if (missing > 0) {
        add((
          icon: Icons.savings_outlined,
          text: tr('Wie baue ich meinen Notgroschen auf?'),
        ));
      }
    } else {
      add((
        icon: Icons.pie_chart_outline_rounded,
        text: tr('Wie ist mein Vermögen verteilt?'),
      ));
    }

    final openGoals = s.goals.where((g) => !g.reached).toList();
    if (openGoals.isNotEmpty) {
      final g = openGoals.first;
      add((
        icon: Icons.flag_rounded,
        text: tr('Wie steht mein Sparziel {x}?', {'x': g.name}),
      ));
    }

    for (final d in deeper) {
      add(d);
    }
    return out.take(max).toList();
  }
}

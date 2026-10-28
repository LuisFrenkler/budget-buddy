// Suggested Buddy questions on Start and in the chat welcome — grounded in
// snapshot domains (depot, splits, vorsorge, wealth) plus stable fallbacks.
import 'package:flutter/material.dart';
import 'category_coach.dart';
import 'finance_snapshot.dart';

typedef BuddyChip = ({IconData icon, String text});

class BuddySuggestions {
  /// Always surfaced on Start and in the empty Buddy welcome.
  static const anchors = <BuddyChip>[
    (icon: Icons.elderly_rounded, text: 'Richte meine Vorsorge ein'),
    (icon: Icons.account_balance_rounded, text: 'Zeig mein Nettovermögen'),
    (icon: Icons.group_rounded, text: 'Was schuldet mir die WG?'),
  ];

  static const fallback = <BuddyChip>[
    (icon: Icons.flight_takeoff_rounded, text: 'Kann ich mir 800 € Urlaub leisten?'),
    (icon: Icons.savings_rounded, text: 'Wo kann ich sparen?'),
    (icon: Icons.receipt_long_rounded, text: 'Welche Abos und Verträge habe ich?'),
    (icon: Icons.account_balance_wallet_rounded, text: 'Wie viel ist diesen Monat noch frei?'),
  ];

  /// Up to [max] chips: anchors, then context-specific, then fallbacks without duplicates.
  static List<BuddyChip> pick(FinanceSnapshot s, {int max = 6}) {
    final out = <BuddyChip>[];
    void add(BuddyChip c) {
      if (out.length >= max) return;
      if (out.any((x) => x.text == c.text)) return;
      out.add(c);
    }

    for (final a in anchors) {
      add(a);
    }

    final misc = CategoryCoach.miscCount();
    if (misc >= 3) {
      add((icon: Icons.category_rounded, text: 'Sonstiges aufräumen'));
    }

    for (final sp in s.splits) {
      if (sp.myCents == 0) continue;
      if (sp.myCents > 0) {
        add((
          icon: Icons.group_rounded,
          text: 'Wer schuldet mir noch Geld in ${sp.name}?',
        ));
      } else {
        add((
          icon: Icons.group_rounded,
          text: 'Wen muss ich in ${sp.name} noch ausgleichen?',
        ));
      }
    }

    if (s.depotCents > 0) {
      add((
        icon: Icons.show_chart_rounded,
        text: 'Wie steht mein Depot?',
      ));
    }

    if (s.vorsorge != null) {
      final v = s.vorsorge!;
      if (!v.gapClosed && v.gapMonthlyCents > 0) {
        add((
          icon: Icons.elderly_rounded,
          text: 'Wie schließe ich meine Rentenlücke?',
        ));
      } else {
        add((
          icon: Icons.elderly_rounded,
          text: 'Wie steht meine Altersvorsorge?',
        ));
      }
    }

    if (s.emergencyTargetCents != null && s.emergencyTargetCents! > 0) {
      final missing = s.emergencyTargetCents! - s.emergencyHaveCents;
      if (missing > 0) {
        add((
          icon: Icons.savings_outlined,
          text: 'Wie baue ich meinen Notgroschen auf?',
        ));
      }
    } else if (s.depotCents > 0 || s.balanceCents > 50000) {
      add((
        icon: Icons.pie_chart_outline_rounded,
        text: 'Wie ist mein Vermögen verteilt?',
      ));
    }

    final openGoals = s.goals.where((g) => !g.reached).toList();
    if (openGoals.isNotEmpty) {
      final g = openGoals.first;
      add((
        icon: Icons.flag_rounded,
        text: 'Wie steht mein Sparziel ${g.name}?',
      ));
    }

    for (final f in fallback) {
      add(f);
    }
    return out.take(max).toList();
  }
}

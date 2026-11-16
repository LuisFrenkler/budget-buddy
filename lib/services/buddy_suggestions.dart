// Suggested Buddy questions on Start and in the chat welcome.
// Anchors push the life-start niche (first money years); depot/wealth only
// if the user already has that data — never as the default story.
import 'package:flutter/material.dart';
import 'category_coach.dart';
import 'finance_snapshot.dart';

typedef BuddyChip = ({IconData icon, String text});

class BuddySuggestions {
  /// Always surfaced on Start and in the empty Buddy welcome.
  static const anchors = <BuddyChip>[
    (icon: Icons.work_outline_rounded, text: 'Was mach ich mit meinem Gehalt?'),
    (icon: Icons.flight_takeoff_rounded, text: 'Kann ich mir 800 € Urlaub leisten?'),
    (icon: Icons.home_outlined, text: 'Kann ich mir die Miete leisten?'),
  ];

  static const fallback = <BuddyChip>[
    (icon: Icons.receipt_long_rounded, text: 'Welche Abos und Verträge habe ich?'),
    (icon: Icons.account_balance_wallet_rounded, text: 'Wie viel ist diesen Monat noch frei?'),
    (icon: Icons.savings_rounded, text: 'Wie starte ich einen Notgroschen?'),
    (icon: Icons.group_rounded, text: 'Was schuldet mir die WG?'),
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
    if (misc >= 1) {
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

    if (s.emergencyTargetCents != null && s.emergencyTargetCents! > 0) {
      final missing = s.emergencyTargetCents! - s.emergencyHaveCents;
      if (missing > 0) {
        add((
          icon: Icons.savings_outlined,
          text: 'Wie baue ich meinen Notgroschen auf?',
        ));
      }
    } else {
      add((
        icon: Icons.savings_outlined,
        text: 'Wie starte ich einen Notgroschen?',
      ));
    }

    // Vorsorge / BAV only as a life-start question, not wealth theater.
    if (s.vorsorge != null) {
      add((
        icon: Icons.elderly_rounded,
        text: 'Was bedeutet meine Betriebsrente für mich?',
      ));
    }

    // Depot only if they already track one — never an anchor.
    if (s.depotCents > 0) {
      add((
        icon: Icons.show_chart_rounded,
        text: 'Wie steht mein Depot?',
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

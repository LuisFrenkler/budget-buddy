import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../services/db.dart';
import '../services/notification_service.dart';
import '../services/plus_service.dart';
import '../services/weekly_report.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/big_number.dart';
import '../widgets/buddy_orb.dart';
import 'buddy_screen.dart';
import 'plus_screen.dart';

// Buddy's weekly report. Everyone sees the week at a glance; the details
// and Buddy's tip are part of Plus.
class WeeklyReportScreen extends StatelessWidget {
  const WeeklyReportScreen({super.key});

  // remembers that this week's report was opened, so the home card goes away
  static Future<void> markSeen(WeeklyReport r) =>
      Hive.box('settings').put('weeklySeen', r.start.toIso8601String());

  static bool seen(WeeklyReport r) => Hive.box('settings').get('weeklySeen') == r.start.toIso8601String();

  @override
  Widget build(BuildContext context) {
    final report = WeeklyReportService.build(DB.getTx());
    // after the frame, never as a side effect of building
    if (report != null) WidgetsBinding.instance.addPostFrameCallback((_) => markSeen(report));
    return Scaffold(
      appBar: AppBar(title: Text(report == null ? 'Wochenbericht' : 'KW ${report.week}')),
      body: report == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('Für diese Woche gibt es noch keine Alltagsausgaben. Sobald welche da sind, wertet Buddy sie aus.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
              ),
            )
          : ValueListenableBuilder<bool>(
              valueListenable: PlusService.active,
              builder: (context, plus, _) => _Report(report: report, plus: plus),
            ),
    );
  }
}

class _Report extends StatelessWidget {
  final WeeklyReport report;
  final bool plus;
  const _Report({required this.report, required this.plus});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final change = r.change;
    // within ±3 % a week is simply normal: no colour, no sign
    final pct = change == null ? 0 : (change * 100).round();
    final usual = change != null && pct.abs() <= 3;
    final good = change == null || change <= 0;
    final badge = usual ? AppColors.textDim : (good ? AppColors.positiveText : AppColors.errorText);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Text('${Dates.dayMonth(r.start)} – ${Dates.dayMonth(r.end)}',
            style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(r.headline, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Alltagsausgaben · ohne Miete & Abos', style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Money.format(r.spentCents),
                  style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(width: 10),
              if (change != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: badge.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(usual ? '≈ Schnitt' : '${pct > 0 ? '+' : '−'}${pct.abs()} % zum Schnitt',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: badge)),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            _DayBars(report: r),
          ]),
        ),
        const SizedBox(height: 14),
        // the details: blurred with an invitation for the free tier
        plus ? _details(context) : _locked(context),
        const SizedBox(height: 18),
        _remind(context),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final r = report;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Buddy's take
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [AppColors.primary.withValues(alpha: 0.22), AppColors.primary.withValues(alpha: 0.06)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            BuddyOrb(size: 30),
            SizedBox(width: 10),
            Text('Buddy sagt', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          Text(r.summary, style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(r.tip, style: TextStyle(fontSize: 14.5, height: 1.45, color: AppColors.text.withValues(alpha: 0.85))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const BuddyScreen(question: 'Wie kann ich nächste Woche weniger ausgeben als diese?'))),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: const Text('Mit Buddy weiterreden'),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      // highlights
      Row(children: [
        Expanded(child: _fact('🗓️', WeeklyReportService.weekdays[r.topDay], 'teuerster Tag')),
        const SizedBox(width: 10),
        Expanded(child: _fact('🌿', '${r.noSpendDays}', r.noSpendDays == 1 ? 'Tag ohne Ausgaben' : 'Tage ohne Ausgaben')),
      ]),
      if (r.biggest != null) ...[
        const SizedBox(height: 10),
        _fact('💸', Money.format(r.biggest!.amountCents),
            'größte Ausgabe: ${(r.biggest!.note?.trim().isNotEmpty ?? false) ? r.biggest!.note!.trim() : r.biggest!.category}, ${Dates.weekdays[r.biggest!.date.weekday - 1]}'),
      ],
      const SizedBox(height: 18),
      const Text('Wohin das Geld ging', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          for (final c in r.categories.take(5))
            ListTile(
              leading: CategoryAvatar(c.category, isIncome: false, size: 38),
              title: Text(c.category, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: c.usualCents > 0
                  ? Text(
                      c.cents > c.usualCents
                          ? '${Money.format(c.cents - c.usualCents)} über Schnitt'
                          : c.cents < c.usualCents
                              ? '${Money.format(c.usualCents - c.cents)} unter Schnitt'
                              : 'wie immer',
                      style: TextStyle(
                          color: c.cents > c.usualCents * 1.2 ? AppColors.errorText : AppColors.textDim, fontSize: 12.5))
                  : Text('${c.count}× diese Woche', style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              trailing: Text(Money.format(c.cents), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    ]);
  }

  Widget _fact(String emoji, String value, String label) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Text(label,
                  style: TextStyle(color: AppColors.textDim, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ]),
      );

  Widget _locked(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(children: [
          // a real preview behind the blur, so it is clear what is waiting
          IgnorePointer(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
              child: SizedBox(height: 330, child: SingleChildScrollView(physics: const NeverScrollableScrollPhysics(), child: _details(context))),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: AppColors.bg.withValues(alpha: 0.35),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const BuddyOrb(size: 52),
                const SizedBox(height: 12),
                const Text('Buddys Auswertung und Tipp',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Wo dein Geld hinging, was auffiel und was du nächste Woche besser machen kannst.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => showPlus(context, reason: 'Buddys Wochenbericht mit Plus'),
                  child: const Text('Mit Plus freischalten'),
                ),
              ]),
            ),
          ),
        ]),
      );

  // invites to the Sunday reminder when notifications are off
  Widget _remind(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: NotificationService.enabled,
        builder: (context, on, _) => on || !NotificationService.canAsk
            ? Center(
                child: Text('Nächster Bericht: Sonntag, 18 Uhr',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              )
            : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  final ok = await NotificationService.enable();
                  if (ok) await NotificationService.hello();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), 
                        content: Text(ok
                            ? 'Buddy erinnert dich jeden Sonntag um 18 Uhr'
                            : NotificationService.problem)));
                  }
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Jeden Sonntag erinnern'),
              ),
      );
}

// spending per weekday, the most expensive day highlighted
class _DayBars extends StatelessWidget {
  final WeeklyReport report;
  const _DayBars({required this.report});

  @override
  Widget build(BuildContext context) {
    final max = report.perDay.fold<int>(1, (m, v) => v > m ? v : m);
    const labels = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return SizedBox(
      height: 110,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Container(
                height: 4 + 80 * report.perDay[i] / max,
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: i == report.topDay ? AppColors.primary : AppColors.primary.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(height: 6),
              Text(labels[i], style: TextStyle(color: AppColors.textDim, fontSize: 11.5)),
            ]),
          ),
      ]),
    );
  }
}

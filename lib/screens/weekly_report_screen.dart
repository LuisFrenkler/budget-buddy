import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/weekly_story.dart';
import 'buddy_screen.dart';
import 'smart_entry_sheet.dart';
import '../l10n/l10n.dart';

// Buddy's weekly report. Tip + categories free; Buddy-Chat mit Gratis-Kontingent.
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
      appBar: AppBar(
        title: Text(report == null ? tr('Wochenbericht') : 'KW ${report.week}'),
        actions: [
          if (report != null)
            IconButton(
              tooltip: tr('Als Story teilen'),
              onPressed: () {
                HapticFeedback.selectionClick();
                final change = report.change;
                final pct = change == null ? null : (change * 100).round().abs();
                final text = change == null || report.roughlyUsual
                    ? tr('Meine Woche mit Ahead: {headline}', {'headline': report.headline})
                    : tr('Meine Woche: {pct} % {x} als sonst · Ahead', {'pct': pct, 'x': change < 0 ? tr('weniger') : tr('mehr')});
                showWeeklyStoryShare(context, report, fallbackText: text);
              },
              icon: const Icon(Icons.ios_share_rounded),
            ),
        ],
      ),
      body: report == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.insights_rounded, size: 48, color: AppColors.primaryText),
                  const SizedBox(height: 16),
                  Text(
                      tr('Für diese Woche gibt es noch keine Alltagsausgaben. Sobald welche da sind, wertet Buddy sie aus.'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, height: 1.4)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      showSmartEntry(context);
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: Text(tr('Ausgabe erfassen')),
                  ),
                ]),
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
    // same band as the headline "Eine ganz normale Woche": no colour, no ±%
    final pct = change == null ? 0 : (change * 100).round();
    final usual = r.roughlyUsual;
    final good = change == null || change <= 0;
    final badge = usual ? AppColors.textDim : (good ? AppColors.positiveText : AppColors.errorText);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
      children: [
        Text('${Dates.dayMonth(r.start)} – ${Dates.dayMonth(r.end)}',
            style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(r.headline, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.6)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Alltagsausgaben · ohne Miete & Abos'), style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(Money.format(r.spentCents),
                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -1)),
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
                    child: Text(usual ? tr('wie üblich') : tr('{x}{x2} % zum Schnitt', {'x': pct > 0 ? '+' : '−', 'x2': pct.abs()}),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: badge)),
                  ),
                ),
            ]),
            const SizedBox(height: 18),
            _DayBars(report: r),
          ]),
        ),
        const SizedBox(height: 14),
        _details(context),
        const SizedBox(height: 18),
        _remind(context),
      ],
    );
  }

  Widget _details(BuildContext context) {
    final r = report;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Buddy's take, free for retention; AI chat CTA can still pitch Plus
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: AppColors.primary.withValues(alpha: 0.12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            BuddyOrb(size: 30),
            SizedBox(width: 10),
            Text(tr('Buddy sagt'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          Text(r.summary, style: const TextStyle(fontSize: 15, height: 1.4, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(r.tip, style: TextStyle(fontSize: 14.5, height: 1.45, color: AppColors.text.withValues(alpha: 0.85))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => BuddyScreen.open(
                context, tr('Wie kann ich nächste Woche weniger ausgeben als diese?')),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text(tr('Mit Buddy weiterreden')),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: _fact(Icons.calendar_today_rounded, WeeklyReportService.weekdays[r.topDay], tr('teuerster Tag'))),
        const SizedBox(width: 10),
        Expanded(
            child: _fact(Icons.eco_rounded, '${r.noSpendDays}',
                r.noSpendDays == 1 ? tr('Tag ohne Ausgaben') : tr('Tage ohne Ausgaben'))),
      ]),
      if (r.biggest != null) ...[
        const SizedBox(height: 10),
        _fact(Icons.payments_rounded, Money.format(r.biggest!.amountCents),
            tr('größte Ausgabe: {x}, {x2}', {'x': (r.biggest!.note?.trim().isNotEmpty ?? false) ? r.biggest!.note!.trim() : r.biggest!.category, 'x2': Dates.weekdays[r.biggest!.date.weekday - 1]})),
      ],
      const SizedBox(height: 18),
      Text(tr('Wohin das Geld ging'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          for (final c in r.categories.take(5))
            ListTile(
              leading: CategoryAvatar(c.category, isIncome: false, size: 38),
              title: Text(tr(c.category), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: c.usualCents > 0
                  ? Text(
                      c.cents > c.usualCents
                          ? tr('{x} über Schnitt', {'x': Money.format(c.cents - c.usualCents)})
                          : c.cents < c.usualCents
                              ? tr('{x} unter Schnitt', {'x': Money.format(c.usualCents - c.cents)})
                              : tr('wie immer'),
                      style: TextStyle(
                          color: c.cents > c.usualCents * 1.2 ? AppColors.errorText : AppColors.textDim, fontSize: 12.5))
                  : Text(tr('{count}× diese Woche', {'count': c.count}), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
              trailing: Text(Money.format(c.cents), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    ]);
  }

  Widget _fact(IconData icon, String value, String label) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, size: 22, color: AppColors.primaryText),
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

  // invites to the Sunday reminder when notifications are off
  Widget _remind(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: NotificationService.enabled,
        builder: (context, on, _) => on || !NotificationService.canAsk
            ? Center(
                child: Text(tr('Nächster Bericht: Sonntag, 18 Uhr'),
                    style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              )
            : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: () async {
                  final ok = await NotificationService.enable();
                  if (ok) await NotificationService.hello();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        duration: const Duration(milliseconds: 2800),
                        content: Text(ok
                            ? tr('Buddy erinnert dich jeden Sonntag um 18 Uhr')
                            : NotificationService.problem)));
                  }
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: Text(tr('Jeden Sonntag erinnern')),
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

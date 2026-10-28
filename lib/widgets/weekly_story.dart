import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import '../services/file_saver.dart';
import '../services/weekly_report.dart';
import '../utils/dates.dart';
import '../utils/theme.dart';
import 'brand.dart';

/// Opens the share sheet from Start — haptic, marks the week seen, one primary action.
Future<void> presentWeeklyStory(BuildContext context, WeeklyReport report) {
  HapticFeedback.lightImpact();
  final change = report.change;
  final pct = change == null ? null : (change * 100).round().abs();
  final fallback = change == null || report.roughlyUsual
      ? 'Meine Woche mit BudgetBuddy: ${report.headline}'
      : 'Meine Woche: $pct % ${change < 0 ? 'weniger' : 'mehr'} als sonst · BudgetBuddy';
  Hive.box('settings').put('weeklySeen', report.start.toIso8601String());
  return showWeeklyStoryShare(context, report, fallbackText: fallback);
}

// Weekly report as a shareable 9:16 story — percentages and counts only, no balances.
class WeeklyStory extends StatelessWidget {
  final WeeklyReport report;
  const WeeklyStory(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final change = r.change;
    final pct = change == null ? null : (change * 100).round().abs();
    final facts = <(String, String)>[
      if (change != null && !r.roughlyUsual)
        (change < 0 ? '📉' : '📈', '$pct % ${change < 0 ? 'weniger' : 'mehr'} als sonst'),
      if (r.roughlyUsual) ('✨', 'Eine ganz normale Woche'),
      if (r.categories.isNotEmpty)
        ('📊', 'Am meisten: ${r.categories.first.category}'),
      ('🌿', '${r.noSpendDays} ${r.noSpendDays == 1 ? 'Tag' : 'Tage'} ohne Ausgaben'),
      ('🗓️', 'Teuerster Tag: ${WeeklyReportService.weekdays[r.topDay]}'),
    ];
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7C5CFF), Color(0xFF5B3DF5), Color(0xFF38BDF8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: FittedBox(
          child: SizedBox(
            width: 360,
            height: 640,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    BrandMark(size: 30),
                    SizedBox(width: 10),
                    Text('BudgetBuddy', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  ]),
                  const Spacer(),
                  Text('KW ${r.week}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85))),
                  Text(r.headline,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2, height: 1.1)),
                  const SizedBox(height: 8),
                  Text('${Dates.dayMonth(r.start)} – ${Dates.dayMonth(r.end)}',
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.75))),
                  const SizedBox(height: 28),
                  for (final (emoji, text) in facts.take(4))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(children: [
                          Text(emoji, style: const TextStyle(fontSize: 20)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(text,
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.25)),
                          ),
                        ]),
                      ),
                    ),
                  const Spacer(),
                  Text('Und deine Woche?',
                      style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.85))),
                  const Text('Finanzen mit Buddy · BudgetBuddy',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showWeeklyStoryShare(BuildContext context, WeeklyReport report, {required String fallbackText}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16161E),
    showDragHandle: true,
    builder: (_) => _WeeklyStorySheet(report, fallbackText),
  );
}

class _WeeklyStorySheet extends StatefulWidget {
  final WeeklyReport report;
  final String fallbackText;
  const _WeeklyStorySheet(this.report, this.fallbackText);

  @override
  State<_WeeklyStorySheet> createState() => _WeeklyStorySheetState();
}

class _WeeklyStorySheetState extends State<_WeeklyStorySheet> with SingleTickerProviderStateMixin {
  final _key = GlobalKey();
  bool _busy = false;
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 520))
    ..forward();

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  Future<Uint8List> _png() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  String get _filename => 'budgetbuddy-kw${widget.report.week}.png';

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await shareImage(_filename, await _png(), text: widget.fallbackText);
      HapticFeedback.mediumImpact();
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: widget.fallbackText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 2800), content: Text('Bild ging nicht, Text ist kopiert')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Wochen-Story',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Nur Prozente und Counts — kein Kontostand.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.55),
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _in, curve: Curves.easeOut),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(CurvedAnimation(parent: _in, curve: Curves.easeOutCubic)),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: RepaintBoundary(key: _key, child: WeeklyStory(widget.report)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF16161E),
            ),
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share_rounded),
            label: Text(_busy ? 'Wird geteilt…' : 'Story teilen', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

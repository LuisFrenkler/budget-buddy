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
import '../l10n/l10n.dart';

/// Opens the share sheet from Start, haptic, marks the week seen, one primary action.
Future<void> presentWeeklyStory(BuildContext context, WeeklyReport report) {
  HapticFeedback.lightImpact();
  final change = report.change;
  final pct = change == null ? null : (change * 100).round().abs();
  final fallback = change == null || report.roughlyUsual
      ? tr('Meine Woche mit Ahead: {headline}', {'headline': report.headline})
      : tr('Meine Woche: {pct} % {x} als sonst · Ahead', {'pct': pct, 'x': change < 0 ? tr('weniger') : tr('mehr')});
  Hive.box('settings').put('weeklySeen', report.start.toIso8601String());
  return showWeeklyStoryShare(context, report, fallbackText: fallback);
}

// Weekly report as a shareable 9:16 story, percentages and counts only, no balances.
class WeeklyStory extends StatelessWidget {
  final WeeklyReport report;
  const WeeklyStory(this.report, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = report;
    final change = r.change;
    final pct = change == null ? null : (change * 100).round().abs();
    final facts = <(IconData, String)>[
      if (change != null && !r.roughlyUsual)
        (change < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
            tr('{pct} % {x} als sonst', {'pct': pct, 'x': change < 0 ? tr('weniger') : tr('mehr')})),
      if (r.roughlyUsual) (Icons.horizontal_rule_rounded, tr('Eine ganz normale Woche')),
      if (r.categories.isNotEmpty)
        (Icons.pie_chart_outline_rounded, tr('Am meisten: {category}', {'category': r.categories.first.category})),
      (Icons.event_available_outlined, tr('{noSpendDays} {x} ohne Ausgaben', {'noSpendDays': r.noSpendDays, 'x': r.noSpendDays == 1 ? tr('Tag') : tr('Tage')})),
      (Icons.calendar_today_outlined, tr('Teuerster Tag: {x}', {'x': WeeklyReportService.weekdays[r.topDay]})),
    ];
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        color: AppColors.brandDeep,
        child: FittedBox(
          child: SizedBox(
            width: 360,
            height: 640,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    BrandMark(size: 30),
                    SizedBox(width: 10),
                    Text(tr('Ahead'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  ]),
                  const Spacer(),
                  Text('KW ${r.week}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85))),
                  Text(r.headline,
                      style: const TextStyle(fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: -1.2, height: 1.1)),
                  const SizedBox(height: 8),
                  Text('${Dates.dayMonth(r.start)} – ${Dates.dayMonth(r.end)}',
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.75))),
                  const SizedBox(height: 28),
                  for (final (icon, text) in facts.take(4))
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
                          Icon(icon, color: Colors.white, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(text,
                                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, height: 1.25)),
                          ),
                        ]),
                      ),
                    ),
                  const Spacer(),
                  Text(tr('Und deine Woche?'),
                      style: TextStyle(fontSize: 15, color: Colors.white.withValues(alpha: 0.85))),
                  Text(tr('Finanzen mit Buddy · Ahead'),
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
    backgroundColor: const Color(0xFF1C1815),
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

  String get _filename => 'ahead-kw${widget.report.week}.png';

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await shareImage(_filename, await _png(), text: widget.fallbackText);
      HapticFeedback.mediumImpact();
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: widget.fallbackText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: Duration(milliseconds: 2800), content: Text(tr('Bild ging nicht, Text ist kopiert'))));
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
          Text(tr('Wochen-Story'),
              style: TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr('Nur Prozente und Anzahlen, kein Kontostand.'),
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
                        color: Colors.black.withValues(alpha: 0.35),
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
              foregroundColor: const Color(0xFF1C1815),
            ),
            onPressed: _busy ? null : _share,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share_rounded),
            label: Text(_busy ? tr('Wird geteilt…') : tr('Story teilen'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

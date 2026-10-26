import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../services/file_saver.dart';
import '../services/recap_service.dart';
import '../utils/dates.dart';
import 'brand.dart';

// The month as one picture in story format (9:16), made to be posted.
// Only percentages and counts, never amounts: nobody shares their balance.
class RecapStory extends StatelessWidget {
  final MonthRecap recap;
  const RecapStory(this.recap, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = recap;
    final month = Dates.months[r.month.month - 1];
    final prev = Dates.months[(r.month.month + 10) % 12];
    final change = r.expenseChange;
    final facts = <(String, String)>[
      if (r.savingsRate > 0) ('💰', '${r.savingsRate} % meines Einkommens gespart'),
      if (change != null && change != 0)
        (change < 0 ? '📉' : '📈', '${change.abs()} % ${change < 0 ? 'weniger' : 'mehr'} ausgegeben als im $prev'),
      if (r.topCategory != null) ('📊', '${r.topCategoryShare} % für ${r.topCategory}'),
      if (r.topMerchant != null && r.topMerchantVisits > 1) ('📍', '${r.topMerchantVisits}× bei ${r.topMerchant}'),
      ('🧾', '${r.bookings} Buchungen im Blick'),
    ];
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF7C5CFF), Color(0xFFB84DD8), Color(0xFFF472B6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        // everything scales with the picture, so preview and export match
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
                  const Text('Mein', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
                  Text(month,
                      style: const TextStyle(fontSize: 58, fontWeight: FontWeight.w900, letterSpacing: -2, height: 1)),
                  const SizedBox(height: 28),
                  for (final (emoji, text) in facts)
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
                  Text('Und dein Monat?',
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

// Shows the story picture and shares it as a PNG (1080 × 1920).
Future<void> showStoryShare(BuildContext context, MonthRecap recap, {required String fallbackText}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16161E),
    showDragHandle: true,
    builder: (_) => _StorySheet(recap, fallbackText),
  );
}

class _StorySheet extends StatefulWidget {
  final MonthRecap recap;
  final String fallbackText;
  const _StorySheet(this.recap, this.fallbackText);

  @override
  State<_StorySheet> createState() => _StorySheetState();
}

class _StorySheetState extends State<_StorySheet> {
  final _key = GlobalKey();
  bool _busy = false;

  // the preview is a few hundred pixels wide; rendered again at 1080 px
  Future<Uint8List> _png() async {
    final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    return png!.buffer.asUint8List();
  }

  String get _filename => 'budgetbuddy-${Dates.months[widget.recap.month.month - 1].toLowerCase()}.png';

  Future<void> _save() async {
    await saveImage(_filename, await _png());
    HapticFeedback.mediumImpact();
  }

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      await shareImage(_filename, await _png(), text: widget.fallbackText);
      HapticFeedback.mediumImpact();
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: widget.fallbackText));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Bild ging nicht, Text ist kopiert')));
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
          const Text('Deine Story',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Nur Prozente, keine Beträge.', style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
          const SizedBox(height: 14),
          SizedBox(
            height: height * 0.55,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: RepaintBoundary(key: _key, child: RecapStory(widget.recap)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF16161E),
            ),
            onPressed: _busy ? null : _share,
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Story teilen', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ),
          TextButton.icon(
            onPressed: _save,
            style: TextButton.styleFrom(foregroundColor: Colors.white70),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Bild speichern'),
          ),
        ]),
      ),
    );
  }
}

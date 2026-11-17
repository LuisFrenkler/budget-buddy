// A shareable 9:16 card: what Buddy found, in the brand colour, ready for a
// story or a group chat. Amounts can be hidden before sharing, so nobody
// posts their balance by accident.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/file_saver.dart';
import '../utils/theme.dart';
import 'brand.dart';
import 'buddy_orb.dart';
import 'buddy_text.dart';

class ShareCardData {
  final String kicker; // small line on top, e.g. "Frag Buddy"
  final String headline;
  final String body; // Buddy's little markdown
  final String text; // what goes along with the picture
  const ShareCardData({required this.kicker, required this.headline, required this.body, required this.text});
}

// "128,40 €" / "1.200 Euro" -> "••• €": keeps the shape, hides the number
String hideAmounts(String s) => s.replaceAllMapped(
    RegExp(r'(\d{1,3}(?:[.\s]\d{3})*(?:,\d{1,2})?|\d+(?:,\d{1,2})?)(\s?)(€|Euro|EUR)'), (m) => '•••${m[2]}${m[3]}');

class ShareCard extends StatelessWidget {
  final ShareCardData data;
  final bool hide;
  const ShareCard(this.data, {super.key, this.hide = false});

  @override
  Widget build(BuildContext context) {
    final body = hide ? hideAmounts(data.body) : data.body;
    final headline = hide ? hideAmounts(data.headline) : data.headline;
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9A5228), Color(0xFF5E2D12)],
          ),
        ),
        child: FittedBox(
          child: SizedBox(
            width: 360,
            height: 640,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 30),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white, fontFamily: 'Inter'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const BrandMark(size: 30),
                    const SizedBox(width: 10),
                    const Text.rich(TextSpan(children: [TextSpan(text: 'Ahead'), TextSpan(text: '.', style: TextStyle(color: Color(0xFFF0B489)))]),
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    const Spacer(),
                    Text(data.kicker.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white.withValues(alpha: 0.75))),
                  ]),
                  const Spacer(),
                  Text(headline,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: AppFonts.display, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -1, height: 1.12)),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const BuddyOrb(size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 250),
                          child: ClipRect(
                            child: RichMarkdown(body, glossary: false, fontSize: 14.5, color: Colors.white),
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const Spacer(),
                  Text(tr('Dein Agent, der verlorenes Geld findet'),
                      style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.8))),
                  const SizedBox(height: 2),
                  Text(tr('ahead · Frag Ahead'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showShareCard(BuildContext context, ShareCardData data, {bool hideByDefault = true}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1815),
    showDragHandle: true,
    builder: (_) => _ShareSheet(data, hideByDefault),
  );
}

class _ShareSheet extends StatefulWidget {
  final ShareCardData data;
  final bool hideByDefault;
  const _ShareSheet(this.data, this.hideByDefault);

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _key = GlobalKey();
  late bool _hide = widget.hideByDefault;
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    final text = _hide ? hideAmounts(widget.data.text) : widget.data.text;
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1080 / boundary.size.width);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await shareImage('ahead-buddy.png', png!.buffer.asUint8List(), text: text);
      HapticFeedback.mediumImpact();
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr('Bild ging nicht, Text ist kopiert'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr('Als Karte teilen'),
              style: const TextStyle(fontFamily: AppFonts.display, color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: height * 0.52),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: RepaintBoundary(key: _key, child: ShareCard(widget.data, hide: _hide)),
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hide,
            onChanged: (v) => setState(() => _hide = v),
            title: Text(tr('Beträge ausblenden'), style: const TextStyle(color: Colors.white)),
            subtitle: Text(tr('Zeigt ••• statt Euro-Beträgen'),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
          ),
          const SizedBox(height: 4),
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
            label: Text(_busy ? tr('Wird geteilt…') : tr('Teilen'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ]),
      ),
    );
  }
}

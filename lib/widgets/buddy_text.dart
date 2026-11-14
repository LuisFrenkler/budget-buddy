// How Buddy's words look: the little markdown he writes (**fett**, "- " and
// "1. " lists), his "Nächster Schritt:" line as a small callout (his
// signature), and money words with a dotted line that explain themselves on tap.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/glossary.dart';
import '../utils/theme.dart';

class RichMarkdown extends StatefulWidget {
  final String text;
  // explain money words on tap (off for the share card)
  final bool glossary;
  // a blinking caret while the answer streams in
  final bool streaming;
  // "Mehr dazu" in the explanation sheet asks Buddy about the term
  final void Function(String question)? onAsk;
  final double fontSize;
  final Color? color;
  const RichMarkdown(this.text,
      {super.key, this.glossary = true, this.streaming = false, this.onAsk, this.fontSize = 15.5, this.color});

  @override
  State<RichMarkdown> createState() => _RichMarkdownState();
}

class _RichMarkdownState extends State<RichMarkdown> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  static final _numbered = RegExp(r'^(\d{1,2})[.)]\s+');
  static const _next = 'Nächster Schritt:';

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final base = TextStyle(color: widget.color ?? AppColors.text, fontSize: widget.fontSize, height: 1.5);
    // models like long dashes even when asked not to: a comma reads the same
    final lines = widget.text.replaceAll(' — ', ', ').replaceAll('—', ', ').split('\n');
    // trailing empty lines while streaming would make the caret jump
    while (lines.length > 1 && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    final seen = <String>{};
    var budget = 3; // explained words per answer
    final children = <Widget>[];

    List<InlineSpan> spans(String line, {bool caret = false}) {
      final out = <InlineSpan>[];
      final parts = line.split('**');
      for (var i = 0; i < parts.length; i++) {
        final bold = i.isOdd;
        final part = parts[i];
        if (part.isEmpty) continue;
        final style = bold ? const TextStyle(fontWeight: FontWeight.w700) : null;
        if (!widget.glossary || budget <= 0) {
          out.add(TextSpan(text: part, style: style));
          continue;
        }
        var at = 0;
        for (final hit in Glossary.find(part, max: 6)) {
          if (budget <= 0 || seen.contains(hit.term.term)) continue;
          seen.add(hit.term.term);
          budget--;
          if (hit.start > at) out.add(TextSpan(text: part.substring(at, hit.start), style: style));
          final r = TapGestureRecognizer()..onTap = () => showGlossary(context, hit.term, onAsk: widget.onAsk);
          _recognizers.add(r);
          out.add(TextSpan(
            text: part.substring(hit.start, hit.end),
            recognizer: r,
            style: (style ?? const TextStyle()).copyWith(
              decoration: TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
              decorationColor: AppColors.brand,
              decorationThickness: 2,
            ),
          ));
          at = hit.end;
        }
        if (at < part.length) out.add(TextSpan(text: part.substring(at), style: style));
      }
      if (caret) out.add(const WidgetSpan(alignment: PlaceholderAlignment.middle, child: _Caret()));
      return out;
    }

    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final last = i == lines.length - 1;
      final caret = widget.streaming && last;
      final t = raw.trimLeft();
      if (t.trim().isEmpty) {
        children.add(const SizedBox(height: 8));
      } else if (t.startsWith('- ') || t.startsWith('• ') || t.startsWith('* ')) {
        children.add(Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: EdgeInsets.only(top: widget.fontSize * 0.62, right: 10, left: 2),
              child: Container(
                  width: 5, height: 5, decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle)),
            ),
            Expanded(child: Text.rich(TextSpan(children: spans(t.substring(2), caret: caret)), style: base)),
          ]),
        ));
      } else if (_numbered.hasMatch(t)) {
        final m = _numbered.firstMatch(t)!;
        children.add(Padding(
          padding: const EdgeInsets.only(top: 3, bottom: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 22,
              child: Text('${m.group(1)}.',
                  style: base.copyWith(color: AppColors.brand, fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Text.rich(TextSpan(children: spans(t.substring(m.end), caret: caret)), style: base)),
          ]),
        ));
      } else if (t.startsWith(_next) || t.startsWith('**$_next**')) {
        final rest = t.replaceFirst('**$_next**', '').replaceFirst(_next, '').trim();
        // Buddy's signature, like on the landing page: a stamp with a copper
        // frame and the label as a small tag
        children.add(Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.brand, width: 2),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(6)),
              child: Text(tr('Nächster Schritt').toUpperCase(),
                  style: const TextStyle(
                      fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
            ),
            const SizedBox(height: 7),
            Text.rich(TextSpan(children: spans(rest, caret: caret)),
                style: base.copyWith(fontWeight: FontWeight.w600)),
          ]),
        ));
      } else {
        children.add(Text.rich(TextSpan(children: spans(raw, caret: caret)), style: base));
      }
    }
    if (children.isEmpty && widget.streaming) children.add(const _Caret());
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }
}

// a soft copper caret that blinks while the answer arrives
class _Caret extends StatefulWidget {
  const _Caret();

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: CurvedAnimation(parent: _c, curve: Curves.easeInOut),
        child: Container(
          width: 8,
          height: 16,
          margin: const EdgeInsets.only(left: 2),
          decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(2)),
        ),
      );
}

// three dots while Buddy thinks
class TypingDots extends StatefulWidget {
  const TypingDots({super.key});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < 3; i++)
            Builder(builder: (_) {
              final phase = ((_c.value * 3) - i) % 3;
              final lift = phase < 1 ? Curves.easeInOut.transform(1 - (phase - 0.5).abs() * 2) : 0.0;
              return Transform.translate(
                offset: Offset(0, -4 * lift),
                child: Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: Color.lerp(AppColors.textDim, AppColors.brand, lift),
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
        ]),
      ),
    );
  }
}

// the explanation of a money word, with a way to ask more
Future<void> showGlossary(BuildContext context, GlossaryTerm term, {void Function(String question)? onAsk}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(tr('Kurz erklärt'),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.brand, letterSpacing: 0.3)),
            ),
          ]),
          const SizedBox(height: 12),
          Text(term.term, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(term.text, style: TextStyle(fontSize: 15.5, height: 1.5, color: AppColors.text)),
          if (onAsk != null) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
              onPressed: () {
                Navigator.pop(sheet);
                onAsk(tr('Was bedeutet {term} für mich?', {'term': term.term}));
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(tr('Was heißt das für mich?')),
            ),
          ],
        ]),
      ),
    ),
  );
}

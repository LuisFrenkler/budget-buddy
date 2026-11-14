// The small "ING · vor 3 Min." button on Start, Konto and Depot: how fresh
// the numbers are, and a tap fetches them again.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/dates.dart';
import '../utils/theme.dart';
import '../l10n/l10n.dart';

class SyncPill extends StatefulWidget {
  final String label; // e.g. the bank; empty shows only the time
  final DateTime? last; // when the numbers were fetched, null = never
  final Future<void> Function() onSync;

  const SyncPill({super.key, this.label = '', required this.last, required this.onSync});

  static String ago(DateTime? last, DateTime now) {
    if (last == null) return tr('Aktualisieren');
    final d = now.difference(last);
    if (d.inMinutes < 1) return tr('gerade eben');
    if (d.inMinutes < 60) return tr('vor {inMinutes} Min.', {'inMinutes': d.inMinutes});
    if (d.inHours < 24) return tr('vor {inHours} Std.', {'inHours': d.inHours});
    return tr('am {x}', {'x': Dates.dayMonth(last)});
  }

  @override
  State<SyncPill> createState() => _SyncPillState();
}

class _SyncPillState extends State<SyncPill> {
  bool _busy = false;
  bool _failed = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // "vor 3 Min." keeps counting while the screen stays open
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final when = _failed ? tr('Nicht aktualisiert') : SyncPill.ago(widget.last, DateTime.now());
    final text = widget.label.isEmpty ? when : '${widget.label} · $when';
    final tint = _failed ? AppColors.warningText : AppColors.textDim;
    return Semantics(
      button: true,
      label: tr('Aktualisieren, {text}', {'text': text}),
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: _busy
              ? null
              : () async {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _busy = true;
                    _failed = false;
                  });
                  try {
                    await widget.onSync();
                    if (mounted) setState(() => _failed = false);
                  } catch (_) {
                    if (mounted) setState(() => _failed = true);
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          // 36 pt high plus the row's room: a comfortable target
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _busy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(_failed ? Icons.sync_problem_rounded : Icons.sync_rounded,
                        size: 16, color: _failed ? AppColors.warningText : AppColors.primaryText),
                const SizedBox(width: 6),
                Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tint)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

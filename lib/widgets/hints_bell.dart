import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/hints_service.dart';
import '../services/notification_service.dart';
import '../utils/theme.dart';

// Bell in the top bar with the number of open hints; tapping it opens the
// list. [onOpen] takes the user to where they can act on a hint.
class HintsBell extends StatelessWidget {
  final List<Hint> hints;
  final void Function(HintTarget target) onOpen;
  final VoidCallback onChanged;

  const HintsBell({super.key, required this.hints, required this.onOpen, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final urgent = hints.any((h) => h.urgent);
    return IconButton(
      tooltip: hints.isEmpty ? 'Keine Hinweise' : '${hints.length} Hinweise',
      onPressed: () => _show(context),
      icon: Stack(clipBehavior: Clip.none, children: [
        Icon(hints.isEmpty ? Icons.notifications_none_rounded : Icons.notifications_rounded,
            color: hints.isEmpty ? AppColors.textDim : AppColors.text),
        if (hints.isNotEmpty)
          Positioned(
            right: -6,
            top: -5,
            child: Container(
              constraints: const BoxConstraints(minWidth: 17),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: urgent ? AppColors.error : AppColors.primary,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.bg, width: 2),
              ),
              child: Text('${hints.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }

  Future<void> _show(BuildContext context) async {
    HapticFeedback.selectionClick();
    final target = await showModalBottomSheet<HintTarget>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _HintsSheet(initial: hints),
    );
    onChanged();
    if (target != null) onOpen(target);
  }
}

class _HintsSheet extends StatefulWidget {
  final List<Hint> initial;
  const _HintsSheet({required this.initial});

  @override
  State<_HintsSheet> createState() => _HintsSheetState();
}

class _HintsSheetState extends State<_HintsSheet> {
  late final List<Hint> _hints = [...widget.initial];

  static (IconData, Color) _look(HintKind k) => switch (k) {
        HintKind.budgetOver => (Icons.error_rounded, AppColors.error),
        HintKind.budgetClose => (Icons.speed_rounded, AppColors.warning),
        HintKind.priceUp => (Icons.trending_up_rounded, AppColors.error),
        HintKind.upcoming => (Icons.event_rounded, AppColors.primary),
        HintKind.trialEnds => (Icons.workspace_premium_rounded, AppColors.warning),
        HintKind.bankExpires => (Icons.account_balance_rounded, AppColors.warning),
        HintKind.bigExpense => (Icons.priority_high_rounded, AppColors.warning),
        HintKind.goalDue => (Icons.flag_rounded, AppColors.positive),
        HintKind.stillCharging => (Icons.report_rounded, AppColors.error),
      };

  Future<void> _dismiss(Hint h) async {
    HapticFeedback.lightImpact();
    setState(() => _hints.remove(h));
    await HintsService.dismiss(h.id);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Hinweise', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Was gerade wichtig ist, aus deinen eigenen Daten.', style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          if (_hints.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Column(children: [
                  const Text('🌿', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 10),
                  const Text('Alles im grünen Bereich', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text('Sobald etwas wichtig wird, sagt BudgetBuddy Bescheid.',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
                ]),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _hints.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final h = _hints[i];
                  final (icon, color) = _look(h.kind);
                  return Dismissible(
                    key: ValueKey(h.id),
                    onDismissed: (_) => _dismiss(h),
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: Icon(Icons.done_rounded, color: AppColors.textDim),
                    ),
                    child: Material(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.pop(context, h.target),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
                              child: Icon(icon, color: color, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(h.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(h.text, style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
                              ]),
                            ),
                            IconButton(
                              tooltip: 'Erledigt',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _dismiss(h),
                              icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          // the gentle ask, at the moment hints make the value obvious
          ValueListenableBuilder<bool>(
            valueListenable: NotificationService.enabled,
            builder: (context, on, _) => on
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(children: [
                        const Icon(Icons.notifications_active_rounded, color: AppColors.primary),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Soll Buddy dir Bescheid sagen, auch wenn die App zu ist?',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: () async {
                            final ok = await NotificationService.enable();
                            if (ok) await NotificationService.hello();
                            if (!ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Mitteilungen sind in den Einstellungen deines Geräts blockiert')));
                            }
                          },
                          child: const Text('Ja, gern'),
                        ),
                      ]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

// A life stage as a short checklist: each step opens the conversation with
// Buddy, and the person ticks it off when it is done.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/buddy_memory.dart';
import '../services/life_stages.dart';
import '../utils/theme.dart';

// [onAsk] sends a step's question into the chat; [save] = remember the stage
Future<void> showLifeStage(BuildContext context, LifeStage stage,
    {required void Function(String question) onAsk, bool save = true}) async {
  HapticFeedback.selectionClick();
  if (save) await LifeStages.choose(stage);
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheet) => _LifeStageSheet(stage, onAsk: (q) {
      Navigator.pop(sheet);
      onAsk(q);
    }, save: save),
  );
  BuddyMemory.changed.value++;
}

class _LifeStageSheet extends StatefulWidget {
  final LifeStage stage;
  final void Function(String question) onAsk;
  final bool save;
  const _LifeStageSheet(this.stage, {required this.onAsk, required this.save});

  @override
  State<_LifeStageSheet> createState() => _LifeStageSheetState();
}

class _LifeStageSheetState extends State<_LifeStageSheet> {
  @override
  Widget build(BuildContext context) {
    final s = widget.stage;
    final done = LifeStages.progress(s);
    final height = MediaQuery.sizeOf(context).height;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(s.icon, color: AppColors.brand),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, style: const TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
                  Text(s.tagline, style: TextStyle(color: AppColors.textDim)),
                ]),
              ),
            ]),
            if (widget.save) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: s.steps.isEmpty ? 0 : done / s.steps.length,
                  minHeight: 6,
                  color: AppColors.brand,
                  backgroundColor: AppColors.surfaceAlt,
                ),
              ),
              const SizedBox(height: 6),
              Text(tr('{done} von {all} erledigt', {'done': done, 'all': s.steps.length}),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            for (var i = 0; i < s.steps.length; i++) _step(s, s.steps[i], i),
          ],
        ),
      ),
    );
  }

  Widget _step(LifeStage stage, LifeStep step, int i) {
    final done = widget.save && LifeStages.isDone(stage, step);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => widget.onAsk(step.prompt),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 14, 8),
            child: Row(children: [
              if (widget.save)
                IconButton(
                  tooltip: done ? tr('Wieder offen') : tr('Erledigt'),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await LifeStages.setDone(stage, step, !done);
                    setState(() {});
                  },
                  icon: Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      color: done ? AppColors.positiveText : AppColors.textDim),
                )
              else
                SizedBox(
                  width: 48,
                  child: Center(
                    child: Text('${i + 1}',
                        style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.brand, fontSize: 16)),
                  ),
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(step.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? AppColors.textDim : AppColors.text,
                      )),
                  const SizedBox(height: 2),
                  Text(step.subtitle, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
              Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppColors.textDim),
            ]),
          ),
        ),
      ),
    );
  }
}

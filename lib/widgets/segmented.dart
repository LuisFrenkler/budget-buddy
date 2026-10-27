import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/theme.dart';

// Segmented control with a sliding highlight, e.g. "Umsätze | Budgets | Analyse".
class Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  const Segmented({super.key, required this.labels, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / labels.length;
        return Stack(
          children: [
            // sliding highlight behind the active label
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: index * w,
              top: 0,
              bottom: 0,
              width: w,
              child: Container(
                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
              ),
            ),
            Row(
              children: [
                for (int i = 0; i < labels.length; i++)
                  Expanded(
                    // read as a button that says which one is chosen
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      label: labels[i],
                      excludeSemantics: true,
                      child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (i == index) return;
                        HapticFeedback.selectionClick();
                        onChanged(i);
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: i == index ? AppColors.text : AppColors.textDim,
                          ),
                          child: Text(labels[i]),
                        ),
                      ),
                    ),
                    ),
                  ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

// Keeps a widget pinned at the top of a CustomScrollView (e.g. a Segmented).
class PinnedHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  PinnedHeader({required this.child, this.height = 60});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant PinnedHeader old) => true;
}

// Section title with an optional action on the right, e.g. "Budgets   Alle".
class SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;

  const SectionTitle(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: Text(action!),
          ),
      ],
    );
  }
}

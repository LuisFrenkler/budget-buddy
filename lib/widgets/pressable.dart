// The two small answers of the interface: a card or main button sinks while
// it is held, and a figure that changed fades in instead of jumping.
import 'package:flutter/material.dart';
import '../utils/motion.dart';

// Hand [states] to the control inside (InkWell, FilledButton, TextButton):
// its own pressed state drives the scale, so a scroll that starts on it does not make it flinch.
class Pressable extends StatefulWidget {
  final Widget Function(WidgetStatesController states) builder;
  const Pressable({super.key, required this.builder});

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  late final _states = WidgetStatesController()..addListener(_sync);
  bool _down = false;

  void _sync() {
    final down = _states.value.contains(WidgetState.pressed);
    if (down != _down) setState(() => _down = down);
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: _down && !Motion.reduce(context) ? Motion.pressScale : 1,
        duration: _down ? Motion.press : Motion.fast,
        curve: Motion.out,
        child: widget.builder(_states),
      );
}

// [child] carries a key made from its value. The old value leaves at once:
// never two numbers on top of each other, and never a count-up.
class FadeSwap extends StatelessWidget {
  final Widget child;
  final AlignmentGeometry alignment;
  const FadeSwap({super.key, required this.child, this.alignment = Alignment.centerLeft});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.fast,
        reverseDuration: Duration.zero,
        switchInCurve: Motion.color,
        layoutBuilder: (current, previous) => Stack(alignment: alignment, children: [...previous, if (current != null) current]),
        child: child,
      );
}

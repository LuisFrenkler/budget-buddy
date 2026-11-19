import 'package:flutter/widgets.dart';

// Ahead's motion: four durations, three curves. New code uses nothing else.
class Motion {
  static const press = Duration(milliseconds: 120); // finger down
  static const fast = Duration(milliseconds: 160); // finger up, colour, small things
  static const base = Duration(milliseconds: 220); // entering or leaving inside a page
  static const reveal = Duration(milliseconds: 280); // rare: a result, a found amount

  static const Curve out = Curves.easeOutQuint; // Cubic(0.23, 1, 0.32, 1): enter, exit, press
  static const Curve inOut = Curves.easeInOutQuart; // Cubic(0.77, 0, 0.175, 1): moving on screen
  static const Curve color = Curves.ease; // colour, border, opacity only

  static const rise = 8.0; // logical px an entering element travels
  static const pressScale = 0.97; // a held button sinks: press down, fast back up

  // the OS asks for less motion: keep fades, drop movement, stop loops
  static bool reduce(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  // for anything that moves or resizes: no time at all under reduced motion
  static Duration move(BuildContext context, Duration d) => reduce(context) ? Duration.zero : d;
}

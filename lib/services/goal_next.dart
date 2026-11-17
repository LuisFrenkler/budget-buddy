// After a goal is reached: what the money that went into it each month can
// do next. The rate keeps going, only the target changes, so the habit
// stays. The Notgroschen leads to investing, another goal to the next open
// one, and with nothing open Buddy helps to find the next one.
import '../l10n/l10n.dart';
import '../models/goal.dart';
import '../utils/money.dart';

class GoalNext {
  final String text; // one sentence under the celebration
  final String question; // what Buddy is asked when tapped
  const GoalNext(this.text, this.question);

  static final _emergency = RegExp(r'notgroschen|notfall|puffer|reserve|polster|emergency', caseSensitive: false);

  static GoalNext suggest(Goal reached, List<Goal> all) {
    final rate = reached.monthlyCents;
    final open = all.where((g) => g.id != reached.id && !g.reached).toList()
      ..sort((a, b) => (a.deadline ?? DateTime(9999)).compareTo(b.deadline ?? DateTime(9999)));
    final rateText = rate > 0 ? Money.format(rate) : null;
    if (_emergency.hasMatch(reached.name)) {
      return GoalNext(
          rateText == null
              ? tr('Dein Polster steht. Als Nächstes kann Geld langfristig für dich arbeiten.')
              : tr('Dein Polster steht. Die {x} im Monat können jetzt langfristig für dich arbeiten.', {'x': rateText}),
          tr('Mein Notgroschen ist voll. Wie lege ich jetzt langfristig an, und wie viel davon?'));
    }
    if (open.isNotEmpty) {
      final next = open.first;
      return GoalNext(
          rateText == null
              ? tr('Als Nächstes: {x}.', {'x': next.name})
              : tr('Die {x} im Monat laufen ab jetzt in {y}.', {'x': rateText, 'y': next.name}),
          tr('{x} ist geschafft. Wie schnell schaffe ich jetzt {y}, wenn ich die Rate dorthin lege?',
              {'x': reached.name, 'y': next.name}));
    }
    return GoalNext(tr('Was kommt als Nächstes? Ahead plant es mit dir.'),
        tr('{x} ist geschafft. Was wäre ein gutes nächstes Sparziel für mich?', {'x': reached.name}));
  }
}

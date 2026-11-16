// The first two minutes as a conversation: Buddy asks three things with
// answers to tap (life stage, payday, first savings goal), keeps what is
// useful later, and ends with the first goal as a card to confirm. Runs on
// the device, without AI, and can be skipped at any point.
import 'dart:async';

import 'package:hive/hive.dart';

import '../l10n/l10n.dart';
import '../utils/money.dart';
import 'buddy_entries.dart';
import 'buddy_memory.dart';
import 'buddy_wizard.dart';
import 'life_stages.dart';

class OnboardTurn {
  final String text;
  final List<String> chips;
  final BuddyEntry? goal;
  final bool done;
  const OnboardTurn(this.text, {this.chips = const [], this.goal, this.done = false});
}

class BuddyOnboarding {
  static const _key = 'buddyOnboarding';
  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static Map<String, dynamic> get _state =>
      ((_box?.get(_key) as Map?) ?? const {}).map((k, v) => MapEntry('$k', v));
  static Future<void> _save(Map<String, dynamic> s) async => _box?.put(_key, s);

  static String? get step => _state['step'] as String?;
  static bool get active => step != null && step != 'done';

  // a new account that has not told Buddy anything yet
  static bool shouldStart() =>
      step == null && LifeStages.current == null && BuddyMemory.all().isEmpty;

  static String get skipChip => tr('Später');

  static Future<OnboardTurn> start() async {
    unawaited(_save({'step': 'stage'}));
    return OnboardTurn(
      tr('Schön, dass du da bist. Drei kurze Fragen, dann kann ich dir wirklich helfen. **Was passt gerade zu dir?**'),
      chips: [for (final s in LifeStages.all) s.name, tr('Nichts davon')],
    );
  }

  static Future<void> skip() async => _save({..._state, 'step': 'done'});

  static OnboardTurn _payday() => OnboardTurn(
        tr('**Wann kommt dein Gehalt?** Dann sage ich dir zum richtigen Zeitpunkt, was frei ist.'),
        chips: [tr('Am Monatsanfang'), tr('Um den 15.'), tr('Am Monatsende'), tr('Unterschiedlich')],
      );

  static OnboardTurn _goal() => OnboardTurn(
        tr('**Wofür willst du als Erstes sparen?**'),
        chips: [tr('Notgroschen'), tr('Urlaub'), tr('Umzug'), tr('Etwas anderes')],
      );

  // a real question instead of an answer: the setup steps aside
  static bool _isQuestion(String t) =>
      t.endsWith('?') && t.split(RegExp(r'\s+')).length > 3 || t.split(RegExp(r'\s+')).length > 10;

  // the next turn for what the person answered; null when it was not an
  // answer but a question of its own (the setup ends, the question goes on)
  static Future<OnboardTurn?> answer(String text) async {
    final s = {..._state};
    final t = text.trim();
    if (_isQuestion(t)) {
      unawaited(skip());
      return null;
    }
    if (t.toLowerCase() == skipChip.toLowerCase()) {
      unawaited(skip());
      return OnboardTurn(tr('Klar, jederzeit. Frag mich einfach, was dir gerade auf dem Herzen liegt.'), done: true);
    }
    switch (s['step']) {
      case 'stage':
        final stage = LifeStages.all.where((x) => x.name.toLowerCase() == t.toLowerCase()).firstOrNull ??
            LifeStages.all.where((x) => t.toLowerCase().contains(x.name.toLowerCase())).firstOrNull;
        if (stage != null) unawaited(LifeStages.choose(stage));
        s['step'] = 'payday';
        unawaited(_save(s));
        final intro = stage == null
            ? tr('Alles klar.')
            : tr('**{x}**, gut zu wissen. Ich hab dir die wichtigsten Schritte dafür bereitgelegt.', {'x': stage.name});
        final next = _payday();
        return OnboardTurn('$intro\n\n${next.text}', chips: next.chips);
      case 'payday':
        final day = _payday_(t);
        if (day != null) {
          unawaited(BuddyMemory.add(day == 0
              ? tr('Gehalt kommt an unterschiedlichen Tagen.')
              : tr('Gehalt kommt um den {d}. des Monats.', {'d': day})));
        }
        s['step'] = 'goal';
        unawaited(_save(s));
        final next = _goal();
        return OnboardTurn('${tr('Notiert.')}\n\n${next.text}', chips: next.chips);
      case 'goal':
        if (t.toLowerCase() == tr('Etwas anderes').toLowerCase()) {
          s['step'] = 'goalName';
          unawaited(_save(s));
          return OnboardTurn(tr('Wofür denn? Ein Wort reicht, zum Beispiel Auto oder Laptop.'));
        }
        s['goal'] = t;
        s['step'] = 'amount';
        unawaited(_save(s));
        return _amountTurn(t);
      case 'goalName':
        s['goal'] = t;
        s['step'] = 'amount';
        unawaited(_save(s));
        return _amountTurn(t);
      case 'amount':
        final cents = Money.parseToCents(t.replaceAll(RegExp(r'[^0-9,.]'), ''));
        if (cents == null || cents <= 0) {
          return OnboardTurn(tr('Wie viel ungefähr? Eine Zahl reicht, zum Beispiel 1.500.'), chips: _amounts('${s['goal']}'));
        }
        final name = '${s['goal']}';
        s['step'] = 'done';
        unawaited(_save(s));
        return OnboardTurn(
          tr('Perfekt. Hier ist dein erstes Ziel. Tipp auf **Übernehmen**, dann rechne ich dir die Monatsrate aus.\n\n'
              'Nächster Schritt: Verbinde dein Konto, damit ich mit deinen echten Zahlen rechne.'),
          goal: BuddyEntry(
              type: 'goal', date: DateTime.now(), note: name, cents: cents, emoji: BuddyWizard.emojiFor(name)),
          chips: [tr('Wie viel ist diesen Monat noch frei?'), tr('Was kannst du alles?')],
          done: true,
        );
    }
    unawaited(skip());
    return const OnboardTurn('', done: true);
  }

  static OnboardTurn _amountTurn(String goal) => OnboardTurn(
        tr('**Wie viel brauchst du für {x}?**', {'x': goal}),
        chips: _amounts(goal),
      );

  static List<String> _amounts(String goal) {
    final g = goal.toLowerCase();
    final list = g.contains('notgroschen') || g.contains('emergency')
        ? [1500, 3000, 5000]
        : g.contains('urlaub') || g.contains('holiday')
            ? [500, 1000, 2000]
            : [1000, 2000, 5000];
    return [for (final v in list) Money.format(v * 100)];
  }

  // 1, 15, 28 or 0 for "different days"; null when unclear
  static int? _payday_(String t) {
    final l = t.toLowerCase();
    if (l == tr('Am Monatsanfang').toLowerCase()) return 1;
    if (l == tr('Um den 15.').toLowerCase()) return 15;
    if (l == tr('Am Monatsende').toLowerCase()) return 28;
    if (l == tr('Unterschiedlich').toLowerCase()) return 0;
    final m = RegExp(r'\b([1-9]|[12]\d|3[01])\b').firstMatch(l);
    return m == null ? null : int.parse(m.group(1)!);
  }
}

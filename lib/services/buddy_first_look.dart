// Buddy's first look: once there is enough money data (a bank link, an
// import, the example data), he says the three things that stand out, with
// a next step. Computed here from the same tools the agent uses, so it works
// without AI and every number is exact. It is the "he gets me" moment.
import '../l10n/l10n.dart';
import '../utils/money.dart';
import 'buddy_tools.dart';
import 'contracts.dart';

class FirstLook {
  final List<String> points;
  final String step;
  final List<String> followUps;
  const FirstLook(this.points, this.step, this.followUps);

  String get text {
    final b = StringBuffer(tr('Ich hab mir deine Zahlen angeschaut. Das fällt mir auf:'))..write('\n\n');
    for (var i = 0; i < points.length; i++) {
      b.writeln('${i + 1}. ${points[i]}');
    }
    b
      ..write('\n')
      ..write(L10n.isDe ? 'Nächster Schritt: ' : 'Next step: ')
      ..write(step);
    return b.toString();
  }
}

class BuddyFirstLook {
  // enough to say something real: at least 20 bookings over 30 days
  static bool ready(BuddyTools t) {
    if (t.tx.length < 20) return false;
    final first = t.tx.map((x) => x.date).reduce((a, b) => a.isBefore(b) ? a : b);
    return t.today.difference(first).inDays >= 30;
  }

  static FirstLook? build(BuddyTools t) {
    if (!ready(t)) return null;
    // candidates, most telling first; each with the step it leads to
    final found = <({String point, String step, String ask})>[];

    // a contract that got more expensive
    for (final c in Contracts.detect(t.tx, now: t.today)) {
      if (c.priceChange <= 0 || t.today.difference(c.last.date).inDays > 62) continue;
      found.add((
        point: tr('**{name}** ist um {x} teurer geworden. Aufs Jahr sind das {y} mehr.',
            {'name': c.name, 'x': Money.format(c.priceChange), 'y': Money.format(c.priceChange * 12)}),
        step: tr('Prüf, ob du {name} noch brauchst. Ich schreib dir die Kündigung, wenn nicht.', {'name': c.name}),
        ask: tr('Lohnt sich {name} noch für mich?', {'name': c.name}),
      ));
      break;
    }

    // last full month: the category furthest above its usual
    final lastMonth = DateTime(t.today.year, t.today.month - 1);
    String d(DateTime x) => x.toIso8601String().substring(0, 10);
    final last = t.run('ausgaben', {'von': d(lastMonth), 'bis': d(DateTime(lastMonth.year, lastMonth.month + 1, 0))});
    final before = t.run('ausgaben', {
      'von': d(DateTime(lastMonth.year, lastMonth.month - 3)),
      'bis': d(DateTime(lastMonth.year, lastMonth.month, 0)),
    });
    if (last['nachKategorie'] is List && before['nachKategorie'] is List) {
      final usual = {for (final c in before['nachKategorie'] as List) c['name']: (c['summe'] as num) / 3};
      Map? spike;
      var spikeRatio = 1.3;
      for (final c in last['nachKategorie'] as List) {
        final u = usual[c['name']];
        final now = c['summe'] as num;
        if (u == null || u < 30 || now - u < 25) continue;
        if (now / u > spikeRatio) {
          spikeRatio = now / u;
          spike = c as Map;
        }
      }
      if (spike != null) {
        final u = usual[spike['name']]!;
        found.add((
          point: tr('**{cat}** lag letzten Monat bei {x}, sonst sind es etwa {y}.', {
            'cat': spike['name'],
            'x': Money.format(((spike['summe'] as num) * 100).round()),
            'y': Money.format((u * 100).round()),
          }),
          step: tr('Setz dir für {cat} ein Monatsbudget. Ich schlag dir eins vor.', {'cat': spike['name']}),
          ask: tr('Wie bekomme ich {cat} wieder runter?', {'cat': spike['name']}),
        ));
      }
    }

    // savings rate of the last three full months
    final months = (t.run('monatsverlauf', {'monate': 4})['monate'] as List).take(3).toList();
    final income = months.fold<num>(0, (s, m) => s + (m['einnahmen'] as num));
    final saved = months.fold<num>(0, (s, m) => s + (m['gespart'] as num));
    if (income > 0) {
      final rate = (saved * 100 / income).round();
      found.add((
        point: rate >= 10
            ? tr('Du legst im Schnitt **{r} %** deines Einkommens zurück. Das ist richtig gut.', {'r': rate})
            : rate >= 0
                ? tr('Von deinem Einkommen bleiben im Schnitt nur **{r} %** übrig.', {'r': rate})
                : tr('In den letzten drei Monaten ging mehr raus als rein, im Schnitt {x} im Monat.',
                    {'x': Money.format((-saved * 100 / 3).round())}),
        step: rate >= 10
            ? tr('Richte einen Dauerauftrag direkt nach dem Gehalt ein, damit es so bleibt.')
            : tr('Fang mit 5 % vom Gehalt an, per Dauerauftrag am Zahltag.'),
        ask: tr('Wie viel sollte ich jeden Monat sparen?'),
      ));
    }

    // contracts and subscriptions together
    final contracts = t.run('vertraege_und_abos', {});
    final perMonth = contracts['summeProMonat'] as num? ?? 0;
    if (perMonth > 0) {
      final list = (contracts['vertraegeUndAbos'] as List?) ?? const [];
      found.add((
        point: tr('Für {n} Verträge und Abos gehen jeden Monat **{x}** raus.',
            {'n': list.length, 'x': Money.format((perMonth * 100).round())}),
        step: tr('Geh einmal deine Abos durch. Jedes, das du nicht nutzt, ist Geld fürs nächste Ziel.'),
        ask: tr('Welche Abos könnte ich kündigen?'),
      ));
    }

    // what is free until the end of the month
    final forecast = t.run('monatsprognose', {})['prognose'];
    if (forecast is Map && forecast['vorhanden'] == true) {
      final free = forecast['freiBisMonatsende'] as num;
      found.add((
        point: free >= 0
            ? tr('Bis Monatsende sind noch **{x}** frei, etwa {y} am Tag.', {
                'x': Money.format((free * 100).round()),
                'y': Money.format(((forecast['proTag'] as num) * 100).round()),
              })
            : tr('Bis Monatsende fehlen nach den festen Kosten etwa **{x}**.', {'x': Money.format((-free * 100).round())}),
        step: free >= 0
            ? tr('Behalte die {y} am Tag im Blick. Ich sag dir Bescheid, wenn es knapp wird.',
                {'y': Money.format(((forecast['proTag'] as num) * 100).round())})
            : tr('Lass uns schauen, was bis Monatsende warten kann.'),
        ask: tr('Wie komme ich gut bis Monatsende?'),
      ));
    }

    if (found.isEmpty) return null;
    final top = found.take(3).toList();
    return FirstLook([for (final f in top) f.point], top.first.step, [for (final f in top.skip(1)) f.ask]);
  }
}

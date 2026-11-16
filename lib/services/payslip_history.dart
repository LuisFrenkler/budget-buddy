// Payslips over the months: each checked one is kept on the device (the
// numbers only, no photo), and the next one is compared with it. What
// changed without anyone saying so is what people miss: a new tax class
// after a wedding, a higher health insurance rate, the company pension
// starting, church tax appearing, or less net with the same gross.
import 'package:hive/hive.dart';

import '../l10n/l10n.dart';
import '../utils/money.dart';
import 'buddy_proposals.dart';
import 'payslip_check.dart';

class PayslipHistory {
  static const _key = 'payslips';
  static const keep = 12;
  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static Map<String, dynamic> _toJson(Payslip p) => {
        if (p.brutto != null) 'brutto': p.brutto,
        if (p.netto != null) 'netto': p.netto,
        if (p.auszahlung != null) 'auszahlung': p.auszahlung,
        if (p.lohnsteuer != null) 'lohnsteuer': p.lohnsteuer,
        if (p.kv != null) 'kv': p.kv,
        if (p.zusatz != null) 'zusatzbeitragProzent': p.zusatz,
        if (p.bav != null) 'bav': p.bav,
        if (p.vl != null) 'vl': p.vl,
        if (p.kirchensteuer != null) 'kirchensteuer': p.kirchensteuer,
        if (p.steuerklasse != null) 'steuerklasse': p.steuerklasse,
        if (p.kirche != null) 'kirche': p.kirche,
        if (p.monat != null) 'monat': p.monat,
      };

  static List<Payslip> all() => [
        for (final m in ((_box?.get(_key) as List?) ?? const []).whereType<Map>())
          Payslip.fromJson(m.map((k, v) => MapEntry('$k', v)))
      ];

  // the latest stays last; the same month replaces the earlier upload
  static Future<void> add(Payslip p) async {
    final list = [for (final x in all()) if (p.monat == null || x.monat != p.monat) x, p];
    final cut = list.length > keep ? list.sublist(list.length - keep) : list;
    await _box?.put(_key, [for (final x in cut) _toJson(x)]);
  }

  static Future<void> clear() async => _box?.delete(_key);

  static String _eur(double v) => Money.format((v * 100).round());

  // what changed from [before] to [now], each as one plain sentence
  static List<String> changes(Payslip before, Payslip now) {
    final out = <String>[];
    if (before.steuerklasse != null && now.steuerklasse != null && before.steuerklasse != now.steuerklasse) {
      out.add(tr('Steuerklasse von {a} auf {b} geändert. War das gewollt, etwa nach einer Heirat?',
          {'a': before.steuerklasse, 'b': now.steuerklasse}));
    }
    if (before.kirche == false && now.kirche == true || (before.kirchensteuer ?? 0) == 0 && (now.kirchensteuer ?? 0) > 0) {
      out.add(tr('Neu ist Kirchensteuer: {x}. Stimmt die Religionszugehörigkeit beim Arbeitgeber?',
          {'x': _eur(now.kirchensteuer ?? 0)}));
    }
    if (before.zusatz != null && now.zusatz != null && (now.zusatz! - before.zusatz!).abs() >= 0.05) {
      out.add(tr('Zusatzbeitrag der Krankenkasse von {a} % auf {b} %. Ein Wechsel kann sich lohnen, wenn er gestiegen ist.',
          {'a': before.zusatz!.toStringAsFixed(2).replaceAll('.', ','), 'b': now.zusatz!.toStringAsFixed(2).replaceAll('.', ',')}));
    }
    if ((before.bav ?? 0) == 0 && (now.bav ?? 0) > 0) {
      out.add(tr('Neu: Betriebsrente mit {x} im Monat aus dem Brutto.', {'x': _eur(now.bav!)}));
    } else if ((before.bav ?? 0) > 0 && (now.bav ?? 0) == 0) {
      out.add(tr('Die Betriebsrente fehlt diesen Monat. Absichtlich beendet?'));
    }
    if ((before.vl ?? 0) == 0 && (now.vl ?? 0) > 0) {
      out.add(tr('Neu: vermögenswirksame Leistungen, {x}.', {'x': _eur(now.vl!)}));
    }
    final bb = before.brutto, nb = now.brutto;
    if (bb != null && nb != null && bb > 0) {
      final diff = nb - bb;
      if (diff.abs() >= bb * 0.01) {
        out.add(diff > 0
            ? tr('Brutto {x} mehr als in der letzten Abrechnung.', {'x': _eur(diff)})
            : tr('Brutto {x} weniger als in der letzten Abrechnung. Krank, unbezahlter Urlaub oder ein Fehler?',
                {'x': _eur(-diff)}));
      } else {
        // the same gross, clearly less paid out: something was deducted
        final bn = before.auszahlung ?? before.netto, nn = now.auszahlung ?? now.netto;
        if (bn != null && nn != null && bn - nn >= 20) {
          out.add(tr('Gleiches Brutto, aber {x} weniger ausgezahlt. Frag nach, welcher Abzug neu ist.', {'x': _eur(bn - nn)}));
        }
      }
    }
    return out;
  }

  // the section under the check, when there is an earlier payslip
  static String? compareText(Payslip now) {
    final earlier = all().where((p) => p.monat == null || p.monat != now.monat).toList();
    if (earlier.isEmpty) return null;
    final c = changes(earlier.last, now);
    if (c.isEmpty) return tr('**Im Vergleich zur letzten Abrechnung:** nichts Auffälliges geändert.');
    return '${tr('**Im Vergleich zur letzten Abrechnung:**')}\n${[for (final x in c) '- $x'].join('\n')}';
  }

  // brutto, netto and the gap (deductions) for each saved month
  static BuddyChart? chart() {
    final slips = [
      for (final p in all())
        if (p.brutto != null && p.brutto! > 0 && (p.netto ?? p.auszahlung) != null) p
    ];
    if (slips.length < 2) return null;
    slips.sort((a, b) => _order(a).compareTo(_order(b)));
    final shown = slips.length > keep ? slips.sublist(slips.length - keep) : slips;
    final years = {
      for (final p in shown)
        if (RegExp(r'^(\d{4})').firstMatch(p.monat ?? '')?.group(1) case final y?) y
    };
    return BuddyChart(ChartKind.payslip, tr('Brutto, Netto, Abzüge'), [
      for (final p in shown)
        (
          label: _monthLabel(p.monat, withYear: years.length > 1),
          a: (p.brutto! * 100).round(),
          b: ((p.netto ?? p.auszahlung)! * 100).round(),
        )
    ]);
  }

  static const _names = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

  static int _order(Payslip p) {
    final m = RegExp(r'(\d{4})-(\d{1,2})').firstMatch(p.monat ?? '');
    if (m == null) return 1 << 30;
    return int.parse(m.group(1)!) * 100 + int.parse(m.group(2)!);
  }

  static String _monthLabel(String? monat, {required bool withYear}) {
    final m = RegExp(r'(\d{4})-(\d{1,2})').firstMatch(monat ?? '');
    if (m == null) return (monat == null || monat.isEmpty) ? '–' : monat;
    final month = int.tryParse(m.group(2)!);
    if (month == null || month < 1 || month > 12) return monat!;
    final name = tr(_names[month - 1]);
    return withYear ? '$name ${m.group(1)!.substring(2)}' : name;
  }
}

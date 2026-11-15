// Buddy checks a payslip: the AI only reads the numbers off the photo, the
// app then recomputes every line with the 2026 rules (NetSalary) and says
// what fits, what looks off and what it means in euros.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import '../utils/money.dart';
import 'backend_service.dart';
import 'net_salary.dart';

class Payslip {
  final double? brutto, netto, auszahlung, lohnsteuer, soli, kirchensteuer, rv, av, kv, pv, zusatz, bav, vl, kids;
  final int? steuerklasse;
  final bool? kirche;
  final String? monat;
  const Payslip({
    this.brutto,
    this.netto,
    this.auszahlung,
    this.lohnsteuer,
    this.soli,
    this.kirchensteuer,
    this.rv,
    this.av,
    this.kv,
    this.pv,
    this.zusatz,
    this.bav,
    this.vl,
    this.kids,
    this.steuerklasse,
    this.kirche,
    this.monat,
  });

  factory Payslip.fromJson(Map<String, dynamic> j) {
    double? n(String k) => (j[k] as num?)?.toDouble();
    return Payslip(
      brutto: n('brutto'),
      netto: n('netto'),
      auszahlung: n('auszahlung'),
      lohnsteuer: n('lohnsteuer'),
      soli: n('soli'),
      kirchensteuer: n('kirchensteuer'),
      rv: n('rv'),
      av: n('av'),
      kv: n('kv'),
      pv: n('pv'),
      zusatz: n('zusatzbeitragProzent'),
      bav: n('bav'),
      vl: n('vl'),
      kids: n('kinderfreibetraege'),
      steuerklasse: (j['steuerklasse'] as num?)?.toInt(),
      kirche: j['kirche'] as bool?,
      monat: j['monat'] as String?,
    );
  }
}

// one line of the check: ok, or worth a look
class PayslipLine {
  final String label;
  final bool ok;
  final String text;
  const PayslipLine(this.label, this.ok, this.text);
}

class PayslipCheck {
  // a message that comes with a payslip photo
  static final _words = RegExp(r'abrechnung|lohnzettel|gehaltszettel|lohnabrechnung|payslip|pay slip|payroll',
      caseSensitive: false);
  static bool looksLike(String text, {String? lastAnswer}) =>
      _words.hasMatch(text) || (text.trim().isEmpty && lastAnswer != null && _words.hasMatch(lastAnswer));

  static Future<Payslip> read(Uint8List bytes, String mediaType) async {
    final res = await http
        .post(Uri.parse('${BackendService.base}/ai/payslip'),
            headers: {'Content-Type': 'application/json', ...BackendService.authHeaders},
            body: jsonEncode({'image': base64Encode(bytes), 'mediaType': mediaType}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      String? error;
      try {
        error = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error'] as String?;
      } catch (_) {}
      throw error ?? tr('Die Abrechnung konnte ich gerade nicht lesen.');
    }
    final j = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['payslip'] as Map;
    if (j['istAbrechnung'] == false) throw tr('Das sieht nicht nach einer Gehaltsabrechnung aus.');
    return Payslip.fromJson(j.cast<String, dynamic>());
  }

  static String _eur(double v) => Money.format((v * 100).round());

  // the lines of the check
  static List<PayslipLine> lines(Payslip p) {
    final gross = p.brutto;
    if (gross == null || gross <= 0) return const [];
    final out = <PayslipLine>[];
    final cls = p.steuerklasse;
    // a company pension paid from the gross lowers tax and contributions: the
    // recomputation would not fit, so those lines are only shown
    final converted = (p.bav ?? 0) > 0;
    final childless = (p.kids ?? 0) == 0;
    final zusatz = p.zusatz ?? (p.kv != null ? ((p.kv! / gross) - NetSalary.kvGeneral) * 200 : NetSalary.averageAdditional);
    final model = NetSalary.compute(gross,
        taxClass: cls != null && cls >= 1 && cls <= 4 ? cls : 1,
        church: p.kirche ?? ((p.kirchensteuer ?? 0) > 0),
        children: (p.kids ?? 0).ceil(),
        additional: zusatz.clamp(0, 5).toDouble());

    if (cls == null) {
      out.add(PayslipLine(tr('Steuerklasse'), false, tr('Steht nicht auf dem Foto. Ledig ist Klasse I.')));
    } else if (cls == 6) {
      out.add(PayslipLine(tr('Steuerklasse'), false,
          tr('Klasse VI ist für einen Zweitjob. Ist das dein einziger Job, frag die Personalabteilung.')));
    } else {
      out.add(PayslipLine(tr('Steuerklasse'), true, tr('Klasse {x}.', {'x': cls})));
    }

    bool near(double? have, double want, {double tol = 1.0}) => have != null && (have - want).abs() <= tol;

    if (p.rv != null) {
      out.add(converted || near(p.rv, model.pension)
          ? PayslipLine(tr('Rentenversicherung'), true, tr('{x}, das sind 9,3 % vom Brutto.', {'x': _eur(p.rv!)}))
          : PayslipLine(tr('Rentenversicherung'), false,
              tr('{x}, erwartet wären etwa {y}.', {'x': _eur(p.rv!), 'y': _eur(model.pension)})));
    }
    if (p.av != null) {
      out.add(converted || near(p.av, model.unemployment)
          ? PayslipLine(tr('Arbeitslosenversicherung'), true, tr('{x}, passt.', {'x': _eur(p.av!)}))
          : PayslipLine(tr('Arbeitslosenversicherung'), false,
              tr('{x}, erwartet wären etwa {y}.', {'x': _eur(p.av!), 'y': _eur(model.unemployment)})));
    }
    if (p.kv != null) {
      final z = zusatz;
      final yearly = (z - NetSalary.averageAdditional) / 200 * gross * 12;
      out.add(PayslipLine(
          tr('Krankenversicherung'),
          true,
          z > NetSalary.averageAdditional + 0.25 && !converted
              ? tr('{x}. Deine Kasse nimmt etwa {z} % Zusatzbeitrag, der Schnitt sind 2,9 %. Ein Wechsel spart dir rund {y} im Jahr.',
                  {'x': _eur(p.kv!), 'z': z.toStringAsFixed(1).replaceAll('.', L10n.isDe ? ',' : '.'), 'y': _eur(yearly)})
              : tr('{x}, passt zu einem üblichen Zusatzbeitrag.', {'x': _eur(p.kv!)})));
    }
    if (p.pv != null) {
      final withSurcharge = gross * (childless ? 0.024 : 0.018);
      out.add(converted || near(p.pv, model.care) || near(p.pv, withSurcharge)
          ? PayslipLine(tr('Pflegeversicherung'), true,
              childless && near(p.pv, gross * 0.024)
                  ? tr('{x}, mit 0,6 % Zuschlag für Kinderlose ab 23.', {'x': _eur(p.pv!)})
                  : tr('{x}, passt.', {'x': _eur(p.pv!)}))
          : PayslipLine(tr('Pflegeversicherung'), false,
              tr('{x}, erwartet wären etwa {y}. Bei Kindern gibt es Abschläge, die müssen der Kasse bekannt sein.',
                  {'x': _eur(p.pv!), 'y': _eur(model.care)})));
    }
    if (p.lohnsteuer != null && cls != null && cls <= 4) {
      final tol = (model.wageTax * 0.03).clamp(5, 40).toDouble();
      out.add(converted || near(p.lohnsteuer, model.wageTax, tol: tol)
          ? PayslipLine(tr('Lohnsteuer'), true, tr('{x}, passt zu Klasse {c}.', {'x': _eur(p.lohnsteuer!), 'c': cls}))
          : PayslipLine(
              tr('Lohnsteuer'),
              false,
              p.lohnsteuer! > model.wageTax
                  ? tr('{x}, erwartet wären etwa {y}. Zu viel Lohnsteuer kommt mit der Steuererklärung zurück, prüf aber Steuerklasse und Freibeträge.',
                      {'x': _eur(p.lohnsteuer!), 'y': _eur(model.wageTax)})
                  : tr('{x}, erwartet wären etwa {y}. Vielleicht ist ein Freibetrag eingetragen.',
                      {'x': _eur(p.lohnsteuer!), 'y': _eur(model.wageTax)})));
    }
    if ((p.kirchensteuer ?? 0) > 0) {
      out.add(PayslipLine(tr('Kirchensteuer'), true,
          tr('{x}. Wer nicht Mitglied einer Kirche ist, sollte hier 0 haben.', {'x': _eur(p.kirchensteuer!)})));
    }
    if (p.netto != null) {
      final deductions = [p.lohnsteuer, p.soli, p.kirchensteuer, p.rv, p.av, p.kv, p.pv].fold<double>(0, (s, v) => s + (v ?? 0));
      final sum = gross - deductions - (p.bav ?? 0);
      out.add(near(p.netto, sum, tol: 2) || converted
          ? PayslipLine(tr('Netto'), true, tr('{x}, die Rechnung geht auf.', {'x': _eur(p.netto!)}))
          : PayslipLine(tr('Netto'), false,
              tr('{x}, aus Brutto minus Abzügen ergeben sich {y}. Vielleicht gibt es weitere Posten.',
                  {'x': _eur(p.netto!), 'y': _eur(sum)})));
    }
    if (converted) {
      out.add(PayslipLine(tr('Betriebsrente'), true,
          tr('{x} gehen in die Betriebsrente. Das senkt Steuer und Abgaben, darum rechne ich die Zeilen hier nicht nach.',
              {'x': _eur(p.bav!)})));
    }
    if ((p.vl ?? 0) > 0) {
      out.add(PayslipLine(tr('Vermögenswirksame Leistungen'), true,
          tr('{x} im Monat. Prüf, ob sie wirklich in einen Sparvertrag fließen.', {'x': _eur(p.vl!)})));
    }
    return out;
  }

  // the answer in the chat
  static String answer(Payslip p) {
    final all = lines(p);
    if (all.isEmpty) return tr('Auf dem Foto finde ich kein Brutto. Probier ein schärferes Foto der ganzen Seite.');
    final off = all.where((l) => !l.ok).toList();
    final head = off.isEmpty
        ? tr('**Deine Abrechnung sieht stimmig aus.** Brutto {b}, ausgezahlt {n}.',
            {'b': _eur(p.brutto!), 'n': _eur(p.auszahlung ?? p.netto ?? 0)})
        : tr('**{n} Punkte solltest du dir ansehen.** Brutto {b}, ausgezahlt {a}.',
            {'n': off.length, 'b': _eur(p.brutto!), 'a': _eur(p.auszahlung ?? p.netto ?? 0)});
    final body = [for (final l in all) '- ${l.ok ? '✓' : '⚠︎'} **${l.label}:** ${l.text}'].join('\n');
    final next = off.isEmpty
        ? tr('Nächster Schritt: Leg die Abrechnung digital ab, die brauchst du für die Steuererklärung.')
        : tr('Nächster Schritt: Frag die Personalabteilung nach {x}.', {'x': off.first.label});
    return '$head\n\n$body\n\n${tr('Nachgerechnet mit den Regeln für 2026. Kleine Abweichungen sind normal.')}\n\n$next';
  }
}

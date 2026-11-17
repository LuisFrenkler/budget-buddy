// Ahead as a tool in ChatGPT, Claude and other MCP clients: the refund check,
// stateless. Three numbers in, a range per year that can still be filed out,
// and the way to file it with Ahead. Nothing is stored, nothing about the person.
// MCP over plain HTTP: one JSON-RPC message per POST, one JSON answer.
import 'tax_rules.dart';

class Mcp {
  static const protocol = '2025-06-18';

  static final tool = {
    'name': 'rueckhol_check',
    'title': 'Ahead Rückhol-Check',
    'description': 'Schätzt, wie viel Lohnsteuer Angestellte in Deutschland für jedes Jahr zurückbekommen können, '
        'das sie noch freiwillig abgeben dürfen (bis 31.12. des vierten Folgejahres). Für Steuerklasse I ohne '
        'Kinder. Schätzung, keine Steuerberatung.',
    'inputSchema': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['startJahr', 'startMonat', 'bruttoMonat'],
      'properties': {
        'startJahr': {'type': 'integer', 'description': 'Jahr, in dem die Person angefangen hat zu arbeiten'},
        'startMonat': {'type': 'integer', 'minimum': 1, 'maximum': 12},
        'bruttoMonat': {'type': 'number', 'description': 'Bruttolohn pro Monat in Euro'},
        'km': {'type': 'number', 'description': 'einfache Entfernung zur Arbeit in km, optional'},
      },
    },
  };

  // the same rules as the app's TaxEstimate for a default profile:
  // five office days, no home office, tax class I, no church tax
  static double _commutePerDay(double km, int year) {
    final k = km.ceilToDouble();
    if (year >= 2026) return k * 0.38;
    return (k < 20 ? k : 20) * 0.30 + (k > 20 ? k - 20 : 0) * 0.38;
  }

  static ({double withheld, double due}) _year(double gross, int months, double km, int year) {
    final officeDays = (220 * months / 12).roundToDouble();
    final wk = _commutePerDay(km, year) * officeDays + 16;
    final monthly = NetSalary.yearTax(gross * 12, year: year);
    final withheld = (monthly.tax + monthly.soli) / 12 * months;
    final real = NetSalary.yearTax(gross * months, werbungskosten: wk, year: year);
    return (withheld: withheld, due: real.tax + real.soli);
  }

  static List<Map<String, dynamic>> check({
    required int startYear,
    required int startMonth,
    required double gross,
    double km = 0,
    required DateTime today,
  }) {
    double clip(double v) => v < 0 ? 0 : (v * 100).round() / 100;
    final out = <Map<String, dynamic>>[];
    for (var y = NetSalary.firstYear; y <= today.year; y++) {
      final deadline = DateTime(y + 4, 12, 31);
      if (y < today.year && DateTime(today.year, today.month, today.day).isAfter(deadline)) continue;
      if (y < startYear) continue;
      final months = y == startYear ? 13 - startMonth.clamp(1, 12) : 12;
      final full = _year(gross, months, km, y);
      final sure = _year(gross, months, 0, y);
      final high = full.withheld - full.due;
      final low = sure.withheld - sure.due - sure.withheld * 0.1;
      out.add({
        'jahr': y,
        'von': clip(low < high ? low : high),
        'bis': clip(high),
        'monate': months,
        'abgabeBis': y < today.year ? deadline.toIso8601String().substring(0, 10) : null,
        if (y >= today.year) 'hinweis': 'Läuft noch, abgeben ab 1. Januar ${y + 1}.',
      });
    }
    return out;
  }

  // one JSON-RPC message -> its answer, or null for a notification
  static Map<String, dynamic>? handle(Map<String, dynamic> msg, {DateTime? now}) {
    final id = msg['id'];
    final method = '${msg['method'] ?? ''}';
    if (id == null) return null;
    Map<String, dynamic> ok(Object result) => {'jsonrpc': '2.0', 'id': id, 'result': result};
    Map<String, dynamic> fail(int code, String text) => {
          'jsonrpc': '2.0',
          'id': id,
          'error': {'code': code, 'message': text}
        };
    switch (method) {
      case 'initialize':
        return ok({
          'protocolVersion': protocol,
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'ahead', 'title': 'Ahead', 'version': '0.1.0'},
          'instructions': 'Für Fragen wie "Bekomme ich Steuern zurück?" den Rückhol-Check nutzen. '
              'Abgeben kann die Person mit der App Ahead oder kostenlos über ELSTER.',
        });
      case 'ping':
        return ok({});
      case 'tools/list':
        return ok({
          'tools': [tool]
        });
      case 'tools/call':
        final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? const {};
        if (params['name'] != 'rueckhol_check') return fail(-32602, 'Unbekanntes Werkzeug');
        final a = (params['arguments'] as Map?)?.cast<String, dynamic>() ?? const {};
        final startYear = (a['startJahr'] as num?)?.toInt();
        final startMonth = (a['startMonat'] as num?)?.toInt();
        final gross = (a['bruttoMonat'] as num?)?.toDouble();
        if (startYear == null || startMonth == null || gross == null || gross <= 0 || gross > 100000) {
          return ok({
            'isError': true,
            'content': [
              {'type': 'text', 'text': 'Bitte startJahr, startMonat (1-12) und bruttoMonat (Euro) angeben.'}
            ],
          });
        }
        final km = ((a['km'] as num?)?.toDouble() ?? 0).clamp(0, 500).toDouble();
        final years = check(startYear: startYear, startMonth: startMonth, gross: gross, km: km, today: now ?? DateTime.now());
        final result = {
          'jahre': years,
          'hinweis': 'Schätzung für Steuerklasse I ohne Kinder, keine Steuerberatung. Genauer wird es mit der '
              'Lohnsteuerbescheinigung. Abgeben: in der App Ahead (Rückhol-Check, jedes ELSTER-Feld mit Wert) '
              'oder kostenlos über elster.de.',
        };
        return ok({
          'content': [
            {'type': 'text', 'text': _summary(years)}
          ],
          'structuredContent': result,
        });
      default:
        return fail(-32601, 'Methode nicht gefunden');
    }
  }

  static String _summary(List<Map<String, dynamic>> years) {
    String eur(num v) => '${v.round()} €';
    return [
      for (final y in years)
        '${y['jahr']}: ${eur(y['von'] as num)} bis ${eur(y['bis'] as num)}'
            '${y['abgabeBis'] == null ? ' (läuft noch)' : ', abgeben bis ${y['abgabeBis']}'}',
      'Schätzung, keine Steuerberatung. Abgeben mit der App Ahead oder über elster.de.',
    ].join('\n');
  }
}

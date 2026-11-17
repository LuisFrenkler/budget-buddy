// A photo of a Lohnsteuerbescheinigung or a Steuerbescheid -> its numbers.
// The AI only reads; the app checks and stores, nothing about the person.
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../l10n/l10n.dart';
import 'backend_service.dart';
import 'tax_estimate.dart';

class TaxDoc {
  final String kind; // lohnsteuerbescheinigung, bescheid, anderes
  final int? year;
  final int? months; // months of the employment on the certificate
  final double? gross, wageTax, soli, churchTax;
  final double? refund, backPayment, werbungskosten;
  final DateTime? date;
  const TaxDoc({
    required this.kind,
    this.year,
    this.months,
    this.gross,
    this.wageTax,
    this.soli,
    this.churchTax,
    this.refund,
    this.backPayment,
    this.werbungskosten,
    this.date,
  });

  factory TaxDoc.fromJson(Map<String, dynamic> j) {
    double? n(String k) => (j[k] as num?)?.toDouble();
    return TaxDoc(
      kind: '${j['art'] ?? 'anderes'}',
      year: (j['jahr'] as num?)?.toInt(),
      months: (j['monate'] as num?)?.toInt(),
      gross: n('bruttoarbeitslohn'),
      wageTax: n('lohnsteuer'),
      soli: n('soli'),
      churchTax: n('kirchensteuer'),
      refund: n('erstattung'),
      backPayment: n('nachzahlung'),
      werbungskosten: n('werbungskostenAnerkannt'),
      date: DateTime.tryParse('${j['bescheidDatum'] ?? ''}'),
    );
  }

  bool get isCertificate => kind == 'lohnsteuerbescheinigung' && year != null && gross != null && wageTax != null;
  bool get isAssessment => kind == 'bescheid' && year != null && date != null && (refund != null || backPayment != null);

  // the certificate's year figures on top of what the person told us
  TaxProfile applyTo(TaxProfile p) {
    final m = (months ?? p.monthsWorked).clamp(1, 12);
    return p.copyWith(
      grossYear: gross,
      withheldYear: (wageTax ?? 0) + (soli ?? 0) + (churchTax ?? 0),
      monthsWorked: m,
      grossMonth: gross! / m,
      church: (churchTax ?? 0) > 0 ? true : null,
    );
  }

  Assessment toAssessment() =>
      Assessment(year: year!, refund: (refund ?? 0) - (backPayment ?? 0), werbungskosten: werbungskosten, date: date!);

  static Future<TaxDoc> read(Uint8List bytes, String mediaType) async {
    final res = await http
        .post(Uri.parse('${BackendService.base}/ai/taxdoc'),
            headers: {'Content-Type': 'application/json', ...BackendService.authHeaders},
            body: jsonEncode({'image': base64Encode(bytes), 'mediaType': mediaType}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      String? error;
      try {
        error = (jsonDecode(utf8.decode(res.bodyBytes)) as Map)['error'] as String?;
      } catch (_) {}
      throw error ?? tr('Das Dokument konnte ich gerade nicht lesen.');
    }
    return TaxDoc.fromJson(((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['doc'] as Map).cast<String, dynamic>());
  }
}

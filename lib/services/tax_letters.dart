// Ready-to-send texts around the tax return. The person sends them; Ahead
// only writes them. Formulierungshilfe, keine Steuerberatung.
// Letters to German offices stay German whatever the app language is.
class TaxLetters {
  static String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  static String _eur(double v) {
    final parts = v.abs().toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+$)'), (_) => '.');
    return '${v < 0 ? '-' : ''}$whole,${parts[1]} €';
  }

  // the certificate is gone: ask the old employer for a copy
  static String employerRequest({required int year, String name = '', DateTime? date}) => [
        _date(date ?? DateTime.now()),
        '',
        'Kopie meiner Lohnsteuerbescheinigung $year',
        '',
        'Guten Tag,',
        '',
        'für meine Einkommensteuererklärung $year bitte ich Sie um eine Kopie meiner '
            'Lohnsteuerbescheinigung $year, gern als PDF per E-Mail.',
        '',
        'Vielen Dank und freundliche Grüße',
        if (name.isNotEmpty) name,
      ].join('\n');

  // the office accepted less than was claimed: a draft objection to check and send
  static String objection({
    required int year,
    required DateTime noticeDate,
    required double claimed,
    required double accepted,
    String name = '',
    String taxNumber = '',
    DateTime? date,
  }) {
    return [
      _date(date ?? DateTime.now()),
      '',
      'Einspruch gegen den Einkommensteuerbescheid $year vom ${_date(noticeDate)}'
          '${taxNumber.isEmpty ? '' : ', Steuernummer $taxNumber'}',
      '',
      'Sehr geehrte Damen und Herren,',
      '',
      'hiermit lege ich Einspruch gegen den oben genannten Bescheid ein.',
      '',
      'Begründung: In meiner Erklärung habe ich Werbungskosten von ${_eur(claimed)} angegeben, '
          'berücksichtigt wurden ${_eur(accepted)}. Bitte berücksichtigen Sie die Werbungskosten wie erklärt. '
          'Belege reiche ich auf Anforderung gern nach.',
      '',
      'Mit freundlichen Grüßen',
      if (name.isNotEmpty) name,
    ].join('\n');
  }
}

// Who runs BudgetBuddy: the details the imprint, privacy policy and terms
// refer to. Fill in every value in [brackets] before publishing the app;
// debug builds show a reminder while any are left (see [LegalInfo.complete]).
class LegalInfo {
  static const appVersion = '1.0.0';

  static const provider = '[Vor- und Nachname bzw. Firma]';
  static const street = '[Straße und Hausnummer]';
  static const city = '[PLZ und Ort]';
  static const country = 'Deutschland';
  static const email = '[E-Mail-Adresse]';
  static const phone = ''; // optional
  static const vatId = ''; // USt-IdNr., only if there is one
  static const register = ''; // e.g. "Amtsgericht Musterstadt, HRB 12345", only for registered companies
  static const representative = ''; // managing director for a GmbH/UG

  // person responsible for content under § 18 Abs. 2 MStV
  static const responsible = '[Vor- und Nachname]';

  // supervisory authority for data protection complaints (the one of the provider's state)
  static const authority = '[Datenschutz-Aufsichtsbehörde des Bundeslandes]';

  static const updated = 'Oktober 2026';

  static String get address => '$street\n$city\n$country';

  static bool get complete =>
      ![provider, street, city, email, responsible, authority].any((v) => v.startsWith('['));
}

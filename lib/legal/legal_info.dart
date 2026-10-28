// Who runs BudgetBuddy: the details the imprint, privacy policy and terms
// refer to. Name and support mail are set; street, city and the state data-
// protection authority must still match the real business address before a
// store release (see [LegalInfo.complete]).
class LegalInfo {
  static const appVersion = '1.0.0';

  static const provider = 'Luis Frenkler';
  static const street = '[Straße und Hausnummer]';
  static const city = '[PLZ und Ort]';
  static const country = 'Deutschland';
  static const email = 'luis.frenkler@t-online.de';
  static const phone = ''; // optional
  static const vatId = ''; // USt-IdNr., only if there is one
  static const register = ''; // e.g. "Amtsgericht Musterstadt, HRB 12345", only for registered companies
  static const representative = ''; // managing director for a GmbH/UG

  // person responsible for content under § 18 Abs. 2 MStV
  static const responsible = 'Luis Frenkler';

  // supervisory authority for data protection complaints (the one of the provider's state)
  static const authority = '[Datenschutz-Aufsichtsbehörde des Bundeslandes]';

  static const updated = 'Oktober 2026';

  static String get address => '$street\n$city\n$country';

  // true only when every required imprint field is a real value, not a [bracket] stub
  static bool get complete =>
      ![provider, street, city, email, responsible, authority].any((v) => v.startsWith('['));

  // fields still waiting on a real postal address / Landesbehörde before publish
  static List<String> get missing => [
        if (street.startsWith('[')) 'Anschrift (Straße)',
        if (city.startsWith('[')) 'Anschrift (PLZ und Ort)',
        if (authority.startsWith('[')) 'Datenschutz-Aufsichtsbehörde',
      ];
}

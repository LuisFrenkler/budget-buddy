// A look at the insurances someone pays for, by type, with the general
// rules consumer advice centres give people starting out: liability first,
// disability cover when the income matters, the same cover twice is wasted,
// and a few kinds are rarely worth it at 20 to 30. No providers, no tariffs:
// Buddy asks the questions, the person decides.
class InsuranceFinding {
  final String name;
  final String type; // haftpflicht, hausrat, bu, ...
  const InsuranceFinding(this.name, this.type);
}

class InsuranceReport {
  final List<InsuranceFinding> found;
  final List<String> twice; // types paid more than once
  final List<String> rarelyNeeded; // types often not worth it when young
  final bool liabilityMissing;
  const InsuranceReport(this.found, this.twice, this.rarelyNeeded, this.liabilityMissing);
}

class InsuranceCheck {
  static final _types = <String, RegExp>{
    // the more specific ones first: a Kfz-Haftpflicht is no private liability
    'kfz': RegExp(r'kfz|autoversicherung|kasko', caseSensitive: false),
    'tier': RegExp(r'tierhalter|hundehaftpflicht|pferdehaftpflicht|tierkranken', caseSensitive: false),
    'haftpflicht': RegExp(r'haftpflicht|\bphv\b', caseSensitive: false),
    'hausrat': RegExp(r'hausrat', caseSensitive: false),
    'bu': RegExp(r'berufsunf[äa]hig|\bbu\b', caseSensitive: false),
    'rechtsschutz': RegExp(r'rechtsschutz', caseSensitive: false),
    'zahnzusatz': RegExp(r'zahnzusatz|zahnversicherung', caseSensitive: false),
    'handy': RegExp(r'handyversicherung|smartphone.?versicherung|displayschutz|gadget', caseSensitive: false),
    'unfall': RegExp(r'unfallversicherung', caseSensitive: false),
    'risikoleben': RegExp(r'risikolebens', caseSensitive: false),
    'kapitalleben': RegExp(r'kapitallebens|lebensversicherung', caseSensitive: false),
    'reise': RegExp(r'reiseversicherung|reiser[üu]cktritt|reisegep[äa]ck|auslandskranken', caseSensitive: false),
    'glas': RegExp(r'glasversicherung', caseSensitive: false),
    'restschuld': RegExp(r'restschuld', caseSensitive: false),
    'private_rente': RegExp(r'private rentenversicherung|fondsgebundene rente|riester|r[üu]rup', caseSensitive: false),
  };

  // often not worth it for people starting out (Verbraucherzentrale, Stiftung Warentest)
  static const rarely = {'handy', 'glas', 'restschuld', 'kapitalleben', 'unfall'};

  static String? typeOf(String name) {
    for (final e in _types.entries) {
      if (e.value.hasMatch(name)) return e.key;
    }
    return null;
  }

  static InsuranceReport check(Iterable<String> names) {
    final found = [
      for (final n in names)
        if (typeOf(n) case final t?) InsuranceFinding(n, t)
    ];
    final count = <String, int>{};
    for (final f in found) {
      count[f.type] = (count[f.type] ?? 0) + 1;
    }
    return InsuranceReport(
      found,
      [for (final e in count.entries) if (e.value > 1) e.key],
      {for (final f in found) if (rarely.contains(f.type)) f.type}.toList(),
      !count.containsKey('haftpflicht'),
    );
  }
}

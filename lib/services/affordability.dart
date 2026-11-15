// „Kann ich mir das leisten?“ as a traffic light, from the person's own month:
//
//   grün  the money is free this month (or by the month asked), with 50 € to spare
//   gelb  it works, but only by pausing the savings rate or using savings
//         that are not the Notgroschen
//   rot   it would eat into the Notgroschen or the account goes short
//
// For a later month the usual surplus of the months until then counts. When
// it does not work now, it says how many months of saving it takes.
class AffordResult {
  final String light; // gruen, gelb, rot
  final int amountCents;
  final int roomCents; // free without touching anything
  final int withSavingsCents; // free when the savings rate pauses and spare savings count
  final int months; // months until the purchase (0 = this month)
  final int? monthsToSave; // when it does not fit: how long saving for it takes
  final int? ratePerMonthCents; // the monthly rate for that
  final List<String> reasons; // short codes for the agent and the offline answer
  const AffordResult({
    required this.light,
    required this.amountCents,
    required this.roomCents,
    required this.withSavingsCents,
    required this.months,
    this.monthsToSave,
    this.ratePerMonthCents,
    this.reasons = const [],
  });
}

class Affordability {
  static const bufferCents = 5000;

  static AffordResult check({
    required int amountCents,
    required int freeCents, // free until the end of this month after fixed costs and goals
    required int goalsMonthCents, // what goes to savings goals each month
    required int surplusCents, // usual income minus usual spending per month
    required int spareSavingsCents, // savings beyond the Notgroschen target
    int months = 0,
  }) {
    final m = months < 0 ? 0 : months;
    // what each later month leaves after the savings rate
    final perMonth = surplusCents - goalsMonthCents;
    final room = (m == 0 ? freeCents : (freeCents > 0 ? freeCents : 0) + (perMonth > 0 ? perMonth : 0) * m);
    final withSavings = room + goalsMonthCents * (m == 0 ? 1 : m) + spareSavingsCents;
    final reasons = <String>[];
    String light;
    if (amountCents <= room - bufferCents) {
      light = 'gruen';
      reasons.add('frei');
    } else if (amountCents <= withSavings) {
      light = 'gelb';
      if (amountCents > room) {
        reasons.add(goalsMonthCents > 0 ? 'sparrate_pausieren' : 'ersparnisse');
      } else {
        reasons.add('knapp');
      }
      if (spareSavingsCents > 0 && amountCents > room + goalsMonthCents * (m == 0 ? 1 : m)) {
        reasons.add('ersparnisse');
      }
    } else {
      light = 'rot';
      reasons.add(freeCents < 0 ? 'monat_schon_eng' : 'notgroschen');
    }

    int? toSave, rate;
    if (light != 'gruen') {
      // what is still missing, saved from what a month leaves
      final have = room > 0 ? room : 0;
      final missing = amountCents + bufferCents - have;
      final capacity = surplusCents > 0 ? surplusCents : 0;
      if (capacity > 0 && missing > 0) {
        toSave = (missing / capacity).ceil();
        final span = toSave > m ? toSave : (m > 0 ? m : 1);
        rate = ((amountCents - have) / span).ceil();
        if (rate < 0) rate = 0;
      } else if (capacity <= 0) {
        reasons.add('kein_ueberschuss');
      }
    }
    return AffordResult(
      light: light,
      amountCents: amountCents,
      roomCents: room,
      withSavingsCents: withSavings,
      months: m,
      monthsToSave: toSave,
      ratePerMonthCents: rate,
      reasons: reasons,
    );
  }
}

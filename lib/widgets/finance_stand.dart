// "Wo stehe ich?": the first of the three questions on the start screen.
// Three plain figures from the person's own numbers, or one line that says
// what is missing. No chart, no menu: the overview is the Überblick tab.
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../models/transaction.dart';
import '../services/contracts.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'pressable.dart';

class FinanceStand extends StatelessWidget {
  final List<Transaction> tx;
  // what the month still leaves and per day, already formatted; null while unknown
  final String? free, perDay;
  // the cash on the accounts, when the person told the app the balance
  final int? cashCents;
  // what the portfolio is worth today; zero without one
  final int depotCents;
  // no bookings yet: the way to get some
  final VoidCallback? onAdd;
  final DateTime? now;
  const FinanceStand(
      {super.key, required this.tx, this.free, this.perDay, this.cashCents, this.depotCents = 0, this.onAdd, this.now});

  // the monthly contracts (rent included: this is what goes out no matter what) and how long the cash lasts
  static ({int fixedCents, int contracts, int? wealthCents}) figures(List<Transaction> tx,
      {int? cashCents, int depotCents = 0, DateTime? now}) {
    final contracts = Contracts.detect(tx, now: now);
    return (
      fixedCents: Contracts.monthlyTotal(contracts),
      contracts: contracts.length,
      // account plus portfolio: what the person owns, not only what lies on the account
      wealthCents: cashCents == null && depotCents == 0 ? null : (cashCents ?? 0) + depotCents,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (tx.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Ich kenne deine Zahlen noch nicht.'),
            key: const Key('stand-empty'), style: TextStyle(fontSize: 14.5, height: 1.4, color: AppColors.textDim)),
        if (onAdd != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('stand-add'),
              onPressed: onAdd,
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppColors.glow),
              child: Text(tr('Umsätze hochladen'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
      ]);
    }
    final f = figures(tx, cashCents: cashCents, depotCents: depotCents, now: now);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _figure('stand-free', tr('Noch frei'), free ?? '–', perDay == null ? tr('diesen Monat') : tr('{y} pro Tag', {'y': perDay!})),
      _figure('stand-fixed', tr('Fixkosten'), f.fixedCents > 0 ? Money.format(f.fixedCents) : '–',
          f.fixedCents > 0 ? tr('im Monat') : null),
      _figure('stand-wealth', tr('Vermögen'), f.wealthCents == null ? '–' : Money.format(f.wealthCents!),
          depotCents > 0 ? tr('Konto + Depot') : null),
    ]);
  }

  Widget _figure(String key, String label, String value, String? note) => Expanded(
        child: Padding(
          key: Key(key),
          padding: const EdgeInsets.only(right: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 12.5, color: AppColors.textDim)),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              // a figure that changed fades in; it never counts up
              child: FadeSwap(
                child: Text(value,
                    key: ValueKey(value),
                    style: const TextStyle(fontFamily: AppFonts.display, fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.6)),
              ),
            ),
            if (note != null) Text(note, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
          ]),
        ),
      );
}

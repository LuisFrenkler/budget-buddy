import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/contracts.dart';
import '../services/db.dart';
import '../services/settings_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/big_number.dart';
import '../widgets/tx_row.dart';

// Contracts and subscriptions found in the bookings, what they cost per
// month and year, when each is due next and which ones got more expensive.
class ContractsScreen extends StatelessWidget {
  const ContractsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('transactions').listenable(),
      builder: (context, _, __) {
        final contracts = Contracts.detect(DB.getTx());
        final monthly = Contracts.monthlyTotal(contracts);
        final raised = contracts.where((c) => c.priceChange > 0).toList();

        return Scaffold(
          appBar: AppBar(title: const Text('Verträge & Abos')),
          body: contracts.isEmpty
              ? _empty()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    BigNumber(
                      label: 'Pro Monat',
                      cents: monthly,
                      below: Text(
                          '${contracts.length} ${contracts.length == 1 ? 'Vertrag' : 'Verträge'} · '
                          '${Settings.hideAmounts.value ? '•••' : Money.format(monthly * 12)} im Jahr',
                          style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                    ),
                    if (raised.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      _raisedBanner(raised),
                    ],
                    const SizedBox(height: 24),
                    Container(
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        for (int i = 0; i < contracts.length; i++) ...[
                          if (i > 0) Divider(height: 1, indent: 70, color: AppColors.border),
                          _row(context, contracts[i]),
                        ],
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Text(
                        'Erkannt an regelmäßigen, gleich hohen Zahlungen an denselben Empfänger. '
                        'Tippe auf einen Vertrag, um alle Zahlungen zu sehen.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                  ],
                ),
        );
      },
    );
  }

  Widget _raisedBanner(List<Contract> raised) {
    final c = raised.first;
    final text = raised.length == 1
        ? '${c.name} kostet seit der letzten Zahlung ${Money.format(c.priceChange)} mehr.'
        : '${raised.length} Verträge sind teurer geworden, z. B. ${c.name} (+${Money.format(c.priceChange)}).';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.trending_up_rounded, color: AppColors.warning),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ]),
    );
  }

  Widget _row(BuildContext context, Contract c) {
    return InkWell(
      onTap: () => showTransactionsSheet(context,
          title: c.name, subtitle: 'Alle Zahlungen', tx: c.payments.reversed.toList()),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Row(children: [
          CategoryAvatar(c.category, isIncome: false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text('Monatlich · nächste am ${Dates.dayMonth(c.nextDate)}',
                  style: TextStyle(fontSize: 12, color: AppColors.textDim), overflow: TextOverflow.ellipsis),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            ValueListenableBuilder<bool>(
              valueListenable: Settings.hideAmounts,
              builder: (_, hidden, __) => Text(hidden ? '•••' : Money.format(c.monthlyCents),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (c.priceChange > 0)
              Text('+${Money.format(c.priceChange)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.warning, fontWeight: FontWeight.w600)),
          ]),
        ]),
      ),
    );
  }

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.receipt_long_rounded, size: 56, color: AppColors.textDim),
            const SizedBox(height: 16),
            const Text('Noch keine Verträge erkannt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Sobald eine Zahlung drei Monate in Folge gleich hoch ist, erscheint sie hier. '
                'Mit verbundenem Bankkonto geht das automatisch.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
          ]),
        ),
      );
}

// Compact entry card ("Verträge & Abos · 6 erkannt · 1.034 € / Monat").
class ContractsCard extends StatelessWidget {
  const ContractsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final contracts = Contracts.detect(DB.getTx());
    if (contracts.isEmpty) return const SizedBox.shrink();
    final monthly = Contracts.monthlyTotal(contracts);
    final raised = contracts.where((c) => c.priceChange > 0).length;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContractsScreen())),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Verträge & Abos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                ValueListenableBuilder<bool>(
                  valueListenable: Settings.hideAmounts,
                  builder: (_, hidden, __) => Text(
                    [
                      '${contracts.length} erkannt',
                      hidden ? '••• / Monat' : '${Money.format(monthly)} / Monat',
                      if (raised > 0) '$raised teurer',
                    ].join(' · '),
                    style: TextStyle(fontSize: 13, color: raised > 0 ? AppColors.warning : AppColors.textDim),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
          ]),
        ),
      ),
    );
  }
}

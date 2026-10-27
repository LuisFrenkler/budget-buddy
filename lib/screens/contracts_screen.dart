import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/account_service.dart';
import '../services/cancellation_service.dart';
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
    // settings hold the sent cancellations, so a new one shows right away
    return ListenableBuilder(
      listenable: Listenable.merge([Hive.box('transactions').listenable(), Hive.box('settings').listenable()]),
      builder: (context, _) {
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
      onTap: () => _ContractSheet.show(context, c),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
        child: Row(children: [
          CategoryAvatar(c.category, isIncome: false, merchant: c.name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Builder(builder: (_) {
                final sent = CancellationService.sentAt(c.name);
                return Text(
                    sent != null
                        ? 'Gekündigt am ${Dates.dayMonth(sent)}'
                        : 'Monatlich · nächste am ${Dates.dayMonth(c.nextDate)}',
                    style: TextStyle(fontSize: 12, color: sent != null ? AppColors.warningText : AppColors.textDim),
                    overflow: TextOverflow.ellipsis);
              }),
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
                  style: TextStyle(fontSize: 12, color: AppColors.warningText, fontWeight: FontWeight.w600)),
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
                    style: TextStyle(fontSize: 13, color: raised > 0 ? AppColors.warningText : AppColors.textDim),
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

// One contract: what it costs, its payments, and cancelling it with a ready
// letter. Copying the letter or opening the mail app doesn't cancel anything
// yet; only once the user says it went out does the row show "Gekündigt" and
// Buddy watch whether the payments stop.
class _ContractSheet extends StatefulWidget {
  final Contract contract;
  const _ContractSheet(this.contract);

  static Future<void> show(BuildContext context, Contract c) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        showDragHandle: true,
        builder: (_) => _ContractSheet(c),
      );

  @override
  State<_ContractSheet> createState() => _ContractSheetState();
}

class _ContractSheetState extends State<_ContractSheet> {
  final _customerNo = TextEditingController();
  bool _writing = false;
  // the letter was copied or handed to the mail app; sent only once confirmed
  bool _prepared = false;

  @override
  void dispose() {
    _customerNo.dispose();
    super.dispose();
  }

  String get _letter {
    final account = AccountService.current.value;
    return CancellationService.letter(
      provider: widget.contract.name,
      // a visible gap rather than a letter without a name
      name: account?.name ?? '[Dein Name]',
      email: account?.email ?? '',
      customerNo: _customerNo.text.trim(),
    );
  }

  Future<void> _sent() async {
    await CancellationService.markSent(widget.contract.name);
    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 3500),
        content: Text('Vermerkt. Buddy prüft in den nächsten Wochen, ob ${widget.contract.name} wirklich aufhört.')));
  }

  Future<void> _mail() async {
    final uri = Uri(scheme: 'mailto', query: _query({
      'subject': CancellationService.subject(widget.contract.name, _customerNo.text.trim()),
      'body': _letter,
    }));
    if (await launchUrl(uri) && mounted) setState(() => _prepared = true);
  }

  static String _query(Map<String, String> p) =>
      p.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _letter));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _prepared = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        duration: Duration(milliseconds: 2400), content: Text('Kündigung kopiert. Füg sie beim Anbieter ein.')));
  }

  // a regular payment that isn't a contract (pocket money, a rent share)
  Future<void> _notAContract() async {
    final name = widget.contract.name;
    await Contracts.hide(name);
    HapticFeedback.selectionClick();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(
      duration: const Duration(seconds: 5),
      content: Text('„$name“ wird nicht mehr als Vertrag gezählt'),
      action: SnackBarAction(label: 'Rückgängig', onPressed: () => Contracts.hide(name, hide: false)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contract;
    final sent = CancellationService.sentAt(c.name);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CategoryAvatar(c.category, isIncome: false, merchant: c.name, size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                Text('${Money.format(c.monthlyCents)} im Monat · ${Money.format(c.monthlyCents * 12)} im Jahr',
                    style: TextStyle(color: AppColors.textDim)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => showTransactionsSheet(context,
                title: c.name, subtitle: 'Alle Zahlungen', tx: c.payments.reversed.toList()),
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: Text('Alle ${c.payments.length} Zahlungen'),
          ),
          const SizedBox(height: 18),
          if (sent != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
              child: Text(
                  'Gekündigt am ${Dates.full(sent)}. Kommt danach noch eine Abbuchung, sagt Buddy dir Bescheid.',
                  style: const TextStyle(height: 1.4)),
            ),
            TextButton(
              onPressed: () async {
                await CancellationService.undo(c.name);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Kündigung zurücknehmen'),
            ),
          ] else if (!_writing)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52), backgroundColor: AppColors.error.withValues(alpha: 0.9)),
              onPressed: () => setState(() => _writing = true),
              icon: const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text('${c.name} kündigen'),
            )
          else ...[
            const Text('Buddy hat deine Kündigung geschrieben',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            TextField(
              controller: _customerNo,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Kundennummer (optional)'),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
              child: SingleChildScrollView(
                child: SelectableText(_letter, style: const TextStyle(fontSize: 13, height: 1.45)),
              ),
            ),
            const SizedBox(height: 8),
            Text('Tipp: Viele Anbieter haben auf ihrer Website einen Button „Verträge hier kündigen“. '
                'Dort geht es oft am schnellsten, den Text kannst du dort einfügen.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.4)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Kopieren'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  onPressed: _mail,
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Per E-Mail'),
                ),
              ),
            ]),
            if (_prepared) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppColors.surfaceAlt,
                    foregroundColor: AppColors.text),
                onPressed: _sent,
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Ich habe sie abgeschickt'),
              ),
            ],
          ],
          if (sent == null)
            TextButton(
              onPressed: _notAContract,
              child: Text('Kein Vertrag? Nicht mehr mitzählen', style: TextStyle(color: AppColors.textDim)),
            ),
        ]),
      ),
    );
  }
}

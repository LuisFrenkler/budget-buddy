import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'checkout_screen.dart';
import '../services/plus_service.dart';
import '../services/store_purchases.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import '../legal/legal_texts.dart';
import 'about_screen.dart';
import 'subscription_screen.dart';
import '../l10n/l10n.dart';

// Opens the Plus page; [reason] says what the user just tried to do, so the
// page starts with that instead of a generic pitch.
Future<void> showPlus(BuildContext context, {String? reason}) {
  HapticFeedback.mediumImpact();
  return Navigator.push(
    context,
    MaterialPageRoute(
        fullscreenDialog: true, builder: (_) => PlusScreen(reason: reason)),
  );
}

class PlusScreen extends StatefulWidget {
  final String? reason;
  const PlusScreen({super.key, this.reason});

  @override
  State<PlusScreen> createState() => _PlusScreenState();
}

class _PlusScreenState extends State<PlusScreen> {
  bool _yearly = true;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    // the store's own prices arrive a moment later
    StorePurchases.prices.addListener(_pricesArrived);
  }

  @override
  void dispose() {
    StorePurchases.prices.removeListener(_pricesArrived);
    super.dispose();
  }

  void _pricesArrived() {
    if (mounted) setState(() {});
  }

  // only promise a free week when the store confirmed eligibility (true).
  // Apple often returns null → never claim "7 Tage gratis" / "Heute 0 €".
  bool? get _trial =>
      StorePurchases.trial[_yearly ? PlusPlan.yearly : PlusPlan.monthly];
  bool get _hasTrial => _trial == true;

  Future<void> _buy() async {
    final ok = await showCheckout(
        context, _yearly ? PlusPlan.yearly : PlusPlan.monthly,
        reason: widget.reason);
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final found = await PlusService.restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 2800),
        content: Text(found
            ? tr('Dein Plus-Abo ist wieder aktiv')
            : tr('Kein Abo zum Wiederherstellen'))));
    if (found) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: PlusService.active,
      builder: (context, hasPlus, _) {
        if (hasPlus) return _alreadyPlus(context);
        return _pitch(context);
      },
    );
  }

  Widget _alreadyPlus(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                  tooltip: tr('Schließen'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context)),
            ),
            const Spacer(),
            const BuddyOrb(size: 88),
            const SizedBox(height: 24),
            Text(tr('Plus ist aktiv'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.6)),
            const SizedBox(height: 10),
            Text(tr('Ahead, Belege und Ziele ohne Limit.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textDim, fontSize: 15, height: 1.4)),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const SubscriptionScreen()));
              },
              child: Text(tr('Mein Abo verwalten')),
            ),
            const SizedBox(height: 8),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('Schließen'))),
          ]),
        ),
      ),
    );
  }

  Widget _pitch(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
                tooltip: tr('Schließen'),
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              children: [
                const Center(child: BuddyOrb(size: 72)),
                const SizedBox(height: 18),
                Text(tr('Ahead Plus'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.8,
                        height: 1.15)),
                const SizedBox(height: 6),
                Text(tr('Ahead ohne Limit'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.glow,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3)),
                if (_hasTrial) ...[
                  const SizedBox(height: 6),
                  Text(tr('7 Tage gratis, danach kündbar'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, fontSize: 14)),
                ],
                if (widget.reason != null) ...[
                  const SizedBox(height: 14),
                  Text(widget.reason!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.text, fontSize: 15, height: 1.4)),
                ],
                const SizedBox(height: 28),
                _compare(),
                const SizedBox(height: 16),
                Text(
                  tr('Konto, Budgets, Prognose, Verträge und Notgroschen bleiben gratis. Keine Werbung.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textDim, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 22),
                _plan(true),
                const SizedBox(height: 10),
                _plan(false),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Column(children: [
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56)),
                onPressed: _buy,
                child: Text(
                    _hasTrial ? tr('7 Tage gratis testen') : tr('Plus starten'),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              // what the stores require next to the button: price, period,
              // automatic renewal, where to cancel, and the legal texts
              Text(
                _hasTrial
                    ? tr(
                        'Danach {x} {x2}, verlängert sich automatisch. Heute 0 €, jederzeit kündbar {x3}.',
                        {
                            'x': PlusService.price(
                                _yearly ? PlusPlan.yearly : PlusPlan.monthly),
                            'x2': _yearly ? tr('im Jahr') : tr('im Monat'),
                            'x3': StorePurchases.supported
                                ? tr('im {x}', {'x': StorePurchases.storeName})
                                : tr('unter Profil › Mein Abo')
                          })
                    : tr(
                        '{x} {x2}, verlängert sich automatisch, jederzeit kündbar {x3}.',
                        {
                            'x': PlusService.price(
                                _yearly ? PlusPlan.yearly : PlusPlan.monthly),
                            'x2': _yearly ? tr('im Jahr') : tr('im Monat'),
                            'x3': StorePurchases.supported
                                ? tr('im {x}', {'x': StorePurchases.storeName})
                                : tr('unter Profil › Mein Abo')
                          }),
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
              ),
              Wrap(alignment: WrapAlignment.center, children: [
                for (final doc in [LegalTexts.terms, LegalTexts.privacy])
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textDim,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12)),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => LegalDocScreen(doc: doc))),
                    child: Text(doc.title == 'Nutzungsbedingungen'
                        ? 'AGB'
                        : tr('Datenschutz')),
                  ),
                TextButton(
                  onPressed: _restoring ? null : _restore,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.textDim,
                      visualDensity: VisualDensity.compact,
                      textStyle: const TextStyle(fontSize: 12)),
                  child: Text(_restoring
                      ? tr('Wird gesucht …')
                      : tr('Käufe wiederherstellen')),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // Free vs Plus. Numbers come from PlusService, so the screen cannot drift from the quota.
  Widget _compare() {
    final dim = TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.2);
    final plus = TextStyle(
        color: AppColors.brandText,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.2);
    final label = const TextStyle(fontSize: 15, fontWeight: FontWeight.w600);
    Widget cell(String text, TextStyle style, {bool end = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(text,
              textAlign: end ? TextAlign.end : TextAlign.start, style: style),
        );
    final rows = [
      (
        tr('Ahead'),
        tr('{x}/Monat', {'x': PlusService.limit(PlusFeature.aiQuestion)})
      ),
      (
        tr('Belege'),
        tr('{x}/Monat', {'x': PlusService.limit(PlusFeature.receiptScan)})
      ),
      (tr('Sparziele'), '${PlusService.limit(PlusFeature.goal)}'),
    ];
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.5),
        1: FlexColumnWidth(1),
        2: FlexColumnWidth(1.15)
      },
      children: [
        TableRow(children: [
          const SizedBox.shrink(),
          cell(tr('Gratis'), dim, end: true),
          cell(tr('Plus'), plus, end: true),
        ]),
        for (final r in rows)
          TableRow(children: [
            cell(r.$1, label),
            cell(r.$2, dim, end: true),
            cell(tr('ohne Limit'), plus, end: true),
          ]),
      ],
    );
  }

  Widget _plan(bool yearly) {
    final selected = _yearly == yearly;
    return Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _yearly = yearly);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? AppColors.primary : AppColors.textDim),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(yearly ? tr('Jährlich') : tr('Monatlich'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 16)),
                        if (yearly) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppColors.positive,
                                borderRadius: BorderRadius.circular(999)),
                            child: const Text('−33 %',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ]),
                      Text(
                          yearly
                              ? tr('nur {yearlyPerMonth} im Monat', {
                                  'yearlyPerMonth': PlusService.yearlyPerMonth
                                })
                              : tr('monatlich kündbar'),
                          style: TextStyle(
                              color: AppColors.textDim, fontSize: 13)),
                    ]),
              ),
              Text(
                  PlusService.price(
                      yearly ? PlusPlan.yearly : PlusPlan.monthly),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
          ),
        ));
  }
}

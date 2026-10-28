import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'checkout_screen.dart';
import '../services/plus_service.dart';
import '../services/store_purchases.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import '../widgets/free_tier_usage.dart';
import '../legal/legal_texts.dart';
import 'about_screen.dart';
import 'subscription_screen.dart';

// Opens the Plus page; [reason] says what the user just tried to do, so the
// page starts with that instead of a generic pitch.
Future<void> showPlus(BuildContext context, {String? reason}) {
  HapticFeedback.mediumImpact();
  return Navigator.push(
    context,
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => PlusScreen(reason: reason)),
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
  bool? get _trial => StorePurchases.trial[_yearly ? PlusPlan.yearly : PlusPlan.monthly];
  bool get _hasTrial => _trial == true;

  static const _features = [
    (Icons.auto_awesome_rounded, 'Buddy ohne Limit', 'Frag so oft du willst, mit KI'),
    (Icons.document_scanner_rounded, 'Belege ohne Limit', 'Belege fotografieren und prüfen — ohne Gratis-Limit'),
    (Icons.flag_rounded, 'Unbegrenzte Sparziele', 'Beliebig viele; Aufrunden & Monatsbetrag — zählt mit, überweist nicht'),
    (Icons.favorite_rounded, 'Du unterstützt BudgetBuddy', 'Ohne Werbung, ohne Datenverkauf'),
  ];

  Future<void> _buy() async {
    final ok = await showCheckout(context, _yearly ? PlusPlan.yearly : PlusPlan.monthly,
        reason: widget.reason);
    if (ok && mounted) Navigator.pop(context);
  }

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final found = await PlusService.restore();
    if (!mounted) return;
    setState(() => _restoring = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), 
        content: Text(found ? 'Dein Plus-Abo ist wieder aktiv' : 'Kein Abo gefunden, das wiederhergestellt werden kann')));
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
                  tooltip: 'Schließen', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ),
            const Spacer(),
            const BuddyOrb(size: 88),
            const SizedBox(height: 24),
            const Text('Plus ist aktiv',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
            const SizedBox(height: 10),
            Text('Buddy, Belege und Sparziele laufen ohne Limit.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 15, height: 1.4)),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
              },
              child: const Text('Mein Abo verwalten'),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen')),
          ]),
        ),
      ),
    );
  }

  Widget _pitch(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        // the brand glow behind the orb
        Positioned(
          top: -140,
          left: -100,
          right: -100,
          child: Container(
            height: 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.primary.withValues(alpha: 0.45),
                AppColors.primary.withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                  tooltip: 'Schließen', icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                children: [
                  const Center(child: BuddyOrb(size: 88)),
                  const SizedBox(height: 22),
                  if (widget.reason != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
                      ),
                      child: Text(widget.reason!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.4, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const Text('BudgetBuddy Plus',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15)),
                  const SizedBox(height: 8),
                  Text(
                      _hasTrial
                          ? '7 Tage gratis testen · danach jederzeit kündbar'
                          : 'Jederzeit kündbar · ohne Werbung',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim, fontSize: 15)),
                  const SizedBox(height: 26),
                  for (final f in _features)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                          child: Icon(f.$1, color: AppColors.primary, size: 20),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(f.$2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                            Text(f.$3, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                          ]),
                        ),
                      ]),
                    ),
                  // what never costs anything: trust before the price
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Icon(Icons.verified_rounded, color: AppColors.positive, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Immer gratis: Konto & Depot, Budgets, Monatsprognose, Verträge samt Kündigung, '
                          'Notgroschen & Vorsorge-Orientierung, Hinweise, Gruppen und dein Monatsrückblick.',
                          style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  const FreeTierUsage(),
                  const SizedBox(height: 16),
                  _plan(true),
                  const SizedBox(height: 10),
                  _plan(false),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final m in availableMethods().take(4))
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: MethodLogo(m)),
                  ]),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(children: [
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: _buy,
                  child: Text(_hasTrial ? '7 Tage gratis testen' : 'Plus starten',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 8),
                // what the stores require next to the button: price, period,
                // automatic renewal, where to cancel, and the legal texts
                Text(
                  _hasTrial
                      ? 'Danach ${PlusService.price(_yearly ? PlusPlan.yearly : PlusPlan.monthly)} '
                          '${_yearly ? 'im Jahr' : 'im Monat'}, verlängert sich automatisch. Heute 0 €, jederzeit kündbar '
                          '${StorePurchases.supported ? 'im ${StorePurchases.storeName}' : 'unter Profil › Mein Abo'}.'
                      : '${PlusService.price(_yearly ? PlusPlan.yearly : PlusPlan.monthly)} '
                          '${_yearly ? 'im Jahr' : 'im Monat'}, verlängert sich automatisch, jederzeit kündbar '
                          '${StorePurchases.supported ? 'im ${StorePurchases.storeName}' : 'unter Profil › Mein Abo'}.',
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
                      onPressed: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: doc))),
                      child: Text(doc.title == 'Nutzungsbedingungen' ? 'AGB' : 'Datenschutz'),
                    ),
                  TextButton(
                    onPressed: _restoring ? null : _restore,
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.textDim,
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 12)),
                    child: Text(_restoring ? 'Wird gesucht …' : 'Käufe wiederherstellen'),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ]),
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
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
              color: selected ? AppColors.primary : AppColors.textDim),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(yearly ? 'Jährlich' : 'Monatlich', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (yearly) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.positive, borderRadius: BorderRadius.circular(999)),
                    child: const Text('−33 %',
                        style: TextStyle(color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ],
              ]),
              Text(yearly ? 'nur ${PlusService.yearlyPerMonth} im Monat' : 'monatlich kündbar',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ]),
          ),
          Text(PlusService.price(yearly ? PlusPlan.yearly : PlusPlan.monthly),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      ),
    ));
  }
}

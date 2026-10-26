import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'checkout_screen.dart';
import '../services/plus_service.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';

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

  static const _features = [
    (Icons.auto_awesome_rounded, 'Buddy ohne Limit', 'Frag so oft du willst, mit KI'),
    (Icons.document_scanner_rounded, 'Belege ohne Limit', 'Jeder Kassenbon in Sekunden erfasst'),
    (Icons.flag_rounded, 'Sparziele auf Autopilot', 'Beliebig viele, mit Aufrunden und Monatsbetrag'),
    (Icons.insights_rounded, 'Buddys Wochenbericht', 'Jeden Sonntag: was auffiel und wo du sparen kannst'),
    (Icons.favorite_rounded, 'Du unterstützt BudgetBuddy', 'Ohne Werbung, ohne Datenverkauf'),
  ];

  Future<void> _buy() async {
    final ok = await showCheckout(context, _yearly ? PlusPlan.yearly : PlusPlan.monthly);
    if (ok && mounted) Navigator.pop(context);
  }

  void _restore() {
    final found = PlusService.restore();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(found ? 'Dein Plus-Abo ist wieder aktiv' : 'Kein Abo gefunden, das wiederhergestellt werden kann')));
    if (found) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
              child: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                children: [
                  const Center(child: BuddyOrb(size: 88)),
                  const SizedBox(height: 22),
                  Text(widget.reason ?? 'Hol dir das volle BudgetBuddy',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15)),
                  const SizedBox(height: 8),
                  Text('BudgetBuddy Plus · 7 Tage gratis, jederzeit kündbar',
                      textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim, fontSize: 15)),
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
                          'Hinweise, Gruppen und dein Monatsrückblick.',
                          style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4),
                        ),
                      ),
                    ]),
                  ),
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
                  child: const Text('7 Tage gratis testen', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Danach ${_yearly ? '${PlusService.yearlyPrice} im Jahr' : '${PlusService.monthlyPrice} im Monat'}. '
                  'Heute 0 €, jederzeit kündbar unter Profil › Mein Abo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
                ),
                TextButton(
                  onPressed: _restore,
                  style: TextButton.styleFrom(foregroundColor: AppColors.textDim, visualDensity: VisualDensity.compact),
                  child: const Text('Käufe wiederherstellen', style: TextStyle(fontSize: 12.5)),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _plan(bool yearly) {
    final selected = _yearly == yearly;
    return GestureDetector(
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
          Text(yearly ? PlusService.yearlyPrice : PlusService.monthlyPrice,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      ),
    );
  }
}

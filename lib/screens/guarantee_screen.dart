// The offer: what the membership costs, the guarantee in plain words and what
// counts towards it. Paying does not exist yet, so the only action is
// "Vormerken": the date is kept on the device and one anonymous counter goes up.
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../l10n/l10n.dart';
import '../services/ahead_agent.dart';
import '../services/product_events.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

class GuaranteeScreen extends StatefulWidget {
  const GuaranteeScreen({super.key});

  @override
  State<GuaranteeScreen> createState() => _GuaranteeScreenState();
}

class _GuaranteeScreenState extends State<GuaranteeScreen> {
  static Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
  late bool _reserved = _box?.get('guaranteeReserved') != null;

  @override
  void initState() {
    super.initState();
    ProductEvents.track(ProductEvents.guaranteeSeen);
  }

  Future<void> _reserve() async {
    ProductEvents.track(ProductEvents.guaranteeReserve);
    await _box?.put('guaranteeReserved', DateTime.now().toIso8601String());
    if (mounted) setState(() => _reserved = true);
  }

  @override
  Widget build(BuildContext context) {
    // a price is never private: the mask for hidden amounts does not apply
    final goal = Money.raw(AheadAgent.guaranteeCents);
    final dim = TextStyle(color: AppColors.textDim, fontSize: 15, height: 1.45);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Mitgliedschaft mit Garantie'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
        Text(
            tr('{m} im Monat oder {y} im Jahr',
                {'m': Money.raw(AheadAgent.monthlyFeeCents), 'y': Money.raw(AheadAgent.yearlyFeeCents)}),
            key: const Key('guarantee-price'),
            style: const TextStyle(
                fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w600, letterSpacing: -0.6, height: 1.15)),
        const SizedBox(height: 12),
        Text(
            tr('Holt Ahead dir in zwölf Monaten ab Beitritt nicht mindestens {x} zurück, bekommst du den ganzen Beitrag wieder.',
                {'x': goal}),
            style: const TextStyle(fontSize: 16.5, height: 1.4)),
        const SizedBox(height: 6),
        Text(tr('{x} sind das Doppelte des Jahresbeitrags. Die zwölf Monate laufen ab dem Tag, an dem du beitrittst.', {'x': goal}),
            style: dim),
        const SizedBox(height: 20),
        _list(tr('Das zählt'), Icons.check_rounded, AppColors.positiveText, [
          tr('Steuererstattung laut Bescheid, für Jahre, die du mit Ahead abgegeben hast'),
          tr('Monatliche Abbuchungen, die nach einem Kündigungsschreiben aus Ahead ausbleiben'),
          tr('Doppelte Abbuchungen, die der Händler zurückgezahlt hat'),
        ]),
        const SizedBox(height: 12),
        _list(tr('Das zählt nicht'), Icons.close_rounded, AppColors.textDim, [
          tr('Schätzungen und offene Funde. Es zählt nur Geld, das angekommen ist.'),
          tr('Erstattungen für Jahre, die du ohne Ahead abgegeben hast'),
          tr('Jahresverträge und alles, was sich in deinen Buchungen nicht zeigt'),
        ]),
        const SizedBox(height: 20),
        Text(tr('Bezahlen geht noch nicht. Mit „Vormerken“ sagst du uns nur, dass du dabei wärst. Es kostet nichts und verpflichtet dich zu nichts.'),
            style: dim),
        const SizedBox(height: 16),
        if (_reserved)
          Text(tr('Vorgemerkt. Wir melden uns, sobald du beitreten kannst.'),
              key: const Key('guarantee-reserved'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.glow, height: 1.4))
        else
          FilledButton(
            key: const Key('guarantee-reserve'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _reserve,
            child: Text(tr('Vormerken')),
          ),
      ]),
    );
  }

  Widget _list(String title, IconData icon, Color color, List<String> lines) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(child: Text(l, style: const TextStyle(fontSize: 14.5, height: 1.35))),
              ]),
            ),
        ]),
      );
}

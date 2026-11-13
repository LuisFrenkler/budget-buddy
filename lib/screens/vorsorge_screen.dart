import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/buddy_service.dart';
import '../services/db.dart';
import '../services/goals_service.dart';
import '../services/vorsorge.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'buddy_screen.dart';
import '../l10n/l10n.dart';

// Light Altersvorsorge: Rentenlücke from a few inputs + depot.
class VorsorgeScreen extends StatefulWidget {
  const VorsorgeScreen({super.key});

  @override
  State<VorsorgeScreen> createState() => _VorsorgeScreenState();
}

class _VorsorgeScreenState extends State<VorsorgeScreen> {
  late VorsorgeInput _input = Vorsorge.load();
  late final _desired = TextEditingController(text: _euro(_input.desiredNetCents));
  late final _statutory = TextEditingController(text: _input.statutoryCents > 0 ? _euro(_input.statutoryCents) : '');
  late final _bav = TextEditingController(text: _input.bavCents > 0 ? _euro(_input.bavCents) : '');
  late final _riester = TextEditingController(text: _input.riesterCents > 0 ? _euro(_input.riesterCents) : '');

  static String _euro(int cents) {
    final v = cents / 100;
    if (v == v.roundToDouble()) return '${v.round()}';
    return v.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    _desired.dispose();
    _statutory.dispose();
    _bav.dispose();
    _riester.dispose();
    super.dispose();
  }

  VorsorgeResult get _result => Vorsorge.build(
        input: _input,
        holdings: DB.getHoldings(),
        goals: GoalsService.all(),
      );

  Future<void> _persist(VorsorgeInput next) async {
    setState(() => _input = next);
    await Vorsorge.save(next);
  }

  int? _parse(String s) => Money.parseToCents(s.trim());

  Future<void> _applyFields() async {
    await _persist(_input.copyWith(
      desiredNetCents: _parse(_desired.text) ?? _input.desiredNetCents,
      statutoryCents: _parse(_statutory.text) ?? 0,
      bavCents: _parse(_bav.text) ?? 0,
      riesterCents: _parse(_riester.text) ?? 0,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Vorsorge')),
        actions: [
          IconButton(
            tooltip: tr('So rechnet Buddy'),
            onPressed: _assumptions,
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(tr('Orientierung, keine Beratung'),
              style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            tr('Buddy schätzt eine monatliche Lücke. Maßgeblich bleibt deine Rentenauskunft der DRV. Keine Steuern, keine Inflation, keine Produktempfehlung.'),
            style: TextStyle(color: AppColors.textDim, height: 1.35, fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          if (!r.ready) _emptyGap() else _gapCard(r),
          const SizedBox(height: 18),
          _label(tr('Dein Plan')),
          _ageRow(),
          const SizedBox(height: 10),
          _moneyField(_desired, tr('Gewünschtes Netto im Alter / Monat'), onDone: _applyFields),
          const SizedBox(height: 10),
          _moneyField(_statutory, tr('Erwartete gesetzliche Rente / Monat'),
              hint: tr('Aus der DRV-Auskunft'), onDone: _applyFields),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                final net = await _askNet();
                if (net == null) return;
                final est = Vorsorge.estimateStatutoryFromNet(net);
                _statutory.text = _euro(est);
                await _persist(_input.copyWith(statutoryCents: est));
              },
              child: Text(tr('Ungefähr aus Netto-Gehalt schätzen')),
            ),
          ),
          const SizedBox(height: 10),
          _moneyField(_bav, tr('Betriebsrente / Monat (optional)'), onDone: _applyFields),
          const SizedBox(height: 10),
          _moneyField(_riester, tr('Riester / Rürup / Monat (optional)'), onDone: _applyFields),
          const SizedBox(height: 18),
          _label(tr('Kapital in der App')),
          _line(tr('Depot'), Money.format(DB.getHoldings().fold<int>(0, (s, h) => s + h.valueCents))),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Offene Sparziele mitzählen'), style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tr('Notgroschen bleibt außen vor'), style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            value: _input.includeGoals,
            onChanged: (v) => _persist(_input.copyWith(includeGoals: v)),
          ),
          _line(tr('Davon als monatliche Rente (25 Jahre, 0 %)'), Money.format(r.capitalAsMonthlyCents)),
          const SizedBox(height: 18),
          if (r.ready)
            OutlinedButton.icon(
              onPressed: () {
                HapticFeedback.selectionClick();
                final q = r.gapClosed
                    ? tr('Reicht meine Altersvorsorge so aus?')
                    : tr('Wie schließe ich eine Rentenlücke von {x} im Monat?', {'x': Money.format(r.gapMonthlyCents)});
                BuddyScreen.open(context, q);
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(tr('Mit Buddy besprechen')),
            ),
        ],
      ),
    );
  }

  Widget _emptyGap() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border.withValues(alpha: 0.7)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.timeline_rounded, color: AppColors.primaryText, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Rentenlücke noch offen'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            tr('Gib unten mindestens deine erwartete gesetzliche Rente an, ideal aus der DRV-Auskunft. Alternativ kannst du sie grob aus deinem Netto schätzen.'),
            style: TextStyle(color: AppColors.textDim, height: 1.45, fontSize: 13.5),
          ),
          const SizedBox(height: 12),
          Text(tr('Danach siehst du hier eine grobe monatliche Lücke (ohne Steuern und Inflation).'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: () async {
              final net = await _askNet();
              if (net == null) return;
              final est = Vorsorge.estimateStatutoryFromNet(net);
              _statutory.text = _euro(est);
              await _persist(_input.copyWith(statutoryCents: est));
            },
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: Text(tr('Rente aus Netto schätzen')),
          ),
        ]),
      );

  Widget _gapCard(VorsorgeResult r) {
    final color = r.gapClosed ? AppColors.positive : AppColors.warning;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r.gapClosed ? tr('Orientierung: Lücke geschlossen') : tr('Orientierung: monatliche Lücke'),
            style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(r.gapClosed ? tr('Im groben Plan') : Money.format(r.gapMonthlyCents),
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: color)),
        const SizedBox(height: 8),
        Text(
          r.gapClosed
              ? tr('Gedeckt ca. {x} von {x2} · ohne Steuern/Inflation.', {'x': Money.format(r.coveredMonthlyCents), 'x2': Money.format(r.input.desiredNetCents)})
              : tr('Gedeckt ca. {x}. Zum Schließen grob {x2} / Monat zusätzlich ({yearsLeft} Jahre, ~{x3} % Realrendite). Kaufkraft und Steuern sind nicht eingerechnet.', {'x': Money.format(r.coveredMonthlyCents), 'x2': Money.format(r.saveExtraMonthlyCents), 'yearsLeft': r.yearsLeft, 'x3': (Vorsorge.realReturn * 100).round()}),
          style: TextStyle(height: 1.35, color: AppColors.text.withValues(alpha: 0.9)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
            onPressed: _assumptions,
            child: Text(tr('So rechnet Buddy')),
          ),
        ),
      ]),
    );
  }

  void _assumptions() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('So rechnet Buddy'), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              tr('• Kapital (Depot, optional Sparziele ohne Notgroschen) wird über {drawYears} Jahre ohne Rendite aufgeteilt, konservativ für die Entnahmephase.\n\n• Die „extra sparen“-Rate nimmt ~{x} % Realrendite bis zur Rente an (Faustformel, kein Versprechen).\n\n• Netto-Schätzung der gesetzlichen Rente: etwa {x2} % deines heutigen Nettos. Das ist nur ein Platzhalter. Ersetze ihn durch die Zahl aus der DRV-Auskunft.\n\n• Keine Steuern, Sozialabgaben oder Inflation. Keine Anlage- oder Rentenberatung.', {'drawYears': Vorsorge.drawYears, 'x': (Vorsorge.realReturn * 100).round(), 'x2': (Vorsorge.estimateShare * 100).round()}),
              style: TextStyle(color: AppColors.textDim, height: 1.45),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _ageRow() {
    return Row(children: [
      Expanded(child: _stepper(tr('Alter heute'), _input.age, 18, 70, (v) => _persist(_input.copyWith(age: v)))),
      const SizedBox(width: 12),
      Expanded(
          child: _stepper(tr('Rente ab'), _input.retireAge, 60, 70, (v) => _persist(_input.copyWith(retireAge: v)))),
    ]);
  }

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: AppColors.textDim, fontSize: 12, fontWeight: FontWeight.w600)),
        Row(children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value <= min ? null : () => onChanged(value - 1),
            icon: const Icon(Icons.remove_rounded),
          ),
          Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value >= max ? null : () => onChanged(value + 1),
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
      ]),
    );
  }

  Widget _moneyField(TextEditingController c, String label, {String? hint, VoidCallback? onDone}) {
    return TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, hintText: hint, suffixText: '€'),
      onEditingComplete: onDone,
      onSubmitted: (_) => onDone?.call(),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _line(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(color: AppColors.textDim))),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
        ]),
      );

  Future<int?> _askNet() async {
    final income = BuddyService.snapshot().avgIncome;
    final c = TextEditingController(text: income > 0 ? _euro(income) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Netto-Gehalt / Monat')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tr('Buddy nimmt grob {x} % davon als gesetzliche Rente an (Orientierung für die Mitte der Karriere). Bitte später durch die DRV-Auskunft ersetzen.', {'x': (Vorsorge.estimateShare * 100).round()}),
            style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: '€'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Schätzen'))),
        ],
      ),
    );
    if (ok != true) return null;
    return Money.parseToCents(c.text);
  }
}

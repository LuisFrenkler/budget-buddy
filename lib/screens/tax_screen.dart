// Steuer 2026: what comes back with the tax return, collected all year. A few
// answers (gross, months, commute, home office) and the bookings that may
// count; each one can be left out. Buddy goes through it with you.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/db.dart';
import '../services/tax_estimate.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'buddy_screen.dart';

class TaxScreen extends StatefulWidget {
  final DateTime? now;
  const TaxScreen({super.key, this.now});

  @override
  State<TaxScreen> createState() => _TaxScreenState();
}

class _TaxScreenState extends State<TaxScreen> {
  late TaxProfile _p = TaxEstimate.profile();
  late final _gross = TextEditingController(text: _p.grossMonth > 0 ? _num(_p.grossMonth) : '');
  late final _km = TextEditingController(text: _p.km > 0 ? _num(_p.km) : '');
  late Map<String, bool> _picks = TaxEstimate.picks();

  int get _year => (widget.now ?? DateTime.now()).year;

  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  void dispose() {
    _gross.dispose();
    _km.dispose();
    super.dispose();
  }

  Future<void> _save(TaxProfile next) async {
    setState(() => _p = next);
    await TaxEstimate.saveProfile(next);
  }

  void _readFields() {
    final g = Money.parseToCents(_gross.text.trim());
    final k = double.tryParse(_km.text.trim().replaceAll(',', '.'));
    _save(_p.copyWith(grossMonth: g == null ? null : g / 100, km: k ?? (_km.text.trim().isEmpty ? 0 : null)));
  }

  @override
  Widget build(BuildContext context) {
    final candidates = TaxEstimate.candidates(DB.getTx(), _year);
    final receipts = candidates.where((c) => _picks[c.tx.id] ?? true).fold<int>(0, (s, c) => s + c.tx.amountCents) / 100;
    final ready = _p.grossMonth > 0;
    final r = ready ? TaxEstimate.compute(_p, receipts: receipts) : null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Steuer {y}', {'y': _year}))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(
            tr('Buddy sammelt übers Jahr, was du absetzen kannst, und schätzt, was mit der Steuererklärung zurückkommt. Schätzung, keine Steuerberatung.'),
            style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 13.5),
          ),
          const SizedBox(height: 18),
          if (r == null) _empty() else _result(r),
          const SizedBox(height: 22),
          _label(tr('Dein Jahr')),
          TextField(
            controller: _gross,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Brutto pro Monat'), suffixText: '€'),
            onEditingComplete: _readFields,
            onSubmitted: (_) => _readFields(),
          ),
          const SizedBox(height: 10),
          _stepper(tr('Monate gearbeitet in {y}', {'y': _year}), _p.monthsWorked, 1, 12,
              (v) => _save(_p.copyWith(monthsWorked: v))),
          const SizedBox(height: 10),
          _stepper(tr('Steuerklasse'), _p.taxClass, 1, 4, (v) => _save(_p.copyWith(taxClass: v))),
          const SizedBox(height: 18),
          _label(tr('Arbeitsweg')),
          TextField(
            controller: _km,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Entfernung zur Arbeit, einfach'), suffixText: 'km'),
            onEditingComplete: _readFields,
            onSubmitted: (_) => _readFields(),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: _stepper(tr('Bürotage / Woche'), _p.officeDaysPerWeek.round(), 0, 5,
                    (v) => _save(_p.copyWith(officeDaysPerWeek: v.toDouble())))),
            const SizedBox(width: 10),
            Expanded(
                child: _stepper(tr('Homeoffice / Woche'), _p.homeDaysPerWeek.round(), 0, 5,
                    (v) => _save(_p.copyWith(homeDaysPerWeek: v.toDouble())))),
          ]),
          const SizedBox(height: 22),
          _label(tr('Belege aus deinen Buchungen')),
          if (candidates.isEmpty)
            Text(
              tr('Noch nichts gefunden. Fachbücher, Kurse, Arbeitsmittel, Gewerkschaft, Bewerbungen und Umzug zum Job tauchen hier auf, sobald sie gebucht sind.'),
              style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 13.5),
            )
          else
            for (final c in candidates)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _picks[c.tx.id] ?? true,
                onChanged: (v) async {
                  HapticFeedback.selectionClick();
                  await TaxEstimate.pick(c.tx.id, v ?? false);
                  setState(() => _picks = TaxEstimate.picks());
                },
                title: Text(c.tx.note ?? tr(c.tx.category), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${Dates.dayMonth(c.tx.date)} · ${_kind(c.kind)}',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                secondary: Text(Money.format(c.tx.amountCents), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.selectionClick();
              BuddyScreen.open(
                  context,
                  ready
                      ? tr('Geh mit mir meine Steuererklärung {y} durch: Was kommt zurück und was fehlt noch?', {'y': _year})
                      : tr('Lohnt sich eine Steuererklärung für mich?'));
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text(tr('Mit Buddy durchgehen')),
          ),
          const SizedBox(height: 12),
          Text(
            tr('Regeln {y}: Pendlerpauschale 0,38 € ab dem ersten Kilometer, Homeoffice 6 € am Tag bis 210 Tage, Arbeitnehmer-Pauschbetrag 1.230 €. Abgeben kannst du kostenlos über ELSTER.',
                {'y': _year}),
            style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _kind(String k) => switch (k) {
        'fortbildung' => tr('Fortbildung'),
        'arbeitsmittel' => tr('Arbeitsmittel'),
        'gewerkschaft' => tr('Gewerkschaft'),
        'bewerbung' => tr('Bewerbung'),
        'umzug' => tr('Umzug'),
        _ => tr('Werbungskosten'),
      };

  Widget _empty() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
        child: Text(tr('Trag dein Brutto ein, dann rechnet Buddy die Erstattung aus.'),
            style: TextStyle(color: AppColors.textDim, height: 1.4)),
      );

  Widget _result(TaxResult r) {
    final back = r.refund;
    final color = back >= 1 ? AppColors.positive : AppColors.textDim;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(back >= 1 ? tr('Kommt voraussichtlich zurück') : tr('Voraussichtlich keine Erstattung'),
            style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(Money.format((back > 0 ? back * 100 : 0).round()),
            style: TextStyle(
                fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: color)),
        const SizedBox(height: 10),
        _line(tr('Fahrten zur Arbeit'), r.commute),
        _line(tr('Homeoffice'), r.homeOffice),
        _line(tr('Belege'), r.receipts),
        _line(tr('Kontoführung, pauschal'), r.accountFee),
        _line(tr('Werbungskosten zusammen'), r.werbungskosten, bold: true),
        const SizedBox(height: 6),
        _line(tr('Lohnsteuer einbehalten'), r.withheld),
        _line(tr('Steuer fürs Jahr'), r.due),
        for (final n in r.notes)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(n, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4)),
          ),
      ]),
    );
  }

  Widget _line(String a, double eur, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(color: AppColors.textDim, fontSize: 13.5))),
          Text(Money.format((eur * 100).round()),
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5)),
        ]),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _stepper(String label, int value, int min, int max, ValueChanged<int> onChanged) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w600))),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value <= min ? null : () => onChanged(value - 1),
            icon: const Icon(Icons.remove_rounded),
          ),
          Text('$value', style: const TextStyle(fontFamily: AppFonts.display, fontSize: 18, fontWeight: FontWeight.w600)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: value >= max ? null : () => onChanged(value + 1),
            icon: const Icon(Icons.add_rounded),
          ),
        ]),
      );
}

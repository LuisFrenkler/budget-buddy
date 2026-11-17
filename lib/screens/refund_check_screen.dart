// Der Rückhol-Check: three answers, then what may come back for every year
// that can still be filed, as a range with its reasons. Works before sign-up.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../l10n/l10n.dart';
import '../services/account_service.dart';
import '../services/product_events.dart';
import '../services/tax_estimate.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'auth_screens.dart';
import 'tax_screen.dart';

class RefundCheckScreen extends StatefulWidget {
  final DateTime? now;
  // where the check was opened, counted anonymously: start, app
  final String source;
  const RefundCheckScreen({super.key, this.now, this.source = 'app'});

  // the answers, so the tax page starts filled in after sign-up
  static Map? saved() => Hive.isBoxOpen('settings') ? Hive.box('settings').get('refundCheck') as Map? : null;

  @override
  State<RefundCheckScreen> createState() => _RefundCheckScreenState();
}

class _RefundCheckScreenState extends State<RefundCheckScreen> {
  DateTime get _today => widget.now ?? DateTime.now();
  late int _startYear = _today.year - 1;
  int _startMonth = 1;
  final _gross = TextEditingController();
  final _km = TextEditingController();
  List<QuickYear>? _result;
  bool _perYear = false;

  @override
  void dispose() {
    _gross.dispose();
    _km.dispose();
    super.dispose();
  }

  double? get _grossValue {
    final c = Money.parseToCents(_gross.text.trim());
    if (c == null || c <= 0) return null;
    return _perYear ? c / 100 / 12 : c / 100;
  }

  Future<void> _check() async {
    final gross = _grossValue;
    if (gross == null) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    final km = double.tryParse(_km.text.trim().replaceAll(',', '.')) ?? 0;
    setState(() => _result = TaxEstimate.quickCheck(
        startYear: _startYear, startMonth: _startMonth, grossMonth: gross, km: km, today: _today));
    if (Hive.isBoxOpen('settings')) {
      await Hive.box('settings').put('refundCheck',
          {'startYear': _startYear, 'startMonth': _startMonth, 'grossMonth': gross, 'km': km});
    }
    await ProductEvents.track(ProductEvents.refundCheck);
    await ProductEvents.track(widget.source == 'start' ? ProductEvents.refundCheckStart : ProductEvents.refundCheckApp);
  }

  Future<void> _next() async {
    if (AccountService.current.value == null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen()));
      return;
    }
    // signed in: every checked year gets its answers, then the first open year opens
    for (final y in _result ?? const <QuickYear>[]) {
      await TaxEstimate.saveProfile(
          TaxProfile(
              grossMonth: _grossValue ?? 0,
              km: double.tryParse(_km.text.trim().replaceAll(',', '.')) ?? 0,
              monthsWorked: y.year == _startYear ? 13 - _startMonth : 12),
          year: y.year);
    }
    if (!mounted) return;
    final first = _result?.where((y) => y.deadline != null).firstOrNull?.year;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TaxScreen(year: first, now: widget.now)));
  }

  @override
  Widget build(BuildContext context) {
    final years = [for (var y = _today.year; y >= _today.year - 5; y--) y];
    final open = (_result ?? const <QuickYear>[]).where((y) => y.deadline != null);
    final total = open.fold<double>(0, (s, y) => s + y.high);
    final sure = open.fold<double>(0, (s, y) => s + y.low);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Rückhol-Check'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(tr('Drei Antworten, dann siehst du, was für jedes offene Jahr zurückkommen kann. Ohne Anmeldung, ohne Bank.'),
              style: TextStyle(color: AppColors.textDim, height: 1.4)),
          const SizedBox(height: 20),
          Text(tr('1. Wann hast du angefangen zu arbeiten?'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: const Key('refund-month'),
                value: _startMonth,
                decoration: InputDecoration(labelText: tr('Monat')),
                items: [
                  for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(Dates.months[m - 1])),
                ],
                onChanged: (v) => setState(() => _startMonth = v ?? 1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: const Key('refund-year'),
                value: _startYear,
                decoration: InputDecoration(labelText: tr('Jahr')),
                items: [
                  for (final y in years)
                    DropdownMenuItem(value: y, child: Text(y == years.last ? tr('{y} oder früher', {'y': y}) : '$y')),
                ],
                onChanged: (v) => setState(() => _startYear = v ?? _today.year - 1),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(tr('2. Dein Brutto'), style: const TextStyle(fontWeight: FontWeight.w800))),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(value: false, label: Text(tr('pro Monat'))),
                ButtonSegment(value: true, label: Text(tr('pro Jahr'))),
              ],
              selected: {_perYear},
              onSelectionChanged: (v) => setState(() => _perYear = v.first),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            key: const Key('refund-gross'),
            controller: _gross,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: _perYear ? tr('Brutto im vollen Jahr') : tr('Brutto pro Monat'), suffixText: '€'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          Text(tr('3. Entfernung zur Arbeit (optional)'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            key: const Key('refund-km'),
            controller: _km,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Entfernung zur Arbeit, einfach'), suffixText: 'km'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('refund-check'),
            onPressed: _grossValue == null ? null : _check,
            child: Text(tr('Rückhol-Check starten')),
          ),
          if (_result != null) ...[
            const SizedBox(height: 26),
            if (total >= 1)
              // the low end first: the notice should beat the headline, not break it
              Text(
                  total - sure < 20
                      ? tr('Rund {x} für die offenen Jahre', {'x': Money.format((total * 100).round())})
                      : tr('Mindestens rund {x}, bis zu {y} für die offenen Jahre',
                          {'x': Money.format((sure * 100).round()), 'y': Money.format((total * 100).round())}),
                  style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.6,
                      color: AppColors.positiveText)),
            for (final y in _result!) _year(y),
            const SizedBox(height: 10),
            Text(
              tr('Schätzung aus deinen Angaben, keine Steuerberatung. Die echte Zahl steht im Bescheid, und nur die zeigen wir dir später als Ergebnis.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('refund-next'),
              onPressed: _next,
              child: Text(AccountService.current.value == null
                  ? tr('Konto erstellen und Geld zurückholen')
                  : tr('Weiter zur Abgabe')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _year(QuickYear y) {
    final band = y.high < 1
        ? tr('voraussichtlich nichts')
        : (y.high - y.low) < 20
            ? tr('ca. {x}', {'x': Money.format((y.high * 100).round())})
            : '${Money.format((y.low * 100).round())} – ${Money.format((y.high * 100).round())}';
    final days = y.deadline?.difference(DateTime(_today.year, _today.month, _today.day)).inDays;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${y.year}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          Text(band, style: TextStyle(fontWeight: FontWeight.w800, color: y.high >= 1 ? AppColors.positiveText : null)),
        ]),
        const SizedBox(height: 4),
        Text(
          y.deadline == null
              ? tr('Läuft noch. Abgeben ab 1. Januar {y}.', {'y': y.year + 1})
              : days! <= 60
                  ? tr('Abgabe bis {d}, noch {n} Tage. Danach ist das Geld weg.', {'d': Dates.full(y.deadline!), 'n': days})
                  : tr('Abgabe bis {d}.', {'d': Dates.full(y.deadline!)}),
          style: TextStyle(
              color: days != null && days <= 60 ? AppColors.warningText : AppColors.textDim,
              fontSize: 12.5,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        for (final r in y.reasons)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('• $r', style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
          ),
      ]),
    );
  }
}

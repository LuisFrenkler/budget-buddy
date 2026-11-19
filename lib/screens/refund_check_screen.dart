// Der Rückhol-Check: three answers, one per page, then what may come back for
// every year that can still be filed, as a range with its reasons. Works
// before sign-up, and so does the yes that follows.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../l10n/l10n.dart';
import '../services/account_service.dart';
import '../services/product_events.dart';
import '../services/tax_estimate.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/motion.dart';
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

  // The check's answers as the tax profile of every year from the start on,
  // so a year's page opens filled in. Before sign-up they sit in the keys
  // AccountIsolation wipes on every sign-in and at every start without one;
  // 'refundCheck' stays, so the new account gets them back
  // (TaxEstimate.adoptRefundCheck) and a find's yes can fill them again.
  // [overwrite]: fresh answers replace older ones, otherwise a year's own answers stay.
  static Future<void> saveProfiles({required DateTime now, bool overwrite = false}) async {
    final q = saved();
    if (q == null) return;
    final start = (q['startYear'] as num).toInt(), month = (q['startMonth'] as num).toInt();
    for (final y in [...TaxEstimate.openYears(now), now.year]) {
      if (y < start || (!overwrite && Hive.box('settings').get('taxProfile:$y') != null)) continue;
      await TaxEstimate.saveProfile(
          TaxProfile(
              grossMonth: (q['grossMonth'] as num).toDouble(),
              km: (q['km'] as num?)?.toDouble() ?? 0,
              monthsWorked: y == start ? 13 - month : 12),
          year: y);
    }
  }

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
  // one question per page: 0 start of work, 1 gross pay, 2 distance, 3 the result
  int _step = 0;
  // which way the last step went: 0 on the first paint (still), 1 forward, -1 back
  int _dir = 0;

  void _go(int step) {
    _dir = step > _step ? 1 : -1;
    _step = step;
  }

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
    final km = double.tryParse(_km.text.trim().replaceAll(',', '.')) ?? 0;
    setState(() {
      _result = TaxEstimate.quickCheck(
          startYear: _startYear, startMonth: _startMonth, grossMonth: gross, km: km, today: _today);
      _go(3);
    });
    // felt once the frame with the number is drawn, not while it is still the question
    WidgetsBinding.instance.addPostFrameCallback((_) => HapticFeedback.mediumImpact());
    if (Hive.isBoxOpen('settings')) {
      await Hive.box('settings')
          .put('refundCheck', {'startYear': _startYear, 'startMonth': _startMonth, 'grossMonth': gross, 'km': km});
    }
    await ProductEvents.track(ProductEvents.refundCheck);
    await ProductEvents.track(widget.source == 'start' ? ProductEvents.refundCheckStart : ProductEvents.refundCheckApp);
  }

  // the yes, with or without an account: every checked year gets its answers,
  // then the first open year with money in it opens
  Future<void> _next() async {
    HapticFeedback.lightImpact();
    await RefundCheckScreen.saveProfiles(now: _today, overwrite: true);
    if (!mounted) return;
    final open = (_result ?? const <QuickYear>[]).where((y) => y.deadline != null);
    final first = (open.where((y) => y.high >= 1).firstOrNull ?? open.firstOrNull)?.year;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => TaxScreen(year: first, now: widget.now)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // back goes one question back, and only the first one leaves the check
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _go(_step - 1));
      },
      child: Scaffold(
        appBar: AppBar(title: Text(tr('Rückhol-Check'))),
        body: _step == 3 ? _arrive(_resultPage()) : _question(),
      ),
    );
  }

  // one arrival for every page: a fade and a small rise (from above on the way back), the old page is gone at once
  Widget _arrive(Widget page) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(_step),
      tween: Tween(begin: 0, end: 1),
      duration: _dir == 0
          ? Duration.zero
          : _step == 3
              ? Motion.reveal
              : Motion.fast,
      curve: Motion.out,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, Motion.reduce(context) ? 0 : _dir * (1 - t) * Motion.rise),
          child: child,
        ),
      ),
      child: page,
    );
  }

  Widget _question() {
    final years = [for (var y = _today.year; y >= _today.year - 5; y--) y];
    // 16 px and more: smaller text fields make mobile browsers zoom in
    const field = TextStyle(fontSize: 20, fontWeight: FontWeight.w600);
    final last = _step == 2;
    void forward() => last ? _check() : setState(() => _go(_step + 1));
    final ready = _step != 1 || _grossValue != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        child: Row(key: const Key('refund-steps'), children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: AnimatedContainer(
                duration: Motion.base,
                curve: Motion.color,
                height: 4,
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                decoration: BoxDecoration(
                    color: i <= _step ? AppColors.glow : AppColors.surfaceAlt, borderRadius: BorderRadius.circular(2)),
              ),
            ),
        ]),
      ),
      Expanded(
        child: _arrive(ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 20), children: [
          Text(
              switch (_step) {
                0 => tr('1. Wann hast du angefangen zu arbeiten?'),
                1 => tr('2. Dein Brutto'),
                _ => tr('3. Entfernung zur Arbeit (optional)'),
              },
              style: const TextStyle(
                  fontFamily: AppFonts.display, fontSize: 28, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.8)),
          const SizedBox(height: 10),
          if (_step == 0)
            Text(
                tr('Drei Antworten, dann siehst du, was für jedes offene Jahr zurückkommen kann. Ohne Anmeldung, ohne Bank.'),
                style: TextStyle(color: AppColors.textDim, height: 1.4)),
          const SizedBox(height: 18),
          // one below the other: side by side "2021 oder früher" does not fit a phone
          if (_step == 0) ...[
            DropdownButtonFormField<int>(
              key: const Key('refund-month'),
              isExpanded: true,
              initialValue: _startMonth,
              decoration: InputDecoration(labelText: tr('Monat')),
              items: [
                for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(Dates.months[m - 1])),
              ],
              onChanged: (v) => setState(() => _startMonth = v ?? 1),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              key: const Key('refund-year'),
              isExpanded: true,
              initialValue: _startYear,
              decoration: InputDecoration(labelText: tr('Jahr')),
              items: [
                for (final y in years)
                  DropdownMenuItem(value: y, child: Text(y == years.last ? tr('{y} oder früher', {'y': y}) : '$y')),
              ],
              onChanged: (v) => setState(() => _startYear = v ?? _today.year - 1),
            ),
          ],
          if (_step == 1) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: false, label: Text(tr('pro Monat'))),
                  ButtonSegment(value: true, label: Text(tr('pro Jahr'))),
                ],
                selected: {_perYear},
                onSelectionChanged: (v) => setState(() => _perYear = v.first),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('refund-gross'),
              controller: _gross,
              autofocus: true,
              style: field,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: _perYear ? tr('Brutto im vollen Jahr') : tr('Brutto pro Monat'), suffixText: '€'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _grossValue == null ? null : forward(),
            ),
          ],
          if (last)
            TextField(
              key: const Key('refund-km'),
              controller: _km,
              autofocus: true,
              style: field,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('Entfernung zur Arbeit, einfach'), suffixText: 'km'),
              onSubmitted: (_) => _check(),
            ),
        ])),
      ),
      SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          FilledButton(
            key: Key(last ? 'refund-check' : 'refund-step-next'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: ready ? forward : null,
            child: Text(last ? tr('Rückhol-Check starten') : tr('Weiter')),
          ),
          if (last)
            TextButton(
              key: const Key('refund-skip'),
              onPressed: () {
                _km.clear();
                _check();
              },
              child: Text(tr('Überspringen')),
            ),
        ]),
      ),
    ]);
  }

  Widget _resultPage() {
    final guest = AccountService.current.value == null;
    final open = _result!.where((y) => y.deadline != null);
    final total = open.fold<double>(0, (s, y) => s + y.high);
    final sure = open.fold<double>(0, (s, y) => s + y.low);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        if (total >= 1)
          // the low end first: the notice should beat the headline, not break it
          Text(
              sure < 1
                  // no sure minimum: "mindestens 0 €" would promise nothing
                  ? tr('Bis zu {x} für die offenen Jahre', {'x': Money.format((total * 100).round())})
                  : total - sure < 20
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
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: _next,
          child: Text(guest ? tr('Ja, los') : tr('Weiter zur Abgabe')),
        ),
        // the account is an offer here, not the price of the next step
        if (guest)
          TextButton(
            key: const Key('refund-signup'),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
            child: Text(tr('Konto anlegen')),
          ),
      ],
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
                  ? tr('Abgabe bis {d}, noch {n} Tage. Danach ist das Geld weg.',
                      {'d': Dates.full(y.deadline!), 'n': days})
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

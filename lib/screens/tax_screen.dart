// Steuer: what comes back with the tax return, for every year that can still
// be filed. A few answers or the Lohnsteuerbescheinigung, the bookings that
// may count, then every ELSTER field to type in. After filing, the notice is
// checked against the estimate. Estimate, not tax advice; the person files.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../services/account_service.dart';
import '../services/buddy_service.dart';
import '../services/buddy_tasks.dart';
import '../services/db.dart';
import '../services/tax_docs.dart';
import '../services/tax_estimate.dart';
import '../services/tax_letters.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/share_card.dart';
import 'auth_screens.dart';
import 'buddy_screen.dart';
import 'refund_check_screen.dart';
import 'smart_entry_sheet.dart';

class TaxScreen extends StatefulWidget {
  final DateTime? now;
  final int? year;
  const TaxScreen({super.key, this.now, this.year});

  @override
  State<TaxScreen> createState() => _TaxScreenState();
}

class _TaxScreenState extends State<TaxScreen> {
  DateTime get _today => widget.now ?? DateTime.now();
  late final List<int> _years = [...TaxEstimate.openYears(_today), _today.year];
  late int _year = widget.year != null && _years.contains(widget.year) ? widget.year! : _years.first;
  late TaxProfile _p = _load(_year);
  late final _gross = TextEditingController(text: _p.grossMonth > 0 ? _num(_p.grossMonth) : '');
  late final _km = TextEditingController(text: _p.km > 0 ? _num(_p.km) : '');
  late Map<String, bool> _picks = TaxEstimate.picks();
  String? _busy, _error;

  bool get _past => _year < _today.year;

  // what the person said about the ELSTER account: nothing, the day it was requested, 'ready' or 'paper'
  String get _elster => Hive.isBoxOpen('settings') ? '${Hive.box('settings').get('elsterAccount') ?? ''}' : '';
  bool get _elsterDone => _elster == 'ready' || _elster == 'paper';

  static String _num(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceAll('.', ',');

  // a year without answers starts from the refund check, if there was one
  TaxProfile _load(int year) {
    final p = TaxEstimate.profile(year: year);
    final q = RefundCheckScreen.saved();
    if (p.grossMonth > 0 || q == null) return p;
    final start = (q['startYear'] as num?)?.toInt() ?? year;
    if (year < start) return p;
    return p.copyWith(
      grossMonth: (q['grossMonth'] as num?)?.toDouble(),
      km: (q['km'] as num?)?.toDouble(),
      monthsWorked: year == start ? 13 - ((q['startMonth'] as num?)?.toInt() ?? 1) : 12,
    );
  }

  // what the two text fields say right now, on top of the saved answers
  TaxProfile _withFields() {
    final g = Money.parseToCents(_gross.text.trim());
    final k = double.tryParse(_km.text.trim().replaceAll(',', '.'));
    return _p.copyWith(grossMonth: g == null ? null : g / 100, km: k ?? (_km.text.trim().isEmpty ? 0 : null));
  }

  @override
  void dispose() {
    // typed but not confirmed: keep it anyway
    final typed = _withFields();
    if (typed.grossMonth != _p.grossMonth || typed.km != _p.km) TaxEstimate.saveProfile(typed, year: _year);
    _gross.dispose();
    _km.dispose();
    super.dispose();
  }

  void _switch(int year) {
    HapticFeedback.selectionClick();
    final typed = _withFields();
    if (typed.grossMonth != _p.grossMonth || typed.km != _p.km) TaxEstimate.saveProfile(typed, year: _year);
    setState(() {
      _year = year;
      _p = _load(year);
      _gross.text = _p.grossMonth > 0 ? _num(_p.grossMonth) : '';
      _km.text = _p.km > 0 ? _num(_p.km) : '';
      _error = null;
    });
  }

  Future<void> _save(TaxProfile next) async {
    setState(() => _p = next);
    await TaxEstimate.saveProfile(next, year: _year);
  }

  void _readFields() => _save(_withFields());

  // a photo of the certificate or the notice, read by the AI, checked here
  Future<TaxDoc?> _photo(String busy) async {
    if (!BuddyService.hasConsent) {
      final ok = await BuddyScreen.requestAiConsent(context);
      if (!ok || !mounted) return null;
    }
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = picked?.files.single;
    if (file?.bytes == null) return null;
    final ext = (file!.extension ?? 'jpg').toLowerCase();
    final mime = switch (ext) { 'png' => 'image/png', 'webp' => 'image/webp', 'gif' => 'image/gif', _ => 'image/jpeg' };
    setState(() {
      _busy = busy;
      _error = null;
    });
    try {
      return await TaxDoc.read(file.bytes!, mime);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _certificate() async {
    final d = await _photo(tr('Ahead liest deine Lohnsteuerbescheinigung …'));
    if (d == null || !mounted) return;
    if (!d.isCertificate) {
      setState(() => _error = tr('Das sieht nicht nach einer Lohnsteuerbescheinigung aus.'));
      return;
    }
    if (d.year != _year && _years.contains(d.year)) _switch(d.year!);
    if (d.year != _year) {
      setState(() => _error = tr('Die Bescheinigung ist für {y}. Dieses Jahr kann nicht mehr abgegeben werden.', {'y': d.year}));
      return;
    }
    HapticFeedback.mediumImpact();
    await _save(d.applyTo(_p));
    _gross.text = _num(_p.grossMonth);
  }

  Future<void> _assessment() async {
    final d = await _photo(tr('Ahead liest deinen Steuerbescheid …'));
    if (d == null || !mounted) return;
    if (!d.isAssessment) {
      setState(() => _error = tr('Das sieht nicht nach einem Einkommensteuerbescheid aus.'));
      return;
    }
    HapticFeedback.mediumImpact();
    await TaxEstimate.saveAssessment(d.toAssessment());
    if (mounted) setState(() {});
  }

  void _letter(String title, String text) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: SelectableText(text, style: const TextStyle(height: 1.4)),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (sheet.mounted) Navigator.pop(sheet);
                },
                child: Text(tr('Kopieren')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  await Share.share(text, subject: title);
                  if (sheet.mounted) Navigator.pop(sheet);
                },
                child: Text(tr('Senden …')),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counted = TaxEstimate.counted(DB.getTx(), _year);
    final candidates = TaxEstimate.candidates(DB.getTx(), _year);
    final receipts = counted.fold<int>(0, (s, c) => s + c.tx.amountCents) / 100;
    final ready = _p.grossMonth > 0;
    final r = ready ? TaxEstimate.compute(_p, receipts: receipts, year: _year) : null;
    final band = ready ? TaxEstimate.range(_p, receipts: receipts, year: _year) : null;
    final filed = TaxEstimate.filedAt(_year);
    final assessed = TaxEstimate.assessment(_year);
    // opened straight after the refund check: everything on the device works, reading photos needs the server
    final guest = AccountService.current.value == null;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Steuer {y}', {'y': _year}))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _overview(),
          const SizedBox(height: 12),
          if (_past) _deadline(),
          if (_past) ...[const SizedBox(height: 10), _steps(ready)],
          // the activation letter takes up to two weeks: ask for the account before the numbers
          if (_past && filed == null && !_elsterDone) ...[const SizedBox(height: 12), _elsterAccount()],
          if (_busy != null) ...[
            const SizedBox(height: 12),
            Row(children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(child: Text(_busy!, style: TextStyle(color: AppColors.textDim))),
            ]),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: AppColors.errorText, fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 14),
          if (assessed != null)
            _assessed(assessed, r)
          else if (r == null)
            _empty()
          else
            _result(r, band!),
          const SizedBox(height: 22),
          _label(tr('Dein Jahr')),
          if (guest)
            _needsAccount(tr('Mit Konto liest Ahead deine Lohnsteuerbescheinigung vom Foto.'))
          else
            OutlinedButton.icon(
              key: const Key('tax-certificate'),
              onPressed: _busy != null ? null : _certificate,
              icon: const Icon(Icons.document_scanner_outlined, size: 18),
              label: Text(_p.fromCertificate
                  ? tr('Lohnsteuerbescheinigung erfasst, neu fotografieren')
                  : tr('Lohnsteuerbescheinigung fotografieren')),
            ),
          TextButton(
            onPressed: () => _letter(tr('Anfrage an deinen Arbeitgeber'),
                TaxLetters.employerRequest(year: _year, name: AccountService.current.value?.firstName ?? '')),
            child: Text(tr('Papier weg? Kopie beim Arbeitgeber anfragen')),
          ),
          const SizedBox(height: 6),
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await showSmartEntry(context, scan: true);
                if (mounted) setState(() {});
              },
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(tr('Beleg fotografieren, z. B. Fachbuch oder Arbeitsmittel')),
            ),
          ),
          if (candidates.isEmpty)
            Text(
              tr('Noch nichts. Fachbücher, Kurse, Arbeitsmittel, Gewerkschaft, Bewerbung und Umzug zum Job erscheinen hier, sobald gebucht.'),
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
          if (_past && r != null) ...[
            const SizedBox(height: 22),
            _label(tr('So gibst du ab')),
            if (_elsterDone) ...[_elsterAccount(), const SizedBox(height: 14)],
            _fields(r, counted),
            const SizedBox(height: 14),
            if (filed == null) ...[
              Text(
                tr('Diese Saison ist Ahead für die Abgabe gratis. Im Tausch lädst du später den Bescheid hoch, damit die Schätzung für alle genauer wird.'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('tax-filed'),
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  await TaxEstimate.markFiled(_year, r.refund, control: TaxEstimate.controlEstimate(_p, _year));
                  await BuddyTasks.add(tr('Steuerbescheid {y} da? Foto machen, Ahead prüft ihn.', {'y': _year}),
                      due: DateTime.now().add(const Duration(days: 56)));
                  setState(() {});
                },
                child: Text(tr('Ich habe abgegeben')),
              ),
            ] else if (assessed == null) ...[
              Text(tr('Abgegeben am {d}. Der Bescheid kommt meist nach sechs bis zwölf Wochen.', {'d': Dates.full(filed)}),
                  style: TextStyle(color: AppColors.textDim, height: 1.4)),
              const SizedBox(height: 8),
              if (guest)
                _needsAccount(tr('Mit Konto liest Ahead deinen Bescheid vom Foto und prüft ihn.'))
              else
                FilledButton.icon(
                  key: const Key('tax-assessment'),
                  onPressed: _busy != null ? null : _assessment,
                  icon: const Icon(Icons.mark_email_read_outlined, size: 18),
                  label: Text(tr('Bescheid ist da: fotografieren')),
                ),
            ],
          ],
          const SizedBox(height: 18),
          // the chat that takes the question lives behind the account
          if (!guest)
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
              label: Text(tr('Mit Ahead durchgehen')),
            ),
          const SizedBox(height: 12),
          Text(_rules(), style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 12)),
        ],
      ),
    );
  }

  // reading a photo runs on the server: without an account, one line and the way to get one
  Widget _needsAccount(String text) => Row(children: [
        Expanded(child: Text(text, style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 13.5))),
        TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
          child: Text(tr('Konto anlegen')),
        ),
      ]);

  // the four steps of a late return, so the next one is always clear
  Widget _steps(bool ready) {
    final filed = TaxEstimate.filedAt(_year) != null;
    final steps = [
      (tr('ELSTER-Konto'), _elster.isNotEmpty || filed),
      (tr('Zahlen'), ready),
      (tr('Werte eintragen'), filed),
      (tr('Abgegeben'), filed),
    ];
    final next = steps.indexWhere((s) => !s.$2);
    return Row(children: [
      for (var i = 0; i < steps.length; i++)
        Expanded(
          child: Column(children: [
            Icon(
              steps[i].$2 ? Icons.check_circle_rounded : (i == next ? Icons.radio_button_checked_rounded : Icons.circle_outlined),
              size: 20,
              color: steps[i].$2 ? AppColors.positiveText : (i == next ? AppColors.brand : AppColors.textDim),
            ),
            const SizedBox(height: 4),
            Text(steps[i].$1,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: i == next ? FontWeight.w800 : FontWeight.w600,
                    color: i == next ? null : AppColors.textDim)),
          ]),
        ),
    ]);
  }

  // every year at once: what may come back, what is filed, what the notice said
  Widget _overview() => Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          for (final y in _years)
            InkWell(
              key: Key('tax-year-$y'),
              onTap: () => _switch(y),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(
                    y == _year ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: y == _year ? AppColors.brand : AppColors.textDim,
                  ),
                  const SizedBox(width: 10),
                  Text('$y', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_status(y),
                        overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
                  ),
                  Text(_amount(y), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
        ]),
      );

  String _status(int y) {
    if (TaxEstimate.assessment(y) != null) return tr('Bescheid da');
    if (TaxEstimate.filedAt(y) != null) return tr('abgegeben');
    if (y >= _today.year) return tr('läuft noch');
    return tr('offen bis {d}', {'d': Dates.full(TaxEstimate.deadline(y))});
  }

  String _amount(int y) {
    final a = TaxEstimate.assessment(y);
    if (a != null) return Money.format((a.refund * 100).round());
    final p = y == _year ? _p : _load(y);
    if (p.grossMonth <= 0) return '–';
    final receipts = TaxEstimate.counted(DB.getTx(), y).fold<int>(0, (s, c) => s + c.tx.amountCents) / 100;
    return _band(TaxEstimate.range(p, receipts: receipts, year: y));
  }

  String _rules() => _year >= 2026
      ? tr('Regeln {y}: Pendlerpauschale 0,38 €/km ab dem 1. km, Homeoffice 6 €/Tag bis 210 Tage, Arbeitnehmer-Pauschbetrag 1.230 €. Abgeben kostenlos über ELSTER.',
          {'y': _year})
      : _year <= 2022
          ? tr('Regeln {y}: Pendlerpauschale 0,30 €/km bis km 20, 0,38 € ab km 21, Homeoffice 5 €/Tag bis 120 Tage, Arbeitnehmer-Pauschbetrag 1.200 €. Abgeben kostenlos über ELSTER.',
              {'y': _year})
          : tr('Regeln {y}: Pendlerpauschale 0,30 €/km bis km 20, 0,38 € ab km 21, Homeoffice 6 €/Tag bis 210 Tage, Arbeitnehmer-Pauschbetrag 1.230 €. Abgeben kostenlos über ELSTER.',
              {'y': _year});

  Widget _deadline() {
    final d = TaxEstimate.deadline(_year);
    final days = d.difference(DateTime(_today.year, _today.month, _today.day)).inDays;
    final urgent = days <= 60;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (urgent ? AppColors.warning : AppColors.brand).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        urgent
            ? tr('Abgabe für {y} bis {d}, noch {n} Tage. Es zählt der Eingang beim Finanzamt, danach ist das Geld weg.',
                {'y': _year, 'd': Dates.full(d), 'n': days})
            : tr('Abgabe für {y} freiwillig bis {d}.', {'y': _year, 'd': Dates.full(d)}),
        style: TextStyle(fontWeight: FontWeight.w600, height: 1.4, color: urgent ? AppColors.warningText : null),
      ),
    );
  }

  // the ELSTER account: the step most people get stuck on, with the real wait
  Widget _elsterAccount() {
    final box = Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
    final requested = DateTime.tryParse(_elster);
    final days = TaxEstimate.deadline(_year).difference(_today).inDays;
    Future<void> set(String v) async {
      await box?.put('elsterAccount', v);
      setState(() {});
    }

    if (_elster == 'ready') {
      return Text(tr('ELSTER-Konto ist da. Melde dich auf elster.de an und trag die Werte unten ein.'),
          style: TextStyle(color: AppColors.textDim, height: 1.4));
    }
    if (_elster == 'paper') {
      return Text(tr('Du gibst auf Papier ab. Übertrag die Werte unten in die Formulare und unterschreib den Hauptvordruck.'),
          style: TextStyle(color: AppColors.textDim, height: 1.4));
    }
    Widget card(String title, String text, List<Widget> actions) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(text, style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 13.5)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: actions),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card(
        requested == null ? tr('Hast du schon ein ELSTER-Konto?') : tr('ELSTER-Konto'),
        requested == null
            ? tr('Kostenlos auf elster.de. Mit dem Online-Ausweis geht es sofort, sonst kommt ein Aktivierungsbrief per Post, meist innerhalb von zwei Wochen.')
            : tr('Beantragt am {d}. Der Brief sollte bis {e} da sein.',
                {'d': Dates.full(requested), 'e': Dates.full(requested.add(const Duration(days: 14)))}),
        [
          if (requested == null) ...[
            OutlinedButton(
              onPressed: () => launchUrl(Uri.parse('https://www.elster.de'), mode: LaunchMode.externalApplication),
              child: Text(tr('Zu ELSTER')),
            ),
            TextButton(
                onPressed: () async {
                  await set(DateTime.now().toIso8601String());
                  await BuddyTasks.add(tr('ELSTER-Brief da? Dann die Steuererklärung {y} abgeben.', {'y': _year}),
                      due: DateTime.now().add(const Duration(days: 14)));
                },
                child: Text(tr('Habe ich beantragt'))),
          ],
          TextButton(onPressed: () => set('ready'), child: Text(tr('Ich habe ein Konto'))),
        ],
      ),
      // too close for the letter to arrive: paper is a way of its own, with the same weight
      if (days <= 21) ...[
        const SizedBox(height: 10),
        card(
          tr('Oder auf Papier abgeben'),
          tr('Knapp bis zur Frist: Du kannst die Erklärung auch auf Papier abgeben. Es zählt der Eingang beim Finanzamt.'),
          [
            OutlinedButton(
              onPressed: () =>
                  launchUrl(Uri.parse('https://www.formulare-bfinv.de'), mode: LaunchMode.externalApplication),
              child: Text(tr('Formulare öffnen')),
            ),
            TextButton(
                key: const Key('tax-paper'), onPressed: () => set('paper'), child: Text(tr('Ich gebe auf Papier ab'))),
          ],
        ),
      ],
    ]);
  }

  // every ELSTER field with its value, one tap to copy
  Widget _fields(TaxResult r, List<TaxCandidate> counted) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('In ELSTER: Einkommensteuererklärung {y}', {'y': _year}),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            tr('Hauptvordruck: Name, Adresse, Steuer-ID und die IBAN für die Erstattung. Dann Anlage N mit diesen Werten:'),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
          ),
          for (final f in TaxEstimate.elster(r, counted))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('${f['feld']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('${f['wert']}'),
              trailing: f['wert'] is num
                  ? IconButton(
                      tooltip: tr('Kopieren'),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () async {
                        final v = f['wert'] as num;
                        await Clipboard.setData(ClipboardData(
                            text: v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(2).replaceAll('.', ',')));
                        HapticFeedback.selectionClick();
                      },
                    )
                  : null,
            ),
        ],
      );

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
        child: Text(tr('Trag dein Brutto ein oder fotografiere die Lohnsteuerbescheinigung, dann rechnet Ahead die Erstattung aus.'),
            style: TextStyle(color: AppColors.textDim, height: 1.4)),
      );

  String _band(({double low, double high}) b) => b.high < 1
      ? Money.format(0)
      : (b.high - b.low) < 20
          ? Money.format((b.high * 100).round())
          : '${Money.format((b.low * 100).round())} – ${Money.format((b.high * 100).round())}';

  Widget _result(TaxResult r, ({double low, double high}) band) {
    final color = band.high >= 1 ? AppColors.positive : AppColors.textDim;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(band.high >= 1 ? tr('Kommt voraussichtlich zurück') : tr('Voraussichtlich keine Erstattung'),
            style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(_band(band),
              style: TextStyle(
                  fontFamily: AppFonts.display, fontSize: 34, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: color)),
        ),
        const SizedBox(height: 10),
        _line(tr('Fahrten zur Arbeit'), r.commute),
        _line(tr('Homeoffice'), r.homeOffice),
        _line(tr('Belege'), r.receipts),
        _line(tr('Kontoführung, pauschal'), r.accountFee),
        _line(tr('Werbungskosten zusammen'), r.werbungskosten, bold: true),
        const SizedBox(height: 6),
        _line(tr('Lohnsteuer einbehalten'), r.withheld),
        _line(tr('Steuer fürs Jahr'), r.due),
        const SizedBox(height: 6),
        for (final n in TaxEstimate.reasons(_p, r, _year))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('• $n', style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4)),
          ),
        for (final n in r.notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(n, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4)),
          ),
      ]),
    );
  }

  // the notice is in: the real number, how close the estimate was, and the
  // objection period when less was accepted than claimed
  Widget _assessed(Assessment a, TaxResult? r) {
    final estimate = TaxEstimate.filedEstimate(_year);
    final until = TaxEstimate.objectionUntil(a.date);
    final open = !DateTime(_today.year, _today.month, _today.day).isAfter(until);
    final claimed = r?.werbungskosten;
    final short = claimed != null && a.werbungskosten != null && a.werbungskosten! + 50 < claimed;
    final good = a.refund >= 1;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: (good ? AppColors.positive : AppColors.textDim).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(good ? tr('Laut Bescheid zurück') : tr('Laut Bescheid'), style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(Money.format((a.refund * 100).round()),
            style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 34,
                fontWeight: FontWeight.w600,
                color: good ? AppColors.positiveText : null)),
        if (estimate != null)
          Text(tr('Geschätzt waren {x}.', {'x': Money.format((estimate * 100).round())}),
              style: TextStyle(color: AppColors.textDim)),
        if (short) ...[
          const SizedBox(height: 10),
          Text(
            tr('Das Finanzamt hat {a} Werbungskosten anerkannt, du hattest {c} angegeben. Prüf die Erläuterungen im Bescheid. Einspruch geht bis {d}.',
                {
                  'a': Money.format((a.werbungskosten! * 100).round()),
                  'c': Money.format((claimed * 100).round()),
                  'd': Dates.full(until)
                }),
            style: TextStyle(color: AppColors.warningText, height: 1.4, fontWeight: FontWeight.w600),
          ),
          if (open)
            TextButton(
              onPressed: () => _letter(
                  tr('Einspruch, Entwurf'),
                  TaxLetters.objection(
                      year: _year,
                      noticeDate: a.date,
                      claimed: claimed,
                      accepted: a.werbungskosten!,
                      name: AccountService.current.value?.firstName ?? '')),
              child: Text(tr('Einspruch-Entwurf ansehen')),
            ),
        ],
        if (good) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            key: const Key('tax-share'),
            onPressed: () => showShareCard(
                context,
                ShareCardData(
                  kicker: 'Ahead',
                  headline: tr('{x} vom Finanzamt zurück', {'x': Money.format((a.refund * 100).round())}),
                  body: tr('Steuererklärung {y} nachgeholt. Laut Bescheid, nicht geschätzt.', {'y': _year}),
                  text: tr('Ich hab mein Steuergeld für {y} zurückgeholt. Mach den Rückhol-Check mit Ahead.', {'y': _year}),
                )),
            icon: const Icon(Icons.ios_share_rounded, size: 18),
            label: Text(tr('Ergebnis teilen')),
          ),
        ],
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

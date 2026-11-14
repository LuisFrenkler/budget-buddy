import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../services/db.dart';
import '../services/goals_service.dart';
import '../services/money_accounts.dart';
import '../services/onboarding_service.dart';
import '../services/wealth.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../widgets/getting_started.dart';
import 'buddy_screen.dart';
import 'goals_screen.dart';
import '../l10n/l10n.dart';

// Notgroschen, Schulden, Versicherungen, the wealth bridge next to everyday money.
class WealthScreen extends StatefulWidget {
  const WealthScreen({super.key});

  @override
  State<WealthScreen> createState() => _WealthScreenState();
}

class _WealthScreenState extends State<WealthScreen> {
  @override
  Widget build(BuildContext context) {
    final tx = DB.getTx();
    final cash = DB.balanceOf(tx) + MoneyAccounts.openingTotal;
    final depot = DB.portfolioValue();
    final net = Wealth.netWorthCents(cashCents: cash, depotCents: depot);
    final emergency = Wealth.emergency(tx);
    final debts = Wealth.debts();
    final policies = Wealth.policies();
    final rate = Wealth.savingsRatePercent(tx);
    final runway = Wealth.runwayMonths(tx, cash);
    final hasNotgroschenGoal =
        GoalsService.all().any((g) => !g.reached && g.name.toLowerCase().contains('notgroschen'));

    return Scaffold(
      appBar: AppBar(title: Text(tr('Vermögen & Absicherung'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text(tr('Vom Alltag zum Polster'),
              style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(tr('Hier siehst du, was hinter dem Start-Vermögen steckt und was noch fehlt.'),
              style: TextStyle(color: AppColors.textDim, height: 1.35, fontSize: 13.5)),
          const SizedBox(height: 16),
          _balanceCard(cash, depot, net, runway),
          const SizedBox(height: 22),
          _section(tr('Sparquote')),
          if (rate == null)
            Text(tr('Sobald Einnahmen und Ausgaben über ein paar Monate da sind, erscheint hier dein Anteil.'),
                style: TextStyle(color: AppColors.textDim, height: 1.35))
          else ...[
            Text('$rate %', style: const TextStyle(fontFamily: AppFonts.display, fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            const SizedBox(height: 4),
            Text(tr('Einnahmen minus Ausgaben · letzte drei volle Monate (ohne laufenden Monat).'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
          ],
          const SizedBox(height: 22),
          _section(tr('Notgroschen')),
          _emergencyCard(emergency),
          const SizedBox(height: 8),
          TextButton(
            onPressed: emergency.targetCents <= 0 || hasNotgroschenGoal
                ? null
                : () => addGoal(context, name: tr('Notgroschen'), cents: emergency.targetCents),
            child: Text(hasNotgroschenGoal ? tr('Sparziel „Notgroschen“ existiert schon') : tr('Als Sparziel anlegen')),
          ),
          const SizedBox(height: 22),
          _section(tr('Schulden')),
          Text(tr('Dispo, Kreditkarte, Ratenkredit: Sie senken dein Nettovermögen auf dem Start.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          if (debts.isEmpty)
            _emptySection(
              Icons.credit_card_off_rounded,
              tr('Noch keine Schulden'),
              tr('Dispo, Kreditkarte oder Ratenkredit. Nur der Betrag, den du noch schuldest.'),
              onAdd: () => _editDebt(),
            ),
          for (final d in debts) _debtTile(d),
          TextButton.icon(
            onPressed: () => _editDebt(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr('Schuld hinzufügen')),
          ),
          const SizedBox(height: 22),
          _section(tr('Versicherungen')),
          Text(tr('Nur Inventar, keine Vermittlung. Damit du und Buddy Fixkosten siehst.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          if (policies.isEmpty)
            _emptySection(
              Icons.shield_outlined,
              tr('Noch keine Versicherungen'),
              tr('Nur dein Inventar, z. B. Haftpflicht, Hausrat, BU. Keine Vermittlung.'),
              onAdd: () => _editPolicy(),
            ),
          for (final p in policies) _policyTile(p),
          if (policies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(tr('Zusammen {x} / Monat', {'x': Money.format(Wealth.policyMonthly())}),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          TextButton.icon(
            onPressed: () => _editPolicy(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(tr('Versicherung hinzufügen')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => BuddyScreen.open(context,
                debts.isEmpty && policies.isEmpty
                    ? tr('Wie baue ich einen Notgroschen auf?')
                    : tr('Wie stehe ich bei Absicherung und Schulden da?')),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text(tr('Mit Buddy besprechen')),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(int cash, int depot, int net, int? runway) {
    final debts = Wealth.debtTotal();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Vermögensbilanz'), style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _line(tr('Konten'), Money.format(cash)),
        _line(tr('Depot'), Money.format(depot)),
        if (debts > 0) _line(tr('Schulden'), '− ${Money.format(debts)}'),
        Divider(color: AppColors.border, height: 20),
        Row(children: [
          Expanded(child: Text(tr('Netto'), style: TextStyle(fontWeight: FontWeight.w800))),
          Text(Money.format(net), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        if (runway != null) ...[
          const SizedBox(height: 8),
          Text(
            runway <= 0
                ? tr('Runway: Kontostand deckt kaum eine Monatsausgabe.')
                : tr('Runway: ca. {runway} {x} übliche Ausgaben auf dem Konto.', {'runway': runway, 'x': runway == 1 ? tr('Monat') : tr('Monate')}),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35),
          ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              foregroundColor: AppColors.primaryText,
            ),
            onPressed: () async {
              await showBalanceSheet(context);
              if (context.mounted) setState(() {});
            },
            child: Text(OnboardingService.balanceKnown
                ? tr('Kontostand aktualisieren')
                : tr('Kontostand eintragen')),
          ),
        ),
        Text(tr('Gleiche Berechnung wie auf Start (Konto + Depot − Schulden).'),
            style: TextStyle(color: AppColors.textDim, fontSize: 11.5, height: 1.3)),
      ]),
    );
  }

  Widget _emptySection(IconData icon, String title, String body, {required VoidCallback onAdd}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.65)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 20, color: AppColors.primaryText),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            ]),
            const SizedBox(height: 6),
            Text(body, style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: onAdd, child: Text(tr('Jetzt hinzufügen'))),
            ),
          ]),
        ),
      );

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );

  Widget _line(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: TextStyle(color: AppColors.textDim))),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _emergencyCard(EmergencyFund e) {
    if (e.targetCents <= 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Text(
          tr('Sobald Fixkosten oder Ausgaben erkennbar sind, schlägt Buddy einen Notgroschen vor (Richtwert: etwa 3× Monatsausgaben). Spar-Konten zählen mit, das Giro nicht.'),
          style: TextStyle(color: AppColors.textDim, height: 1.35),
        ),
      );
    }
    final color = e.ready ? AppColors.positive : AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(e.ready ? tr('Polster steht') : tr('Noch {x}', {'x': Money.format(e.missingCents)}),
                style: TextStyle(fontFamily: AppFonts.display, fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          ),
          TextButton(onPressed: _editExtra, child: Text(tr('Anpassen'))),
        ]),
        const SizedBox(height: 6),
        Text(tr('Ziel {x} · auf Sparkonto {x2}', {'x': Money.format(e.targetCents), 'x2': Money.format(e.haveCents)}),
            style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: e.progress,
            minHeight: 7,
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 8),
        Text(tr('Richtwert: 3× {x} Fix-/Monatskosten.', {'x': Money.format(e.fixedMonthlyCents)}),
            style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
      ]),
    );
  }

  Widget _debtTile(Debt d) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text(Money.format(d.cents), style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => _editDebt(existing: d),
      );

  Widget _policyTile(Policy p) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: Text('${Money.format(p.monthlyCents)}/Mon.', style: const TextStyle(fontWeight: FontWeight.w700)),
        onTap: () => _editPolicy(existing: p),
      );

  Future<void> _editExtra() async {
    final current = Wealth.emergencyExtraCents;
    final c = TextEditingController(text: current == 0 ? '' : (current / 100).round().toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Zusätzliches Polster')),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: tr('Bargeld / Tagesgeld außerhalb der App'),
            suffixText: '€',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Speichern'))),
        ],
      ),
    );
    if (ok != true) return;
    await Wealth.setEmergencyExtra(Money.parseToCents(c.text) ?? 0);
    if (mounted) setState(() {});
  }

  Future<void> _editDebt({Debt? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final amount = TextEditingController(
        text: existing == null ? '' : (existing.cents / 100).round().toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? tr('Schuld hinzufügen') : tr('Schuld bearbeiten')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Name')), autofocus: true),
          const SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Restschuld'), suffixText: '€'),
          ),
        ]),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(tr('Schuld löschen?')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: AppColors.error),
                          child: Text(tr('Löschen'))),
                    ],
                  ),
                );
                if (sure != true) return;
                final list = Wealth.debts()..removeWhere((x) => x.id == existing.id);
                await Wealth.saveDebts(list);
                if (context.mounted) Navigator.pop(context, false);
                if (mounted) setState(() {});
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text(tr('Löschen')),
            ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Speichern'))),
        ],
      ),
    );
    if (ok != true) return;
    final cents = Money.parseToCents(amount.text) ?? 0;
    final n = name.text.trim().isEmpty ? tr('Kredit') : name.text.trim();
    final list = Wealth.debts();
    if (existing != null) {
      final i = list.indexWhere((x) => x.id == existing.id);
      if (i >= 0) list[i] = Debt(id: existing.id, name: n, cents: cents);
    } else {
      list.add(Debt(id: const Uuid().v4(), name: n, cents: cents));
    }
    await Wealth.saveDebts(list);
    HapticFeedback.lightImpact();
    if (mounted) setState(() {});
  }

  Future<void> _editPolicy({Policy? existing}) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final amount = TextEditingController(
        text: existing == null ? '' : (existing.monthlyCents / 100).round().toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? tr('Versicherung') : tr('Bearbeiten')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: tr('Name')), autofocus: true),
          const SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: tr('Beitrag / Monat'), suffixText: '€'),
          ),
        ]),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(tr('Eintrag löschen?')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: AppColors.error),
                          child: Text(tr('Löschen'))),
                    ],
                  ),
                );
                if (sure != true) return;
                final list = Wealth.policies()..removeWhere((x) => x.id == existing.id);
                await Wealth.savePolicies(list);
                if (context.mounted) Navigator.pop(context, false);
                if (mounted) setState(() {});
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: Text(tr('Löschen')),
            ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Speichern'))),
        ],
      ),
    );
    if (ok != true) return;
    final cents = Money.parseToCents(amount.text) ?? 0;
    final n = name.text.trim().isEmpty ? tr('Versicherung') : name.text.trim();
    final list = Wealth.policies();
    if (existing != null) {
      final i = list.indexWhere((x) => x.id == existing.id);
      if (i >= 0) list[i] = Policy(id: existing.id, name: n, monthlyCents: cents);
    } else {
      list.add(Policy(id: const Uuid().v4(), name: n, monthlyCents: cents));
    }
    await Wealth.savePolicies(list);
    HapticFeedback.lightImpact();
    if (mounted) setState(() {});
  }
}

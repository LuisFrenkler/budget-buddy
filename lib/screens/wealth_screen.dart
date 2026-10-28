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

// Notgroschen, Schulden, Versicherungen — the wealth bridge next to everyday money.
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
      appBar: AppBar(title: const Text('Vermögen & Absicherung')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Text('Vom Alltag zum Polster',
              style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Hier siehst du, was hinter dem Start-Vermögen steckt — und was noch fehlt.',
              style: TextStyle(color: AppColors.textDim, height: 1.35, fontSize: 13.5)),
          const SizedBox(height: 16),
          _balanceCard(cash, depot, net, runway),
          const SizedBox(height: 22),
          _section('Sparquote'),
          if (rate == null)
            Text('Sobald Einnahmen und Ausgaben über ein paar Monate da sind, erscheint hier dein Anteil.',
                style: TextStyle(color: AppColors.textDim, height: 1.35))
          else ...[
            Text('$rate %', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
            const SizedBox(height: 4),
            Text('Einnahmen minus Ausgaben · letzte drei volle Monate (ohne laufenden Monat).',
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.35)),
          ],
          const SizedBox(height: 22),
          _section('Notgroschen'),
          _emergencyCard(emergency),
          const SizedBox(height: 8),
          TextButton(
            onPressed: emergency.targetCents <= 0 || hasNotgroschenGoal
                ? null
                : () => addGoal(context, name: 'Notgroschen', cents: emergency.targetCents),
            child: Text(hasNotgroschenGoal ? 'Sparziel „Notgroschen“ existiert schon' : 'Als Sparziel anlegen'),
          ),
          const SizedBox(height: 22),
          _section('Schulden'),
          Text('Dispo, Kreditkarte, Ratenkredit — senken dein Nettovermögen auf dem Start.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          if (debts.isEmpty)
            _emptySection(
              Icons.credit_card_off_rounded,
              'Noch keine Schulden',
              'Dispo, Kreditkarte oder Ratenkredit — nur der Betrag, den du noch schuldest.',
              onAdd: () => _editDebt(),
            ),
          for (final d in debts) _debtTile(d),
          TextButton.icon(
            onPressed: () => _editDebt(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Schuld hinzufügen'),
          ),
          const SizedBox(height: 22),
          _section('Versicherungen'),
          Text('Nur Inventar — keine Vermittlung. Damit du und Buddy Fixkosten siehst.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
          const SizedBox(height: 10),
          if (policies.isEmpty)
            _emptySection(
              Icons.shield_outlined,
              'Noch keine Versicherungen',
              'Nur dein Inventar — z. B. Haftpflicht, Hausrat, BU. Keine Vermittlung.',
              onAdd: () => _editPolicy(),
            ),
          for (final p in policies) _policyTile(p),
          if (policies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Zusammen ${Money.format(Wealth.policyMonthly())} / Monat',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          TextButton.icon(
            onPressed: () => _editPolicy(),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Versicherung hinzufügen'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => BuddyScreen.open(context,
                debts.isEmpty && policies.isEmpty
                    ? 'Wie baue ich einen Notgroschen auf?'
                    : 'Wie stehe ich bei Absicherung und Schulden da?'),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Mit Buddy besprechen'),
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
        Text('Vermögensbilanz', style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _line('Konten', Money.format(cash)),
        _line('Depot', Money.format(depot)),
        if (debts > 0) _line('Schulden', '− ${Money.format(debts)}'),
        Divider(color: AppColors.border, height: 20),
        Row(children: [
          const Expanded(child: Text('Netto', style: TextStyle(fontWeight: FontWeight.w800))),
          Text(Money.format(net), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        if (runway != null) ...[
          const SizedBox(height: 8),
          Text(
            runway <= 0
                ? 'Runway: Kontostand deckt kaum eine Monatsausgabe.'
                : 'Runway: ca. $runway ${runway == 1 ? 'Monat' : 'Monate'} übliche Ausgaben auf dem Konto.',
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
                ? 'Kontostand aktualisieren'
                : 'Kontostand eintragen'),
          ),
        ),
        Text('Gleiche Berechnung wie auf Start (Konto + Depot − Schulden).',
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
              child: TextButton(onPressed: onAdd, child: const Text('Jetzt hinzufügen')),
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
          'Sobald Fixkosten oder Ausgaben erkennbar sind, schlägt Buddy einen Notgroschen vor '
          '(Richtwert: etwa 3× Monatsausgaben). Spar-Konten zählen mit — das Giro nicht.',
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
            child: Text(e.ready ? 'Polster steht' : 'Noch ${Money.format(e.missingCents)}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          ),
          TextButton(onPressed: _editExtra, child: const Text('Anpassen')),
        ]),
        const SizedBox(height: 6),
        Text('Ziel ${Money.format(e.targetCents)} · auf Sparkonto ${Money.format(e.haveCents)}',
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
        Text('Richtwert: 3× ${Money.format(e.fixedMonthlyCents)} Fix-/Monatskosten.',
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
        title: const Text('Zusätzliches Polster'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Bargeld / Tagesgeld außerhalb der App',
            suffixText: '€',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
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
        title: Text(existing == null ? 'Schuld hinzufügen' : 'Schuld bearbeiten'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
          const SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Restschuld', suffixText: '€'),
          ),
        ]),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Schuld löschen?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: AppColors.error),
                          child: const Text('Löschen')),
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
              child: const Text('Löschen'),
            ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok != true) return;
    final cents = Money.parseToCents(amount.text) ?? 0;
    final n = name.text.trim().isEmpty ? 'Kredit' : name.text.trim();
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
        title: Text(existing == null ? 'Versicherung' : 'Bearbeiten'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), autofocus: true),
          const SizedBox(height: 10),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Beitrag / Monat', suffixText: '€'),
          ),
        ]),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () async {
                final sure = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Eintrag löschen?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
                      TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: TextButton.styleFrom(foregroundColor: AppColors.error),
                          child: const Text('Löschen')),
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
              child: const Text('Löschen'),
            ),
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Speichern')),
        ],
      ),
    );
    if (ok != true) return;
    final cents = Money.parseToCents(amount.text) ?? 0;
    final n = name.text.trim().isEmpty ? 'Versicherung' : name.text.trim();
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

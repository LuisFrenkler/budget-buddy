// Monats-Simulator: what-if on ForecastService, not persisted.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/contracts.dart';
import '../services/db.dart';
import '../services/forecast_service.dart';
import '../services/goals_service.dart';
import '../services/money_accounts.dart';
import '../services/scenario_service.dart';
import '../utils/merchant.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import '../l10n/l10n.dart';

Future<void> showScenarioSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (context) => const _ScenarioSheet(),
  );
}

class _ScenarioSheet extends StatefulWidget {
  const _ScenarioSheet();

  @override
  State<_ScenarioSheet> createState() => _ScenarioSheetState();
}

class _ScenarioSheetState extends State<_ScenarioSheet> {
  final _oneTime = TextEditingController();
  final _excluded = <String>{};
  int _goalsTrim = 0; // cents cut from baseline goals
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _oneTime.dispose();
    super.dispose();
  }

  void _kick() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final tx = DB.getTx();
    final goals = GoalsService.all();
    final cash = DB.balanceOf(tx) + MoneyAccounts.openingTotal;
    final contracts = Contracts.detect(tx);
    final baseGoals = goals
        .where((g) => !g.reached)
        .map((g) => g.monthlyCents > 0 ? g.monthlyCents : (g.monthlyNeeded(DateTime.now()) ?? 0))
        .fold<int>(0, (s, v) => s + v);
    final oneTime = Money.parseToCents(_oneTime.text) ?? 0;
    final o = ForecastOverrides(
      excludedContractKeys: {..._excluded},
      oneTimeSpentCents: oneTime < 0 ? 0 : oneTime,
      goalsMonthlyCents: baseGoals <= 0
          ? null
          : (baseGoals - _goalsTrim).clamp(0, baseGoals),
    );
    final cmp = ScenarioService.compare(tx,
        overrides: o, goals: goals, balanceCents: cash);
    final sim = cmp?.sim;
    final (color, label) = switch (sim?.pace ?? ForecastPace.relaxed) {
      ForecastPace.relaxed => (AppColors.positive, tr('Ruhiges Tempo')),
      ForecastPace.tight => (AppColors.warning, tr('Enger Spielraum')),
      ForecastPace.over => (AppColors.error, tr('Überzogen')),
    };

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Was wäre wenn…?'),
                style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(tr('Nur Rechnung, nichts wird gespeichert.'),
                style: TextStyle(color: AppColors.textDim, height: 1.35)),
            const SizedBox(height: 16),
            if (cmp != null) ...[
              Text(Money.format(cmp.sim.freeCents),
                  style: TextStyle(fontFamily: AppFonts.display, 
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: cmp.sim.freeCents < 0
                          ? AppColors.errorText
                          : AppColors.text)),
              const SizedBox(height: 4),
              Row(children: [
                Text(
                  cmp.deltaFree == 0
                      ? tr('wie heute')
                      : '${cmp.deltaFree > 0 ? '+' : ''}${Money.format(cmp.deltaFree)} vs. heute',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cmp.deltaFree > 0
                          ? AppColors.positiveText
                          : cmp.deltaFree < 0
                              ? AppColors.errorText
                              : AppColors.textDim),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ]),
              if (cmp.sim.freeCents > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(tr('etwa {x} pro Tag', {'x': Money.format(cmp.sim.perDayCents)}),
                      style: TextStyle(color: AppColors.textDim)),
                ),
            ] else
              Text(tr('Dafür brauche ich noch Einnahmen in den Buchungen.'),
                  style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 18),
            Text(tr('Abos diesen Monat auslassen'),
                style: TextStyle(
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const SizedBox(height: 6),
            if (contracts.isEmpty)
              Text(tr('Keine Verträge erkannt.'),
                  style: TextStyle(color: AppColors.textDim))
            else
              for (final c in contracts.take(8))
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name),
                  subtitle: Text('${Money.format(c.monthlyCents)} / Monat'),
                  value: _excluded.contains(Merchant.key(c.name)),
                  onChanged: (on) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      final k = Merchant.key(c.name);
                      on ? _excluded.add(k) : _excluded.remove(k);
                    });
                  },
                ),
            const SizedBox(height: 8),
            Text(tr('Einmalkauf'),
                style: TextStyle(
                    color: AppColors.textDim,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            const SizedBox(height: 6),
            TextField(
              controller: _oneTime,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'z. B. 89,00',
                suffixText: '€',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _kick(),
            ),
            if (baseGoals > 0) ...[
              const SizedBox(height: 14),
              Text(tr('Sparziele diesen Monat'),
                  style: TextStyle(
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              Row(children: [
                Expanded(
                  child: Text(_goalsTrim == 0
                      ? tr('Volle Rate ({x})', {'x': Money.format(baseGoals)})
                      : '− ${Money.format(_goalsTrim)} (noch ${Money.format(baseGoals - _goalsTrim)})'),
                ),
                IconButton(
                  onPressed: _goalsTrim >= baseGoals
                      ? null
                      : () => setState(() =>
                          _goalsTrim = (_goalsTrim + 1000).clamp(0, baseGoals)),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                IconButton(
                  onPressed: _goalsTrim <= 0
                      ? null
                      : () => setState(() =>
                          _goalsTrim = (_goalsTrim - 1000).clamp(0, baseGoals)),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ]),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

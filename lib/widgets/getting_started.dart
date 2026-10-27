import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../screens/budget_screen.dart';
import '../screens/connections_screen.dart';
import '../screens/goals_screen.dart';
import '../screens/smart_entry_sheet.dart';
import '../services/notification_service.dart';
import '../services/db.dart';
import '../services/onboarding_service.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// Asks for today's real account balance, so a hand-kept account shows the
// same number as the bank. Not offered while a bank is linked.
Future<void> showBalanceSheet(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (_) => const _BalanceSheet(),
  );
  if (ok == true && context.mounted) {
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Kontostand gespeichert')));
  }
}

class _BalanceSheet extends StatefulWidget {
  const _BalanceSheet();

  @override
  State<_BalanceSheet> createState() => _BalanceSheetState();
}

class _BalanceSheetState extends State<_BalanceSheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cents = Money.parseToCents(_amount.text);
    if (cents == null) {
      setState(() => _error = 'Bitte einen Betrag eingeben, z. B. 1.250,40');
      return;
    }
    await OnboardingService.setCurrentBalance(cents);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Wie viel ist gerade auf deinem Konto?',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.2)),
        const SizedBox(height: 6),
        Text('Schau kurz in deine Banking-App. Ab dann rechnet BudgetBuddy mit jeder Buchung weiter.',
            style: TextStyle(color: AppColors.textDim, height: 1.4)),
        const SizedBox(height: 18),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            hintText: '0,00',
            suffixText: '€',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _save,
          child: const Text('Speichern', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        TextButton.icon(
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
          },
          icon: const Icon(Icons.account_balance_rounded, size: 18),
          label: const Text('Lieber Bankkonto verbinden'),
        ),
      ]),
    );
  }
}

// "Erste Schritte" on the start screen: five short steps, each ticking
// itself off, with progress at the top. Disappears when done or hidden.
class GettingStartedCard extends StatelessWidget {
  const GettingStartedCard({super.key});

  static const _steps = {
    OnboardingStep.booking: (Icons.auto_awesome_rounded, 'Erste Ausgabe erfassen', 'Tipp einfach „Kaffee 3,20“'),
    OnboardingStep.balance: (Icons.account_balance_wallet_rounded, 'Kontostand eintragen', 'Oder Bankkonto verbinden'),
    OnboardingStep.budget: (Icons.speed_rounded, 'Ein Budget festlegen', 'z. B. 300 € für Essen im Monat'),
    OnboardingStep.goal: (Icons.flag_rounded, 'Ein Sparziel anlegen', 'Buddy rechnet dir den Plan aus'),
    OnboardingStep.notifications: (Icons.notifications_active_rounded, 'Mitteilungen erlauben', 'Buddy warnt, bevor es knapp wird'),
  };

  Future<void> _open(BuildContext context, OnboardingStep s) async {
    HapticFeedback.selectionClick();
    switch (s) {
      case OnboardingStep.booking:
        await showSmartEntry(context);
      case OnboardingStep.balance:
        await showBalanceSheet(context);
      case OnboardingStep.budget:
        showAddBudgetDialog(context);
      case OnboardingStep.goal:
        await addGoal(context);
      case OnboardingStep.notifications:
        final ok = await NotificationService.enable();
        if (ok) await NotificationService.hello();
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(duration: const Duration(milliseconds: 3500), content: Text(NotificationService.problem)));
        }
    }
  }

  // the card is const in its parents, so it listens to the data itself
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        for (final b in ['transactions', 'budgets', 'goals', 'settings']) Hive.box(b).listenable(),
        NotificationService.enabled,
      ]),
      builder: (context, _) => _card(context),
    );
  }

  Widget _card(BuildContext context) {
    if (OnboardingService.hidden) return const SizedBox.shrink();
    final done = OnboardingService.doneCount;
    final total = OnboardingStep.values.length;
    final complete = done == total;
    // the next open step is highlighted, so it is clear what to do now
    final next = OnboardingStep.values.where((s) => !OnboardingService.done(s)).firstOrNull;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 38,
            height: 38,
            child: Stack(alignment: Alignment.center, children: [
              CircularProgressIndicator(
                value: done / total,
                strokeWidth: 4,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(complete ? AppColors.positive : AppColors.primary),
              ),
              Text('$done', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(complete ? 'Alles eingerichtet 🎉' : 'Erste Schritte',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              Text(complete ? 'BudgetBuddy kennt jetzt alles, was es braucht.' : '$done von $total erledigt',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            ]),
          ),
          // before the first booking the steps are the whole Start screen: nothing to hide yet
          if (complete || DB.getTx().isNotEmpty)
            TextButton(
              onPressed: OnboardingService.hide,
              style: TextButton.styleFrom(foregroundColor: AppColors.textDim),
              child: Text(complete ? 'Fertig' : 'Ausblenden'),
            ),
        ]),
        if (!complete) ...[
          const SizedBox(height: 8),
          for (final s in OnboardingStep.values)
            _row(context, s, OnboardingService.done(s), s == next),
        ],
      ]),
    );
  }

  Widget _row(BuildContext context, OnboardingStep s, bool done, bool isNext) {
    final (icon, title, subtitle) = _steps[s]!;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: done ? null : () => _open(context, s),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: done
                  ? AppColors.positive
                  : isNext
                      ? AppColors.primary.withValues(alpha: 0.18)
                      : AppColors.surfaceAlt,
              shape: BoxShape.circle,
            ),
            child: Icon(done ? Icons.check_rounded : icon,
                size: 18, color: done ? Colors.black : (isNext ? AppColors.primary : AppColors.textDim)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: done ? AppColors.textDim : AppColors.text,
                    decoration: done ? TextDecoration.lineThrough : null,
                  )),
              if (!done) Text(subtitle, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ]),
          ),
          if (!done) Icon(Icons.chevron_right_rounded, color: isNext ? AppColors.primary : AppColors.textDim),
          const SizedBox(width: 6),
        ]),
      ),
    );
  }
}

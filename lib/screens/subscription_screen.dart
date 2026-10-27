import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/backend_service.dart';
import '../services/plus_service.dart';
import '../services/store_purchases.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'checkout_screen.dart';
import 'plus_screen.dart';
import 'about_screen.dart';
import '../legal/legal_texts.dart';

// "Mein Abo": status, plan, payment method, invoices, codes and cancelling,
// all in one place so nobody has to search for how to quit.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Subscription?>(
      valueListenable: PlusService.subscription,
      builder: (context, sub, _) => Scaffold(
        appBar: AppBar(title: const Text('Mein Abo')),
        body: sub == null ? _empty(context) : _Details(sub: sub),
      ),
    );
  }

  Widget _empty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🚀', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            const Text('Du nutzt BudgetBuddy gratis',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('Mit Plus gibt es Buddy, Belege und Sparziele ohne Limit.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => showPlus(context), child: const Text('Plus ansehen')),
          ]),
        ),
      );
}

class _Details extends StatelessWidget {
  final Subscription sub;
  const _Details({required this.sub});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final trial = sub.inTrial(now);
    final next = sub.periodEnd(now);
    final invoices = sub.invoices(now);
    final yearly = sub.plan == PlusPlan.yearly;
    final store = sub.fromStore;

    final status = sub.cancelled
        ? 'Gekündigt · läuft bis ${Dates.full(sub.endsAt!)}'
        : trial
            ? 'Gratis-Test · noch ${_daysLeft(now, sub.trialEnds)}'
            : 'Aktiv';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // the status card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: sub.cancelled
                ? null
                : const LinearGradient(
                    colors: AppColors.heroBrand, begin: Alignment.topLeft, end: Alignment.bottomRight),
            color: sub.cancelled ? AppColors.surface : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('✨', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Text('BudgetBuddy Plus',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: sub.cancelled ? AppColors.text : Colors.white)),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sub.cancelled ? AppColors.warning.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(status,
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: sub.cancelled ? AppColors.warning : Colors.white)),
            ),
            const SizedBox(height: 14),
            Text(
              sub.cancelled
                  ? 'Du behältst alles bis zum Ende. Danach geht es gratis weiter, deine Daten bleiben.'
                  : trial
                      ? 'Erste Zahlung am ${Dates.full(sub.trialEnds)}: ${PlusService.price(sub.plan)}. Vorher kündigen kostet nichts.'
                      : 'Nächste Zahlung am ${Dates.full(next)}: ${PlusService.price(sub.plan)}.',
              style: TextStyle(color: sub.cancelled ? AppColors.textDim : Colors.white70, fontSize: 13.5, height: 1.35),
            ),
          ]),
        ),

        _label('Abo'),
        _group([
          _row(
            icon: Icons.workspace_premium_rounded,
            title: yearly ? 'Jährlich' : 'Monatlich',
            subtitle: '${PlusService.price(sub.plan)} ${yearly ? 'im Jahr' : 'im Monat'}',
            trailing: yearly ? null : 'Sparen',
            onTap: sub.cancelled ? null : () => sub.managed ? _portal(context) : _choosePlan(context),
          ),
          _row(
            icon: Icons.event_rounded,
            title: sub.cancelled ? 'Endet am' : 'Nächste Zahlung',
            subtitle: sub.cancelled
                ? Dates.full(sub.endsAt!)
                : '${Dates.full(next)} · ${PlusService.price(sub.plan)}',
          ),
          _row(
            leading: MethodLogo(sub.method),
            title: 'Zahlungsmethode',
            subtitle: sub.methodText,
            onTap: () async {
              if (sub.managed) return _portal(context);
              if (await changePaymentMethod(context) && context.mounted) {
                _snack(context, 'Zahlungsmethode gespeichert');
              }
            },
          ),
        ]),

        _label('Rechnungen'),
        _group([
          if (sub.managed)
            _row(
              icon: Icons.receipt_long_rounded,
              title: 'Rechnungen ansehen',
              subtitle: store
                  ? 'Die Kaufbelege schickt dir ${StorePurchases.storeName} per E-Mail'
                  : 'Als PDF im Kundenportal von Stripe',
              onTap: () => _portal(context),
            )
          else if (invoices.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.receipt_long_rounded, color: AppColors.textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    sub.cancelled
                        ? 'Keine. Bei einer Kündigung im Test zahlst du nichts.'
                        : 'Noch keine. Die erste kommt am ${Dates.full(sub.trialEnds)}.',
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ),
              ]),
            )
          else
            for (final inv in invoices)
              _row(
                icon: Icons.receipt_long_rounded,
                title: Dates.full(inv.date),
                subtitle: inv.number,
                trailing: Money.raw(inv.cents),
                onTap: () => _showInvoice(context, inv),
              ),
        ]),

        _label('Mehr'),
        _group([
          // with a real payment a code is entered at checkout
          if (!sub.managed)
            _row(icon: Icons.redeem_rounded, title: 'Gutscheincode einlösen', onTap: () => _redeem(context)),
          _row(
            icon: Icons.restore_rounded,
            title: 'Käufe wiederherstellen',
            subtitle: 'Nach einem neuen Gerät oder einer Neuinstallation',
            onTap: () async {
              final found = await PlusService.restore();
              if (context.mounted) _snack(context, found ? 'Dein Plus-Abo ist aktiv' : 'Kein Abo gefunden');
            },
          ),
          if (sub.cancelled)
            _row(
              icon: Icons.replay_rounded,
              title: 'Abo fortsetzen',
              subtitle: 'Läuft dann einfach weiter wie bisher',
              onTap: () async {
                if (store) return StorePurchases.manage();
                if (!await _attempt(context, PlusService.resume)) return;
                HapticFeedback.mediumImpact();
                if (context.mounted) _snack(context, 'Schön, dass du bleibst 💜');
              },
            )
          else
            _row(
              icon: Icons.cancel_outlined,
              title: store ? 'Im ${StorePurchases.storeName} kündigen' : 'Vertrag hier kündigen',
              danger: true,
              onTap: () => store ? StorePurchases.manage() : _cancel(context, sub),
            ),
          if (PlusService.canWithdraw(sub))
            _row(
              icon: Icons.undo_rounded,
              title: store ? 'Erstattung anfragen' : 'Vertrag widerrufen',
              subtitle: store
                  ? 'Über Erstattungen von Käufen im ${StorePurchases.storeName} entscheidet der Store'
                  : 'Innerhalb von 14 Tagen nach Abschluss, ohne Angabe von Gründen',
              danger: true,
              onTap: () => store ? StorePurchases.requestRefund() : _withdraw(context, sub),
            ),
        ]),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: LegalTexts.terms))),
            child: const Text('Nutzungsbedingungen'),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          store
              ? 'Gekauft über ${StorePurchases.storeName}. Zahlung, Kündigung und Belege laufen über '
                  '${StorePurchases.platform == 'apple' ? 'deine Apple-ID' : 'dein Google-Konto'}.'
              : sub.managed
              ? 'Zahlung und Rechnungen laufen über unseren Zahlungsanbieter Stripe. '
                  'Deine Zahlungsdaten liegen nur dort.'
              : 'Testmodus: Es wurde und wird nichts abgebucht. Im Store-Release laufen Zahlung und '
                  'Rechnungen über App Store, Google Play oder unseren Zahlungsanbieter.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textDim, fontSize: 11.5),
        ),
      ],
    );
  }

  static String _daysLeft(DateTime now, DateTime end) {
    final days = DateTime(end.year, end.month, end.day).difference(DateTime(now.year, now.month, now.day)).inDays;
    return days <= 1 ? '1 Tag' : '$days Tage';
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8, left: 4),
        child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
      );

  Widget _group(List<Widget> rows) => Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 60, color: AppColors.border),
            rows[i],
          ],
        ]),
      );

  Widget _row({
    IconData? icon,
    Widget? leading,
    required String title,
    String? subtitle,
    String? trailing,
    VoidCallback? onTap,
    bool danger = false,
  }) {
    final color = danger ? AppColors.error : AppColors.primary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 32,
            child: leading != null
                ? FittedBox(child: leading)
                : Container(
                    height: 32,
                    decoration:
                        BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, color: color, size: 18),
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: TextStyle(fontWeight: FontWeight.w600, color: danger ? AppColors.errorText : AppColors.text)),
              if (subtitle != null)
                Text(subtitle,
                    style: TextStyle(color: AppColors.textDim, fontSize: 12), overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (trailing != null)
            Text(trailing,
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: trailing == 'Sparen' ? AppColors.positiveText : AppColors.text)),
          if (onTap != null && !danger) Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
        ]),
      ),
    );
  }

  static void _snack(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(text)));

  // runs a change that may go to the server; false (with a message) when it failed
  static Future<bool> _attempt(BuildContext context, Future<void> Function() change) async {
    try {
      await change();
      return true;
    } catch (e) {
      if (context.mounted) _snack(context, 'Das hat gerade nicht geklappt: $e');
      return false;
    }
  }

  // payment method, plan and invoices of a real subscription live at Stripe
  static Future<void> _portal(BuildContext context) async {
    if (PlusService.subscription.value?.fromStore == true) return StorePurchases.manage();
    try {
      final url = await BackendService.plusPortal();
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      // whatever changed there shows up here once the user is back
      await PlusService.syncWithServer(fresh: true);
    } catch (e) {
      if (context.mounted) _snack(context, 'Kundenportal gerade nicht erreichbar: $e');
    }
  }

  Future<void> _choosePlan(BuildContext context) async {
    final chosen = await showModalBottomSheet<PlusPlan>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Plan wechseln', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Der neue Preis gilt ab der nächsten Zahlung.', style: TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 16),
          for (final p in PlusPlan.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                      color: p == sub.plan ? AppColors.primary : AppColors.border, width: p == sub.plan ? 2 : 1),
                ),
                title: Text('${p == PlusPlan.yearly ? 'Jährlich' : 'Monatlich'} · ${PlusService.price(p)}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(p == PlusPlan.yearly
                    ? 'Nur ${PlusService.yearlyPerMonth} im Monat, du sparst 33 %'
                    : 'Monatlich kündbar'),
                trailing: p == sub.plan ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () => Navigator.pop(context, p),
              ),
            ),
        ]),
      ),
    );
    if (chosen == null || chosen == sub.plan) return;
    await PlusService.changePlan(chosen);
    HapticFeedback.mediumImpact();
    if (context.mounted) {
      _snack(context, chosen == PlusPlan.yearly ? 'Jährlich: du sparst ab jetzt 33 %' : 'Ab der nächsten Zahlung monatlich');
    }
  }

  Future<void> _showInvoice(BuildContext context, Invoice inv) {
    final net = (inv.cents / 1.19).round();
    Widget line(String a, String b, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Text(a, style: TextStyle(color: bold ? AppColors.text : AppColors.textDim)),
            const Spacer(),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
          ]),
        );
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Rechnung ${inv.number}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          line('Datum', Dates.full(inv.date)),
          line('Leistung', 'Plus ${inv.plan == PlusPlan.yearly ? 'jährlich' : 'monatlich'}'),
          line('Netto', Money.raw(net)),
          line('MwSt. 19 %', Money.raw(inv.cents - net)),
          Divider(color: AppColors.border),
          line('Gesamt', Money.raw(inv.cents), bold: true),
          const SizedBox(height: 8),
          Text('Testmodus: nicht abgebucht', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Schließen'))],
      ),
    );
  }

  Future<void> _redeem(BuildContext context) async {
    final ctrl = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Gutscheincode'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(hintText: 'z. B. FREUND', errorText: error),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            TextButton(
              onPressed: () async {
                if (await PlusService.redeem(ctrl.text)) {
                  if (context.mounted) Navigator.pop(context, true);
                } else {
                  setState(() => error = 'Diesen Code kennen wir nicht');
                }
              },
              child: const Text('Einlösen'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      HapticFeedback.heavyImpact();
      _snack(context, '${PlusService.promoDays(ctrl.text)} Tage gratis gutgeschrieben 🎁');
    }
  }

  // the legal withdrawal: ends Plus now; paid amounts come back
  Future<void> _withdraw(BuildContext context, Subscription sub) async {
    final paid = sub.invoices(DateTime.now()).isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Vertrag widerrufen?'),
        content: Text(paid
            ? 'Plus endet sofort. Bereits gezahlte Beträge erstatten wir dir binnen 14 Tagen, '
                'abzüglich des Anteils für die Zeit, in der du Plus schon genutzt hast.'
            : 'Plus endet sofort. Es entstehen keine Kosten.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Jetzt widerrufen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (!await _attempt(context, PlusService.withdraw)) return;
    HapticFeedback.mediumImpact();
    if (context.mounted) _snack(context, 'Widerruf bestätigt. Plus ist beendet.');
  }

  // honest, two taps, no maze; offers the cheaper plan only when it helps
  Future<void> _cancel(BuildContext context, Subscription sub) async {
    final now = DateTime.now();
    final end = sub.periodEnd(now);
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Plus kündigen?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            sub.inTrial(now)
                ? 'Du zahlst nichts. Plus bleibt bis ${Dates.full(end)} aktiv.'
                : 'Plus bleibt bis ${Dates.full(end)} aktiv, danach wird nichts mehr abgebucht.',
            style: TextStyle(color: AppColors.textDim, height: 1.35),
          ),
          const SizedBox(height: 16),
          Text('Danach gilt wieder', style: TextStyle(color: AppColors.textDim, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final t in [
            '${PlusService.freeAiQuestions} Fragen an Buddy im Monat',
            '${PlusService.freeReceiptScans} Belege im Monat',
            '${PlusService.freeGoals} Sparziel',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                Icon(Icons.remove_circle_outline_rounded, size: 18, color: AppColors.textDim),
                const SizedBox(width: 8),
                Text(t),
              ]),
            ),
          const SizedBox(height: 18),
          if (sub.plan == PlusPlan.monthly) ...[
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => Navigator.pop(context, 'yearly'),
              child: Text('Lieber jährlich: nur ${PlusService.yearlyPerMonth} im Monat'),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus behalten'),
          ),
          const SizedBox(height: 6),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Jetzt kündigen'),
          ),
        ]),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'yearly') {
      if (sub.managed) return _portal(context);
      await PlusService.changePlan(PlusPlan.yearly);
      if (context.mounted) _snack(context, 'Jährlich: du sparst ab jetzt 33 %');
    } else if (choice == 'cancel') {
      if (!await _attempt(context, PlusService.cancel)) return;
      HapticFeedback.mediumImpact();
      if (context.mounted) _snack(context, 'Gekündigt. Plus läuft noch bis ${Dates.full(end)}.');
    }
  }
}

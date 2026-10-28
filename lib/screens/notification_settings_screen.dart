import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/account_service.dart';
import '../services/backend_service.dart';
import '../services/notification_service.dart';
import '../utils/theme.dart';
import '../widgets/settings_list.dart';

// Mitteilungen: one main switch, then each topic on its own.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool _waReady = false;
  bool _waOn = false;
  bool _waBusy = false;

  @override
  void initState() {
    super.initState();
    _loadWhatsApp();
  }

  Future<void> _loadWhatsApp() async {
    if (AccountService.current.value == null) return;
    try {
      final status = await BackendService.whatsAppStatus();
      if (!mounted) return;
      setState(() {
        _waReady = status['configured'] == true;
        _waOn = status['optedIn'] == true;
      });
    } catch (_) {
      if (mounted) setState(() => _waReady = false);
    }
  }

  Future<void> _toggleWhatsApp(bool on) async {
    if (!on) {
      setState(() => _waBusy = true);
      try {
        await BackendService.whatsAppUnlink();
        if (!mounted) return;
        setState(() {
          _waOn = false;
          _waBusy = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _waBusy = false);
        _waError(e);
      }
      return;
    }
    final phone = await showDialog<String>(context: context, builder: (_) => const _WaPhoneDialog());
    if (phone == null || phone.trim().isEmpty || !mounted) return;
    setState(() => _waBusy = true);
    try {
      final res = await BackendService.whatsAppLink(phone.trim());
      if (!mounted) return;
      setState(() {
        _waOn = true;
        _waBusy = false;
      });
      final text = '${res['instructions'] ?? 'Freigabe gespeichert.'}';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('WhatsApp'),
          content: Text(text),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Verstanden'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _waBusy = false);
      _waError(e);
    }
  }

  void _waError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e is String ? e : 'Gerade nicht erreichbar.')),
    );
  }

  static IconData _icon(NotifyTopic t) => switch (t) {
        NotifyTopic.spending => Icons.speed_rounded,
        NotifyTopic.contracts => Icons.receipt_long_rounded,
        NotifyTopic.weekly => Icons.insights_rounded,
        NotifyTopic.account => Icons.workspace_premium_rounded,
      };

  Future<void> _toggle(bool on) async {
    if (!on) {
      await NotificationService.disable();
      return;
    }
    final ok = await NotificationService.enable();
    if (ok) {
      await NotificationService.hello();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 3500), content: Text(NotificationService.problem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mitteilungen')),
      body: ValueListenableBuilder<bool>(
        valueListenable: NotificationService.enabled,
        builder: (context, on, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text('Buddy meldet sich nur, wenn es wirklich zählt. Kein Spam, keine Werbung.',
                style: TextStyle(color: AppColors.textDim, height: 1.4)),
            const SizedBox(height: 16),
            SettingsGroup([
              SettingsRow(
                icon: on ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                title: 'Mitteilungen erlauben',
                // where it cannot work, the reason is shown instead of a switch that fails
                subtitle: !on && !NotificationService.canAsk
                    ? 'Hier gerade nicht möglich'
                    : null,
                trailing: Switch(value: on, onChanged: !on && !NotificationService.canAsk ? null : _toggle),
              ),
            ]),
            if (!on && !NotificationService.canAsk)
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
                child: Text(
                  kIsWeb
                      ? 'Dein Browser lässt BudgetBuddy keine Mitteilungen schicken. Du kannst das in den '
                          'Website-Einstellungen ändern (Schloss-Symbol neben der Adresse). Die Hinweise in der '
                          'App bekommst du trotzdem.'
                      : 'Erlaube Mitteilungen für BudgetBuddy in den Einstellungen deines Geräts. Die Hinweise in '
                          'der App bekommst du trotzdem.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
                ),
              ),
            const SectionLabel('Worüber Buddy Bescheid sagt'),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: on ? 1 : 0.45,
              child: IgnorePointer(
                ignoring: !on,
                child: SettingsGroup([
                  for (final t in NotifyTopic.values)
                    SettingsRow(
                      icon: _icon(t),
                      title: t.label,
                      subtitle: t.description,
                      trailing: Switch(
                        value: NotificationService.topic(t),
                        onChanged: (v) async {
                          await NotificationService.setTopic(t, v);
                          setState(() {});
                        },
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              kIsWeb
                  ? 'Im Browser: Hinweise nur, während BudgetBuddy offen ist. Geplante Erinnerungen '
                      '(z. B. Sonntag Wochenbericht, ablaufende Bank-Freigabe) gibt es in der iPhone- und Android-App.'
                  : 'Erinnerungen werden auf deinem Gerät geplant. Deine Daten gehen dafür an keinen Server.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
            ),
            const SectionLabel('WhatsApp'),
            Text(
              'Aus, bis du zustimmst. Versand über die WhatsApp Cloud API von Meta. Nur drei Arten, kein Spam '
              'und keine Werbung: Wochenbericht, Budget-Warnung, Split-Erinnerung. Deine Nummer speichern wir '
              'nicht im Klartext, nur einen Hash. Abmelden geht mit dem Schalter oder mit „Stop“ in WhatsApp.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            SettingsGroup([
              SettingsRow(
                icon: Icons.chat_rounded,
                title: 'Mitteilungen per WhatsApp',
                subtitle: _waReady ? (_waOn ? 'An — jederzeit abmeldbar' : 'Aus') : 'Bald / Server einrichten',
                trailing: Switch(
                  value: _waReady && _waOn,
                  onChanged: _waReady && !_waBusy ? _toggleWhatsApp : null,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _WaPhoneDialog extends StatefulWidget {
  const _WaPhoneDialog();

  @override
  State<_WaPhoneDialog> createState() => _WaPhoneDialogState();
}

class _WaPhoneDialogState extends State<_WaPhoneDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('WhatsApp-Nummer'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(labelText: 'Nummer', hintText: '+491701234567'),
        onSubmitted: (_) => Navigator.pop(context, _ctrl.text.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(context, _ctrl.text.trim()), child: const Text('Freigeben')),
      ],
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/account_service.dart';
import '../services/backend_service.dart';
import '../services/notification_service.dart';
import '../utils/theme.dart';
import '../widgets/settings_list.dart';
import '../l10n/l10n.dart';

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
          title: Text(tr('WhatsApp')),
          content: Text(text),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Verstanden')))],
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
      SnackBar(content: Text(e is String ? e : tr('Gerade nicht erreichbar.'))),
    );
  }

  static IconData _icon(NotifyTopic t) => switch (t) {
        NotifyTopic.spending => Icons.speed_rounded,
        NotifyTopic.contracts => Icons.receipt_long_rounded,
        NotifyTopic.weekly => Icons.insights_rounded,
        NotifyTopic.account => Icons.workspace_premium_rounded,
        NotifyTopic.buddy => Icons.auto_awesome_rounded,
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
      appBar: AppBar(title: Text(tr('Mitteilungen'))),
      body: ValueListenableBuilder<bool>(
        valueListenable: NotificationService.enabled,
        builder: (context, on, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Text(tr('Buddy meldet sich nur, wenn es zählt: höchstens einmal am Tag, dreimal pro Woche. Kein Spam, keine Werbung.'),
                style: TextStyle(color: AppColors.textDim, height: 1.4)),
            const SizedBox(height: 16),
            SettingsGroup([
              SettingsRow(
                icon: on ? Icons.notifications_active_rounded : Icons.notifications_off_outlined,
                title: tr('Mitteilungen erlauben'),
                // where it cannot work, the reason is shown instead of a switch that fails
                subtitle: !on && !NotificationService.canAsk
                    ? tr('Hier gerade nicht möglich')
                    : null,
                trailing: Switch(value: on, onChanged: !on && !NotificationService.canAsk ? null : _toggle),
              ),
            ]),
            if (!on && !NotificationService.canAsk)
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
                child: Text(
                  kIsWeb
                      ? tr('Dein Browser blockiert Mitteilungen. Änder das in den Website-Einstellungen (Schloss neben der Adresse). Hinweise in der App bleiben.')
                      : tr('Erlaube Mitteilungen für Ahead in den Geräteeinstellungen. Hinweise in der App bleiben.'),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
                ),
              ),
            SectionLabel(tr('Worüber Buddy Bescheid sagt')),
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
                  ? tr('Im Browser nur, solange Ahead offen ist. Geplante Erinnerungen (Wochenbericht, Bank-Freigabe) gibt es in der App.')
                  : tr('Erinnerungen plant dein Gerät. Dafür gehen keine Daten an einen Server.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
            ),
            SectionLabel(tr('WhatsApp')),
            Text(
              tr('Aus, bis du zustimmst. Versand über WhatsApp (Meta): Wochenbericht, Budget-Warnung, Split-Erinnerung. Kein Spam. Nummer nur als Hash. Abmelden per Schalter oder „Stop“.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            SettingsGroup([
              SettingsRow(
                icon: Icons.chat_rounded,
                title: tr('Mitteilungen per WhatsApp'),
                subtitle: _waReady ? (_waOn ? tr('An, jederzeit abmeldbar') : tr('Aus')) : tr('Bald / Server einrichten'),
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
      title: Text(tr('WhatsApp-Nummer')),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(labelText: tr('Nummer'), hintText: '+491701234567'),
        onSubmitted: (_) => Navigator.pop(context, _ctrl.text.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen'))),
        TextButton(onPressed: () => Navigator.pop(context, _ctrl.text.trim()), child: Text(tr('Freigeben'))),
      ],
    );
  }
}

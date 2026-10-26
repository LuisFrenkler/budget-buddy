import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
                  ? 'Im Browser kommen Hinweise, sobald BudgetBuddy sie bemerkt. Erinnerungen im Voraus, '
                      'etwa am Tag vor einer Abbuchung, gibt es in der App für iPhone und Android.'
                  : 'Erinnerungen werden auf deinem Gerät geplant. Deine Daten gehen dafür an keinen Server.',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

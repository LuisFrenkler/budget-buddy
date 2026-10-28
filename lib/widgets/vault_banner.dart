import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/cloud_sync.dart';
import '../utils/errors.dart';
import '../utils/theme.dart';

// Shown on every tab while the cloud vault could not be decrypted after login.
class VaultBanner extends StatelessWidget {
  const VaultBanner({super.key});

  static bool get failed =>
      Hive.isBoxOpen('settings') && Hive.box('settings').get('vaultLoadFailed') == true;

  static Future<String?> askPassword(BuildContext context) async {
    final ctrl = TextEditingController();
    final pw = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cloud laden'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
                'Das kann auf dem Handy ein paar Sekunden dauern — bitte warten.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Dein Passwort',
                hintText: 'Dasselbe wie beim Anmelden',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Ohne Cloud weiter')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Laden')),
        ],
      ),
    );
    ctrl.dispose();
    if (pw == null) return null;
    return pw;
  }

  static Future<void> retry(BuildContext context) async {
    HapticFeedback.selectionClick();
    final pw = await askPassword(context);
    if (pw == null || !context.mounted) return;
    if (pw.isEmpty) {
      await CloudSync.skipCloudForNow();
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Cloud wird geladen…'),
            ]),
          ),
        ),
      ),
    );
    Object? err;
    try {
      await CloudSync.loadAccountData(pw.trim());
    } catch (e) {
      err = e;
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!context.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(friendlyError(err)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Hive.isBoxOpen('settings')) return const SizedBox.shrink();
    return ValueListenableBuilder(
      valueListenable: Hive.box('settings').listenable(keys: const ['vaultLoadFailed']),
      builder: (context, _, __) {
        if (!failed) return const SizedBox.shrink();
        return Material(
          color: AppColors.error.withValues(alpha: 0.14),
          child: SafeArea(
            bottom: false,
            child: InkWell(
              onTap: () => retry(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(children: [
                  Icon(Icons.cloud_off_rounded, color: AppColors.errorText, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Kontodaten noch nicht geladen. Tippen zum erneuten Versuch — '
                      'bis dahin speichere ich nichts in die Cloud.',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.errorText,
                        height: 1.35,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

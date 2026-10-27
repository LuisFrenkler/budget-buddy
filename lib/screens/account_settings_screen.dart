import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/account_service.dart';
import '../services/plus_service.dart';
import '../services/store_purchases.dart';
import '../utils/password.dart';
import '../utils/theme.dart';
import '../widgets/settings_list.dart';
import 'auth_screens.dart';

// "Mein Konto": name, email, password, signing out and deleting the account.
class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Account?>(
      valueListenable: AccountService.current,
      builder: (context, account, _) => Scaffold(
        appBar: AppBar(title: const Text('Mein Konto')),
        body: account == null ? _guest(context) : _signedIn(context, account),
      ),
    );
  }

  Widget _guest(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_outline_rounded, size: 56, color: AppColors.textDim),
            const SizedBox(height: 12),
            const Text('Du nutzt BudgetBuddy als Gast',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('Mit einem Konto verbindest du deine Bank und meldest dich auf neuen Geräten an.',
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
              child: const Text('Konto erstellen'),
            ),
          ]),
        ),
      );

  Widget _signedIn(BuildContext context, Account account) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: AppColors.heroBrand, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Text(account.name.isEmpty ? '?' : account.name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 12),
        Center(child: Text(account.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        Center(child: Text(account.email, style: TextStyle(color: AppColors.textDim))),
        const SectionLabel('Persönliche Daten'),
        SettingsGroup([
          SettingsRow(
            icon: Icons.badge_outlined,
            title: 'Name',
            value: account.name,
            onTap: () => _edit(context, _NameForm(account.name), 'Name gespeichert'),
          ),
          SettingsRow(
            icon: Icons.alternate_email_rounded,
            title: 'E-Mail',
            value: account.email,
            onTap: () => _edit(context, _EmailForm(account.email), 'E-Mail geändert'),
          ),
        ]),
        const SectionLabel('Sicherheit'),
        SettingsGroup([
          SettingsRow(
            icon: Icons.lock_reset_rounded,
            title: 'Passwort ändern',
            subtitle: 'Meldet alle anderen Geräte ab',
            onTap: () => _edit(context, const _PasswordForm(), 'Passwort geändert. Andere Geräte sind abgemeldet.'),
          ),
        ]),
        const SectionLabel('Konto'),
        SettingsGroup([
          SettingsRow(icon: Icons.logout_rounded, title: 'Abmelden', onTap: () => logout(context)),
          SettingsRow(
            icon: Icons.person_remove_rounded,
            title: 'Konto löschen',
            subtitle: 'Mit allen Bankverbindungen, endgültig',
            danger: true,
            onTap: () => _delete(context),
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          'Dein Passwort speichern wir nur als unumkehrbaren Hash (bcrypt). Niemand bei BudgetBuddy kann es lesen.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, Widget form, String done) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => form,
    );
    if (ok == true && context.mounted) {
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(milliseconds: 2800), content: Text(done)));
    }
  }

  static Future<bool> _confirm(BuildContext context, String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  // also on Profil, where people look for it first
  static Future<void> logout(BuildContext context) async {
    if (!await _confirm(context, 'Abmelden?',
        'Deine Daten sind in deinem Konto gesichert. Hier und auf jedem anderen Gerät öffnest du sie, '
            'sobald du dich wieder anmeldest.',
        'Abmelden')) {
      return;
    }
    await AccountService.logout();
    if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  Future<void> _delete(BuildContext context) async {
    final plus = PlusService.subscription.value;
    // what happens to Plus depends on where it was bought
    final plusNote = plus == null || plus.cancelled
        ? ''
        : plus.fromStore
            ? '\n\nDein Plus-Abo läuft über ${StorePurchases.storeName} und endet nicht von selbst. '
                'Kündige es dort in den Abo-Einstellungen.'
            : plus.managed
                ? '\n\nDein Plus-Abo wird mit dem Konto gekündigt.'
                : '';
    final text = 'Dein Konto und alle Bankverbindungen werden dauerhaft gelöscht. '
        'Umsätze auf diesem Gerät bleiben, bis du sie unter Profil › „App zurücksetzen“ entfernst.$plusNote';
    if (!await _confirm(context, 'Konto löschen?', text, 'Endgültig löschen')) return;
    if (!context.mounted) return;
    // deleting takes a moment on the server: show that something happens
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await AccountService.deleteAccount();
      if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // the progress dialog
      final text = '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 3500),
          content: Text(RegExp(r'Exception|Error|Failed|Socket|Timeout').hasMatch(text)
              ? 'Löschen hat nicht geklappt: keine Verbindung zum Server. Bitte versuch es gleich noch einmal.'
              : text)));
    }
  }
}

// The frame shared by the three edit sheets: title, fields, error, save.
class _Sheet extends StatelessWidget {
  final String title;
  final String? text;
  final List<Widget> fields;
  final String? error;
  final bool busy;
  final VoidCallback onSave;

  const _Sheet({
    required this.title,
    this.text,
    required this.fields,
    required this.error,
    required this.busy,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        if (text != null) ...[
          const SizedBox(height: 4),
          Text(text!, style: TextStyle(color: AppColors.textDim)),
        ],
        const SizedBox(height: 16),
        ...fields,
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(error!, style: TextStyle(color: AppColors.errorText, fontSize: 13)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: busy ? null : onSave,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('Speichern', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }
}

// runs a save, shows the server's message on failure, closes on success
mixin _Saving<T extends StatefulWidget> on State<T> {
  String? error;
  bool busy = false;

  Future<void> save(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() => error = '$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _NameForm extends StatefulWidget {
  final String name;
  const _NameForm(this.name);

  @override
  State<_NameForm> createState() => _NameFormState();
}

class _NameFormState extends State<_NameForm> with _Saving {
  late final _name = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Name ändern',
        text: 'So spricht Buddy dich an.',
        error: error,
        busy: busy,
        onSave: () => save(() => AccountService.changeName(_name.text)),
        fields: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (_) => save(() => AccountService.changeName(_name.text)),
          ),
        ],
      );
}

class _EmailForm extends StatefulWidget {
  final String email;
  const _EmailForm(this.email);

  @override
  State<_EmailForm> createState() => _EmailFormState();
}

class _EmailFormState extends State<_EmailForm> with _Saving {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty) {
      setState(() => error = 'Bitte bestätige mit deinem Passwort.');
      return;
    }
    save(() => AccountService.changeEmail(_email.text, _password.text));
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'E-Mail ändern',
        text: 'Aktuell: ${widget.email}',
        error: error,
        busy: busy,
        onSave: _submit,
        fields: [
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Neue E-Mail'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Passwort zur Bestätigung',
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
        ],
      );
}

class _PasswordForm extends StatefulWidget {
  const _PasswordForm();

  @override
  State<_PasswordForm> createState() => _PasswordFormState();
}

class _PasswordFormState extends State<_PasswordForm> with _Saving {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  void _submit() {
    if (_next.text.length < 8) {
      setState(() => error = 'Das neue Passwort braucht mindestens 8 Zeichen.');
    } else if (_next.text != _repeat.text) {
      setState(() => error = 'Die beiden neuen Passwörter stimmen nicht überein.');
    } else {
      save(() => AccountService.changePassword(_current.text, _next.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (score, label) = passwordStrength(_next.text);
    final colors = [AppColors.error, AppColors.error, AppColors.warning, AppColors.positive, AppColors.positive];
    Widget field(TextEditingController c, String label, List<String> hints, {bool autofocus = false}) => TextField(
          controller: c,
          obscureText: _hide,
          autofocus: autofocus,
          autofillHints: hints,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label),
        );
    return _Sheet(
      title: 'Passwort ändern',
      text: 'Danach bleibst du hier angemeldet, alle anderen Geräte werden abgemeldet.',
      error: error,
      busy: busy,
      onSave: _submit,
      fields: [
        field(_current, 'Aktuelles Passwort', const [AutofillHints.password], autofocus: true),
        const SizedBox(height: 10),
        field(_next, 'Neues Passwort', const [AutofillHints.newPassword]),
        if (_next.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 0; i < 4; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: i < score ? colors[score] : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 12, color: colors[score], fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 10),
        field(_repeat, 'Neues Passwort wiederholen', const [AutofillHints.newPassword]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _hide = !_hide),
            icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
            label: Text(_hide ? 'Passwörter zeigen' : 'Passwörter verbergen'),
          ),
        ),
      ],
    );
  }
}


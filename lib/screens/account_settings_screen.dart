import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/account_service.dart';
import '../services/auth_service.dart';
import '../services/avatar_service.dart';
import '../services/plus_service.dart';
import '../services/settings_service.dart';
import '../services/store_purchases.dart';
import '../utils/password.dart';
import '../utils/theme.dart';
import '../widgets/settings_list.dart';
import '../widgets/user_avatar.dart';
import 'auth_screens.dart';
import '../l10n/l10n.dart';

// "Mein Konto": name, email, password, signing out and deleting the account.
class AccountSettingsScreen extends StatelessWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Account?>(
      valueListenable: AccountService.current,
      builder: (context, account, _) => Scaffold(
        appBar: AppBar(title: Text(tr('Mein Konto'))),
        body: account == null ? _signedOut(context) : _signedIn(context, account),
      ),
    );
  }

  Widget _signedOut(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_outline_rounded, size: 56, color: AppColors.textDim),
            const SizedBox(height: 12),
            Text(tr('Nicht angemeldet'),
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(tr('Melde dich an, um Bank und Depot zu verbinden und deine Daten zu sichern.'),
                textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInScreen())),
              child: Text(tr('Anmelden')),
            ),
            TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
              child: Text(tr('Konto erstellen')),
            ),
          ]),
        ),
      );

  Widget _signedIn(BuildContext context, Account account) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Center(
          child: GestureDetector(
            onTap: () => _changeAvatar(context),
            child: Stack(alignment: Alignment.bottomRight, children: [
              UserAvatar(name: account.name, size: 84, fontSize: 34),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                child: Icon(Icons.camera_alt_rounded, size: 14, color: AppColors.onPrimary),
              ),
            ]),
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => _changeAvatar(context),
            child: Text(tr('Profilbild ändern')),
          ),
        ),
        Center(child: Text(account.name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
        Center(child: Text(account.email, style: TextStyle(color: AppColors.textDim))),
        SectionLabel(tr('Persönliche Daten')),
        SettingsGroup([
          SettingsRow(
            icon: Icons.badge_outlined,
            title: tr('Name'),
            value: account.name,
            onTap: () => _edit(context, _NameForm(account.name), tr('Name gespeichert')),
          ),
          SettingsRow(
            icon: Icons.alternate_email_rounded,
            title: tr('E-Mail'),
            value: account.email,
            onTap: () => _edit(context, _EmailForm(account.email), tr('E-Mail geändert')),
          ),
        ]),
        SectionLabel(tr('Sicherheit')),
        SettingsGroup([
          _AppLockRow(),
          SettingsRow(
            icon: Icons.phonelink_lock_rounded,
            title: tr('Zwei-Faktor'),
            subtitle: account.totp ? tr('Aktiv · Code aus der Authenticator-App') : tr('Optional · schützt die Anmeldung'),
            onTap: () => _edit(
              context,
              account.totp ? _TotpDisableForm() : _TotpEnrollForm(),
              account.totp ? tr('Zwei-Faktor ist aus.') : tr('Zwei-Faktor ist aktiv. Andere Geräte sind abgemeldet.'),
            ),
          ),
          SettingsRow(
            icon: Icons.devices_rounded,
            title: tr('Angemeldete Geräte'),
            subtitle: tr('Einzeln abmelden oder alle'),
            onTap: () => _sessions(context),
          ),
          SettingsRow(
            icon: Icons.lock_reset_rounded,
            title: tr('Passwort ändern'),
            subtitle: tr('Meldet alle anderen Geräte ab'),
            onTap: () => _edit(context, _PasswordForm(), tr('Passwort geändert. Andere Geräte sind abgemeldet.')),
          ),
        ]),
        SectionLabel(tr('Konto')),
        SettingsGroup([
          SettingsRow(icon: Icons.logout_rounded, title: tr('Abmelden'), onTap: () => logout(context)),
          SettingsRow(
            icon: Icons.person_remove_rounded,
            title: tr('Konto löschen'),
            subtitle: tr('Mit allen Bankverbindungen, endgültig'),
            danger: true,
            onTap: () => deleteAccount(context),
          ),
        ]),
        SizedBox(height: 16),
        Text(
          tr('Umsätze in der Cloud sind mit deinem Passwort verschlüsselt, Ahead kann sie nicht lesen. Die App-Sperre schützt nur die Anzeige auf diesem Gerät.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _changeAvatar(BuildContext context) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(Icons.photo_library_outlined),
            title: Text(tr('Foto wählen')),
            onTap: () => Navigator.pop(context, 'pick'),
          ),
          if (AvatarService.bytes() != null)
            ListTile(
              leading: Icon(Icons.delete_outline_rounded),
              title: Text(tr('Entfernen')),
              onTap: () => Navigator.pop(context, 'clear'),
            ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      if (choice == 'clear') {
        await AvatarService.clear();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Profilbild entfernt'))));
        }
        return;
      }
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      final file = result?.files.single;
      if (file?.bytes == null) return;
      await AvatarService.set(file!.bytes!);
      if (context.mounted) {
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Profilbild gespeichert'))));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: Duration(milliseconds: 2800), content: Text(done)));
    }
  }

  Future<void> _sessions(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _SessionsSheet(),
    );
  }

  static Future<bool> _confirm(BuildContext context, String title, String text, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Abbrechen'))),
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
    if (!await _confirm(context, tr('Abmelden?'),
        tr('Auf diesem Gerät werden die Finanzdaten gelöscht. Wenn die Cloud-Sicherung geklappt hat, holst du sie mit dem nächsten Login zurück, sonst sind nur die Daten auf anderen Geräten noch da.'),
        tr('Abmelden'))) {
      return;
    }
    await AccountService.logout();
    if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
  }

  static Future<void> deleteAccount(BuildContext context) async {
    final plus = PlusService.subscription.value;
    // what happens to Plus depends on where it was bought
    final plusNote = plus == null || plus.cancelled
        ? ''
        : plus.fromStore
            ? tr('\n\nDein Plus-Abo läuft über {storeName} und endet nicht von selbst. Kündige es dort in den Abo-Einstellungen.', {'storeName': StorePurchases.storeName})
            : plus.managed
                ? tr('\n\nDein Plus-Abo wird mit dem Konto gekündigt.')
                : '';
    final text = tr('Dein Konto, alle Bankverbindungen und die Sicherung in der Cloud werden dauerhaft gelöscht, auch die Umsätze auf diesem Gerät.{plusNote}', {'plusNote': plusNote});
    if (!await _confirm(context, tr('Konto löschen?'), text, tr('Weiter'))) return;
    if (!context.mounted) return;
    final password = await _askPassword(context);
    if (password == null || password.trim().isEmpty) return;
    if (!context.mounted) return;
    // deleting takes a moment on the server: show that something happens
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(child: CircularProgressIndicator()),
    );
    try {
      await AccountService.deleteAccount(password);
      if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // the progress dialog
      final text = '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: Duration(milliseconds: 3500),
          content: Text(RegExp(r'Exception|Error|Failed|Socket|Timeout').hasMatch(text)
              ? tr('Löschen hat nicht geklappt: keine Verbindung zum Server. Bitte versuch es gleich noch einmal.')
              : text)));
    }
  }

  static Future<String?> _askPassword(BuildContext context) => showDialog<String>(
        context: context,
        builder: (context) => _PasswordConfirmDialog(),
      );
}

// owns its TextEditingController so it is not disposed while the dialog still animates
class _PasswordConfirmDialog extends StatefulWidget {
  _PasswordConfirmDialog();

  @override
  State<_PasswordConfirmDialog> createState() => _PasswordConfirmDialogState();
}

class _PasswordConfirmDialogState extends State<_PasswordConfirmDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Passwort bestätigen')),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(labelText: tr('Aktuelles Passwort')),
        onSubmitted: (_) => Navigator.pop(context, _ctrl.text),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Abbrechen'))),
        TextButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(tr('Endgültig löschen')),
        ),
      ],
    );
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
  final String? action;

  _Sheet({
    required this.title,
    this.text,
    required this.fields,
    required this.error,
    required this.busy,
    required this.onSave,
    this.action,
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
              : Text(action ?? tr('Speichern'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
        title: tr('Name ändern'),
        text: tr('So spricht Buddy dich an.'),
        error: error,
        busy: busy,
        onSave: () => save(() => AccountService.changeName(_name.text)),
        fields: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: tr('Name')),
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
      setState(() => error = tr('Bitte bestätige mit deinem Passwort.'));
      return;
    }
    save(() => AccountService.changeEmail(_email.text, _password.text));
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: tr('E-Mail ändern'),
        text: tr('Aktuell: {email}', {'email': widget.email}),
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
            decoration: InputDecoration(labelText: tr('Neue E-Mail')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _password,
            obscureText: _hide,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: tr('Passwort zur Bestätigung'),
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
      setState(() => error = tr('Das neue Passwort braucht mindestens 8 Zeichen.'));
    } else if (_next.text != _repeat.text) {
      setState(() => error = tr('Die beiden neuen Passwörter stimmen nicht überein.'));
    } else {
      save(() => AccountService.changePassword(_current.text, _next.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final (score, label) = passwordStrength(_next.text);
    final colors = passwordStrengthScale;
    Widget field(TextEditingController c, String label, List<String> hints, {bool autofocus = false}) => TextField(
          controller: c,
          obscureText: _hide,
          autofocus: autofocus,
          autofillHints: hints,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label),
        );
    return _Sheet(
      title: tr('Passwort ändern'),
      text: tr('Danach bleibst du hier angemeldet, alle anderen Geräte werden abgemeldet. Merke dir das neue Passwort gut: Es verschlüsselt die Cloud-Sicherung. Vergisst du es, ist die Kopie nicht mehr lesbar.'),
      error: error,
      busy: busy,
      onSave: _submit,
      fields: [
        field(_current, tr('Aktuelles Passwort'), const [AutofillHints.password], autofocus: true),
        const SizedBox(height: 10),
        field(_next, tr('Neues Passwort'), const [AutofillHints.newPassword]),
        if (_next.text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            for (var i = 1; i <= 4; i++)
              Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i < 4 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: score >= i ? colors[score] : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            const SizedBox(width: 12),
            Text(_next.text.length < 8 ? tr('Min. 8 Zeichen') : label,
                style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 10),
        field(_repeat, tr('Neues Passwort wiederholen'), const [AutofillHints.newPassword]),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _hide = !_hide),
            icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18),
            label: Text(_hide ? tr('Passwörter zeigen') : tr('Passwörter verbergen')),
          ),
        ),
      ],
    );
  }
}

class _AppLockRow extends StatefulWidget {
  const _AppLockRow();

  @override
  State<_AppLockRow> createState() => _AppLockRowState();
}

class _AppLockRowState extends State<_AppLockRow> {
  String _hint = tr('Face ID, Fingerabdruck oder Gerätecode');

  @override
  void initState() {
    super.initState();
    AuthService.lockSubtitle().then((hint) {
      if (mounted) setState(() => _hint = hint);
    });
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      if (!await AuthService.isAvailable()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(tr('Auf diesem Gerät gibt es keine Biometrie und keinen Gerätecode.'))));
        }
        return;
      }
      final ok = await AuthService.authenticate(tr('App-Sperre aktivieren'));
      if (!ok) return;
    }
    await Settings.setAppLockEnabled(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => SettingsRow(
        icon: Icons.lock_rounded,
        title: tr('App-Sperre'),
        subtitle: tr('{hint} · nur dieses Gerät', {'hint': _hint}),
        onTap: () => _toggle(!Settings.appLockEnabled),
        trailing: IgnorePointer(
          child: Switch(value: Settings.appLockEnabled, onChanged: (_) {}),
        ),
      );
}

class _TotpEnrollForm extends StatefulWidget {
  const _TotpEnrollForm();

  @override
  State<_TotpEnrollForm> createState() => _TotpEnrollFormState();
}

class _TotpEnrollFormState extends State<_TotpEnrollForm> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  String? _secret;
  String? error;
  bool busy = false;
  bool _hide = true;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_password.text.isEmpty) {
      setState(() => error = tr('Bitte bestätige mit deinem Passwort.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final setup = await AccountService.beginTotp(_password.text);
      if (mounted) setState(() => _secret = setup.secret);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_code.text.trim().length < 6) {
      setState(() => error = tr('Der Code hat 6 Ziffern.'));
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await AccountService.confirmTotp(_code.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _grouped(String secret) {
    final out = StringBuffer();
    for (var i = 0; i < secret.length; i++) {
      if (i > 0 && i % 4 == 0) out.write(' ');
      out.write(secret[i]);
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    final secret = _secret;
    return _Sheet(
      title: tr('Zwei-Faktor'),
      action: secret == null ? tr('Weiter') : tr('Aktivieren'),
      text: secret == null
          ? tr('Der Code schützt nur die Anmeldung. Umsätze auf dem Gerät und in der Cloud bleiben mit deinem Passwort verschlüsselt. Ohne den Code kommst du nicht mehr rein. Ein Zurücksetzen per E-Mail gibt es noch nicht.')
          : tr('Trag den Schlüssel in deine Authenticator-App ein (Konto manuell hinzufügen) und gib den ersten Code ein. Andere Geräte werden abgemeldet.'),
      error: error,
      busy: busy,
      onSave: secret == null ? _start : _confirm,
      fields: [
        if (secret == null)
          TextField(
            controller: _password,
            obscureText: _hide,
            autofocus: true,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _start(),
            decoration: InputDecoration(
              labelText: tr('Passwort zur Bestätigung'),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          )
        else ...[
          SelectableText(_grouped(secret), style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w700)),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: secret));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Schlüssel kopiert'))));
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(tr('Schlüssel kopieren')),
            ),
          ),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: InputDecoration(labelText: tr('Code aus der App')),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ],
    );
  }
}

class _TotpDisableForm extends StatefulWidget {
  const _TotpDisableForm();

  @override
  State<_TotpDisableForm> createState() => _TotpDisableFormState();
}

class _TotpDisableFormState extends State<_TotpDisableForm> with _Saving {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_password.text.isEmpty || _code.text.trim().length < 6) {
      setState(() => error = tr('Passwort und den 6-stelligen Code, bitte.'));
      return;
    }
    save(() => AccountService.disableTotp(_password.text, _code.text));
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: tr('Zwei-Faktor ausschalten'),
        action: tr('Ausschalten'),
        text: tr('Danach reicht wieder das Passwort für die Anmeldung.'),
        error: error,
        busy: busy,
        onSave: _submit,
        fields: [
          TextField(
            controller: _password,
            obscureText: _hide,
            autofocus: true,
            decoration: InputDecoration(
              labelText: tr('Passwort'),
              suffixIcon: IconButton(
                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _code,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            decoration: InputDecoration(labelText: tr('Code aus der App')),
            onSubmitted: (_) => _submit(),
          ),
        ],
      );
}

class _SessionsSheet extends StatefulWidget {
  const _SessionsSheet();

  @override
  State<_SessionsSheet> createState() => _SessionsSheetState();
}

class _SessionsSheetState extends State<_SessionsSheet> {
  List<DeviceSession>? _sessions;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await AccountService.sessions();
      if (mounted) setState(() => _sessions = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _when(String? iso) {
    final time = DateTime.tryParse(iso ?? '')?.toLocal();
    if (time == null) return tr('Angemeldet');
    final day = time.day.toString().padLeft(2, '0');
    final month = time.month.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$day.$month.${time.year}, $hour:$minute';
  }

  Future<void> _revoke(DeviceSession session) async {
    if (!await AccountSettingsScreen._confirm(
        context, tr('Gerät abmelden?'), tr('Die Anmeldung auf „{label}“ wird beendet.', {'label': session.label}), tr('Abmelden'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await AccountService.revokeSession(session.id);
      if (session.current) {
        await AccountService.logout();
        if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _all() async {
    if (!await AccountSettingsScreen._confirm(
        context,
        tr('Alle Geräte abmelden?'),
        tr('Jede Anmeldung endet, auch auf diesem Gerät. Die Daten hier werden gelöscht; die verschlüsselte Sicherung holst du mit dem nächsten Login zurück.'),
        tr('Alle abmelden'))) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await AccountService.logoutEverywhere();
      if (mounted) Navigator.popUntil(context, (route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Angemeldete Geräte'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(tr('Eine gestohlene Sitzung bleibt gültig, bis du sie hier beendest oder das Passwort änderst.'),
            style: TextStyle(color: AppColors.textDim)),
        const SizedBox(height: 12),
        if (_error != null) Text(_error!, style: TextStyle(color: AppColors.errorText, fontSize: 13)),
        if (sessions == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else
          for (final session in sessions)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(session.current && session.device.isNotEmpty ? tr('{label} · dieses Gerät', {'label': session.label}) : session.label),
              subtitle: Text(_when(session.createdAt)),
              trailing: _busy
                  ? null
                  : TextButton(onPressed: () => _revoke(session), child: Text(tr('Abmelden'))),
            ),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: _busy || sessions == null ? null : _all,
          child: Text(tr('Alle Geräte abmelden')),
        ),
      ]),
    );
  }
}


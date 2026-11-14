import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:url_launcher/url_launcher.dart';
import '../legal/legal_info.dart';
import '../services/cloud_sync.dart';
import '../services/account_service.dart';
import '../services/demo_data.dart';
import '../services/settings_service.dart';
import '../utils/errors.dart';
import '../utils/password.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import 'buddy_screen.dart';
import 'connections_screen.dart';
import 'about_screen.dart';
import '../legal/legal_texts.dart';
import '../l10n/l10n.dart';
import '../widgets/buddy_orb.dart';

// First screen for anyone not signed in: Buddy himself. The first message is
// useful without an account or a bank link; sign-up and sign-in sit in the
// header and come up in the chat once Buddy could do more with real numbers.
class WelcomeScreen extends StatelessWidget {
  WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => const BuddyScreen(guest: true);
}

// --- sign up ---

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  // a tappable legal page inside the consent sentence
  TextSpan _link(String text, LegalDoc doc) => TextSpan(
        text: text,
        style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w600),
        recognizer: TapGestureRecognizer()
          ..onTap = () => Navigator.push(context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: doc))),
      );

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;
  bool _accepted = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _valid =>
      _email.text.contains('@') && _password.text.length >= 8 && _name.text.trim().isNotEmpty && _accepted;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await AccountService.register(name: _name.text, email: _email.text, password: _password.text);
      // a new account starts its copy with what is on this device
      await CloudSync.unlock(account.id, _password.text);
      var backedUp = false;
      try {
        await CloudSync.push(required: true, force: true);
        backedUp = true;
      } catch (_) {
        // account exists; vault stays dirty and retries on the next change/start
      }
      await Settings.setOnboardingDone(true);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (!backedUp) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: Duration(milliseconds: 3200),
            content: Text(tr('Konto erstellt. Die Sicherung folgt, sobald die Verbindung steht.'))));
      }
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const StartChoiceScreen()));
    } catch (e) {
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // the same scale as when changing the password later
    final (strength, word) = passwordStrength(_password.text);
    final colors = passwordStrengthScale;
    return _AuthScaffold(
      title: tr('Konto erstellen'),
      subtitle: tr('Damit sind deine Bankverbindungen nur für dich sichtbar.'),
      children: [
        AutofillGroup(
          child: Column(children: [
            _Field(
                controller: _name, label: tr('Vorname'), hints: const [AutofillHints.givenName], onChanged: _refresh),
            const SizedBox(height: 12),
            _Field(
              controller: _email,
              label: tr('E-Mail'),
              keyboard: TextInputType.emailAddress,
              hints: const [AutofillHints.email],
              onChanged: _refresh,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _password,
              label: tr('Passwort'),
              obscure: _hide,
              hints: const [AutofillHints.newPassword],
              onChanged: _refresh,
              onSubmitted: (_) => _valid && !_busy ? _submit() : null,
              suffix: IconButton(
                tooltip: _hide ? tr('Passwort zeigen') : tr('Passwort verbergen'),
                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AppColors.textDim),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (int i = 1; i <= 4; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                margin: EdgeInsets.only(right: i < 4 ? 6 : 0),
                decoration: BoxDecoration(
                  color: strength >= i ? colors[strength] : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(_password.text.length < 8 ? tr('Min. 8 Zeichen') : word,
                style: TextStyle(fontSize: 12, color: AppColors.textDim)),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          tr('Wichtig: Dein Passwort verschlüsselt die Cloud-Sicherung. Vergisst du es, kann niemand, auch wir nicht, deine Daten wiederherstellen.'),
          style: TextStyle(fontSize: 12, color: AppColors.warningText, height: 1.35),
        ),
        const SizedBox(height: 18),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _accepted = !_accepted),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: tr('Ich akzeptiere die ')),
                    _link(tr('Nutzungsbedingungen'), LegalTexts.terms),
                    TextSpan(text: tr(' und habe die ')),
                    _link(tr('Datenschutzerklärung'), LegalTexts.privacy),
                    const TextSpan(text: ' gelesen.'),
                  ]),
                  style: TextStyle(fontSize: 13, color: AppColors.textDim, height: 1.4),
                ),
              ),
            ),
          ]),
        ),
        _ErrorText(_error),
        const SizedBox(height: 20),
        _PrimaryButton(tr('Konto erstellen'), busy: _busy, onPressed: _valid ? _submit : null),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () =>
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignInScreen())),
            child: Text(tr('Ich habe schon ein Konto')),
          ),
        ),
      ],
    );
  }

  void _refresh(String _) => setState(() => _error = null);
}

// --- sign in ---

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;
  String? _challenge;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _valid =>
      _challenge == null ? _email.text.contains('@') && _password.text.isNotEmpty : _code.text.length == 6;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_challenge == null) {
        await AccountService.login(email: _email.text, password: _password.text);
      } else {
        await AccountService.loginTotp(challenge: _challenge!, code: _code.text);
      }
      await Settings.setOnboardingDone(true);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      await _bringAccountData(_password.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.popUntil(context, (r) => r.isFirst);
    } on TotpRequired catch (e) {
      if (!mounted) return;
      setState(() {
        _challenge = e.challenge;
        _error = null;
      });
    } catch (e) {
      HapticFeedback.heavyImpact();
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // device is an empty cache after login, load this account's vault from the server
  Future<void> _bringAccountData(String password) async {
    try {
      await CloudSync.loadAccountData(password);
    } catch (e) {
      await Hive.box('settings').put('vaultLoadFailed', true);
      // wrong key / corrupt seal: drop the key so nothing can force-push an empty vault
      final msg = '$e';
      if (msg.contains('MAC') || msg.contains('SecretBox') || msg.contains('Invalid')) {
        await CloudSync.forget();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: Duration(milliseconds: 4200),
            content: Text(tr(
                'Deine gesicherten Daten konnten gerade nicht geladen werden. Schreib noch nichts. Tipp auf den roten Hinweis, um es erneut zu versuchen.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: _challenge == null ? tr('Willkommen zurück') : tr('Code eingeben'),
      subtitle: _challenge == null
          ? tr('Melde dich mit deiner E-Mail an.')
          : tr('Der Code aus der Authenticator-App schützt nur die Anmeldung. Deine Umsätze bleiben auf dem Gerät.'),
      children: [
        if (_challenge == null)
          AutofillGroup(
            child: Column(children: [
              _Field(
                controller: _email,
                label: tr('E-Mail'),
                keyboard: TextInputType.emailAddress,
                hints: const [AutofillHints.email],
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 12),
              _Field(
                controller: _password,
                label: tr('Passwort'),
                obscure: _hide,
                hints: const [AutofillHints.password],
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _valid && !_busy ? _submit() : null,
                suffix: IconButton(
                  icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AppColors.textDim),
                  onPressed: () => setState(() => _hide = !_hide),
                ),
              ),
            ]),
          )
        else
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _valid && !_busy ? _submit() : null,
            decoration: InputDecoration(labelText: tr('6-stelliger Code')),
          ),
        _ErrorText(_error),
        if (_challenge == null) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => showForgotPasswordSheet(context),
              child: Text(tr('Passwort vergessen?')),
            ),
          ),
          const SizedBox(height: 8),
        ] else
          const SizedBox(height: 24),
        _PrimaryButton(_challenge == null ? tr('Anmelden') : tr('Code prüfen'),
            busy: _busy, onPressed: _valid ? _submit : null),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _challenge == null
                ? () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignUpScreen()))
                : () => setState(() {
                      _challenge = null;
                      _code.clear();
                      _error = null;
                    }),
            child: Text(_challenge == null ? tr('Neu hier? Konto erstellen') : tr('Zurück zum Passwort')),
          ),
        ),
      ],
    );
  }
}

// Soft launch: no e-mail reset yet, be honest that the vault key is the password.
Future<void> showForgotPasswordSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.paddingOf(ctx).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Passwort vergessen'),
              style: TextStyle(
                  fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
          const SizedBox(height: 12),
          Text(
            tr('Es gibt keinen Reset-Link. Dein Passwort ist der Schlüssel zur Cloud-Sicherung. Niemand außer dir kann ihn ersetzen, auch wir nicht.'),
            style: TextStyle(fontSize: 15, color: AppColors.textDim, height: 1.45),
          ),
          const SizedBox(height: 12),
          Text(
            tr('Was du tun kannst:\n• Passwort noch einmal in Ruhe versuchen\n• Neues Konto anlegen und lokal neu starten\n• Bei Fragen zur Konto-Löschung schreib uns'),
            style: TextStyle(fontSize: 15, color: AppColors.text, height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Verstanden')),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () async {
              final uri = Uri(
                scheme: 'mailto',
                path: LegalInfo.email,
                query: 'subject=${Uri.encodeComponent('Ahead: Passwort / Konto')}',
              );
              Navigator.pop(ctx);
              if (!await launchUrl(uri) && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(tr('Schreib an {email}', {'email': LegalInfo.email}))),
                );
              }
            },
            child: Text(tr('E-Mail an Support')),
          ),
        ],
      ),
    ),
  );
}

// --- first start: how to fill the app ---

class StartChoiceScreen extends StatefulWidget {
  const StartChoiceScreen({super.key});

  @override
  State<StartChoiceScreen> createState() => _StartChoiceScreenState();
}

class _StartChoiceScreenState extends State<StartChoiceScreen> {
  bool _busy = false;

  Future<void> _finish({bool demo = false, bool bank = false, bool buddy = false}) async {
    setState(() => _busy = true);
    if (demo) await DemoData.load();
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    nav.popUntil((r) => r.isFirst);
    final shell = nav.context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!shell.mounted) return;
      if (bank) {
        Navigator.push(shell, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
      } else if (buddy) {
        // demo numbers + the one question that sells the coach
        BuddyScreen.ask.value = tr('Kann ich mir 800 € Urlaub leisten?');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final name = AccountService.current.value?.firstName;
    // Buddy asks from copper light, like on the landing page
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            CopperLight(
              child: Padding(
                padding: EdgeInsets.fromLTRB(24, MediaQuery.paddingOf(context).top + 32, 24, 26),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const BuddyOrb(size: 52, mood: BuddyMood.happy),
                  const SizedBox(height: 18),
                  Text(
                      name != null
                          ? tr('Schön, dass du da bist, {name}.', {'name': name})
                          : tr('Schön, dass du da bist.'),
                      style: const TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.3,
                          height: 1.02,
                          color: Color(0xFFFFF7F0))),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: CopperLight.card,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x1FFFFFFF)),
                    ),
                    child: Text(
                        tr('Wie wollen wir starten? Am schnellsten geht es mit mir im Chat. Die Bank kannst du jederzeit später verbinden.'),
                        style: const TextStyle(fontSize: 15.5, height: 1.45, color: Colors.white)),
                  ),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _ChoiceCard(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: tr('Mit Buddy loslegen'),
                  text: tr('Erzähl Buddy, was ansteht. Zahlen trägst du ein, wenn du magst, oder knipst einen Beleg.'),
                  badge: tr('Empfohlen'),
                  onTap: _busy ? null : () => _finish(),
                ),
                const SizedBox(height: 12),
                _ChoiceCard(
                  icon: Icons.account_balance_rounded,
                  title: tr('Bankkonto verbinden'),
                  text: tr('Login nur bei deiner Bank, nur Lesezugriff. Kontostand und Umsätze kommen automatisch.'),
                  onTap: _busy ? null : () => _finish(bank: true),
                ),
                const SizedBox(height: 12),
                _ChoiceCard(
                  icon: Icons.science_rounded,
                  title: tr('Mit Beispieldaten testen'),
                  text: tr('Mit Beispieldaten ausprobieren. Klar markiert und jederzeit entfernbar.'),
                  onTap: _busy ? null : () => _finish(demo: true, buddy: true),
                ),
                if (_busy)
                  const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

// --- shared pieces ---

class _AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;
  const _AuthScaffold({required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    // the title sits in copper light, like the landing page's opening
    return Scaffold(
      appBar: AppBar(
        backgroundColor: CopperLight.top,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            CopperLight(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: AppFonts.display,
                          fontSize: 36,
                          height: 1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.5,
                          color: Color(0xFFFFF7F0))),
                  const SizedBox(height: 10),
                  Text(subtitle, style: const TextStyle(fontSize: 16, color: Color(0xDBFFF7F0), height: 1.4)),
                ]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboard;
  final Iterable<String>? hints;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboard,
    this.hints,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      autofillHints: hints,
      autocorrect: false,
      enableSuggestions: !obscure,
      textInputAction: onSubmitted != null ? TextInputAction.done : TextInputAction.next,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(labelText: label, suffixIcon: suffix),
    );
  }
}

class _ErrorText extends StatelessWidget {
  final String? error;
  const _ErrorText(this.error);

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: error == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(error!, style: TextStyle(color: AppColors.errorText, fontSize: 14))),
              ]),
            ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const _PrimaryButton(this.label, {this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        disabledBackgroundColor: AppColors.surfaceAlt,
        disabledForegroundColor: AppColors.textDim,
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String? badge;
  final VoidCallback? onTap;
  const _ChoiceCard({required this.icon, required this.title, required this.text, this.badge, this.onTap});

  @override
  Widget build(BuildContext context) {
    final highlighted = badge != null;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: highlighted ? AppColors.brand.withValues(alpha: 0.7) : AppColors.border,
                width: highlighted ? 1.5 : 1),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: AppColors.brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                  if (highlighted) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(999)),
                      child: Text(badge!,
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
                const SizedBox(height: 4),
                Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.4)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

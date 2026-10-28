import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cloud_sync.dart';
import '../services/account_service.dart';
import '../services/db.dart';
import '../services/demo_data.dart';
import '../services/settings_service.dart';
import '../utils/password.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import 'connections_screen.dart';
import 'about_screen.dart';
import '../legal/legal_texts.dart';

// First screen for anyone not signed in: what the app does (a slowly
// turning carousel) and the three ways in. Replaces a separate intro, so a
// new user is one tap away from starting.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  int _page = 0;
  Timer? _auto;

  static const _slides = [
    (
      icon: Icons.account_balance_rounded,
      title: 'Dein Geld.\nEndlich klar.',
      text: 'Girokonto, Depot und Budgets in einer App. Verbunden in einer Minute.',
    ),
    (
      icon: Icons.receipt_long_rounded,
      title: 'Verträge und Abos\nim Blick.',
      text: 'BudgetBuddy erkennt feste Kosten von selbst und warnt, wenn etwas teurer wird.',
    ),
    (
      icon: Icons.shield_rounded,
      title: 'Sicher wie\ndeine Bank.',
      text: 'Login nur bei deiner Bank, reiner Lesezugriff, Sperre per Face ID.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_pages.hasClients) return;
      _pages.animateToPage((_page + 1) % _slides.length,
          duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _auto?.cancel();
    _pages.dispose();
    super.dispose();
  }

  void _open(Widget screen) => Navigator.push(context, MaterialPageRoute(builder: (_) => screen));

  Future<void> _tryWithoutAccount() async {
    HapticFeedback.selectionClick();
    await Settings.setOnboardingDone(true);
    if (!mounted) return;
    // a fresh install chooses how to start; returning users go straight in
    if (DB.getTx().isEmpty && DB.getHoldings().isEmpty) {
      _open(const StartChoiceScreen(guest: true));
    } else if (Settings.signedOutEmail.isNotEmpty) {
      // someone signed out: their data is not for whoever picks up the phone
      await _askToSignIn();
    } else {
      await Settings.setGuest(true);
    }
  }

  Future<void> _askToSignIn() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daten gehören zu einem Konto'),
        content: Text('Auf diesem Gerät liegen die Daten von ${Settings.signedOutEmail}. '
            'Melde dich an, um sie zu öffnen, oder lösch sie und starte neu ohne Konto.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'wipe'),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Löschen & neu starten'),
          ),
          TextButton(onPressed: () => Navigator.pop(context, 'signin'), child: const Text('Anmelden')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'signin') {
      _open(const SignInScreen());
    } else if (choice == 'wipe') {
      final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Wirklich alles löschen?'),
          content: const Text('Alle Umsätze, Budgets, Ziele und Depot-Positionen auf diesem Gerät sind dann weg. '
              'Das Konto selbst bleibt bestehen.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Abbrechen')),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Löschen'),
            ),
          ],
        ),
      );
      if (sure != true || !mounted) return;
      await DB.clearAll();
      await Settings.resetApp();
      await Settings.setOnboardingDone(true);
      if (mounted) _open(const StartChoiceScreen(guest: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // soft brand glow behind the headline
          Positioned(
            top: -160,
            left: -120,
            right: -120,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppColors.primary.withValues(alpha: 0.35),
                  AppColors.primary.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(children: [BrandMark(size: 40), SizedBox(width: 12), Wordmark(size: 22)]),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pages,
                    itemCount: _slides.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _slide(_slides[i]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      for (int i = 0; i < _slides.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.only(right: 6),
                          width: i == _page ? 22 : 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i == _page ? AppColors.primary : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                    ]),
                    const SizedBox(height: 28),
                    _PrimaryButton('Konto erstellen', onPressed: () => _open(const SignUpScreen())),
                    const SizedBox(height: 10),
                    _SecondaryButton('Ich habe schon ein Konto', onPressed: () => _open(const SignInScreen())),
                    const SizedBox(height: 6),
                    Center(
                      child: TextButton(
                        onPressed: _tryWithoutAccount,
                        child: Text('Ohne Konto ausprobieren', style: TextStyle(color: AppColors.textDim)),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // sits at the bottom like a title card; with large system text it scrolls
  // instead of overflowing
  Widget _slide(({IconData icon, String title, String text}) s) {
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: _slideBody(s),
        ),
      ),
    );
  }

  Widget _slideBody(({IconData icon, String title, String text}) s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration:
              BoxDecoration(color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
          child: Icon(s.icon, color: AppColors.primary, size: 28),
        ),
        const SizedBox(height: 24),
        Text(s.title,
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.08)),
        const SizedBox(height: 14),
        Text(s.text, style: TextStyle(fontSize: 17, color: AppColors.textDim, height: 1.45)),
        const SizedBox(height: 28),
      ],
    );
  }
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
      CloudSync.push().catchError((_) {});
      await Settings.setOnboardingDone(true);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      if (DB.getTx().isNotEmpty || DB.getHoldings().isNotEmpty) {
        // a guest with data signed up from inside the app: back to where they
        // were (Profil, Verbindungen, Buddy), no sample data on top of theirs
        final messenger = ScaffoldMessenger.of(context);
        Navigator.pop(context, true);
        messenger.showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 2800), content: Text('Konto erstellt. Deine Daten sind dabei.')));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const StartChoiceScreen()));
      }
    } catch (e) {
      setState(() => _error = '$e');
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
      title: 'Konto erstellen',
      subtitle: 'Damit sind deine Bankverbindungen nur für dich sichtbar.',
      children: [
        AutofillGroup(
          child: Column(children: [
            _Field(controller: _name, label: 'Vorname', hints: const [AutofillHints.givenName], onChanged: _refresh),
            const SizedBox(height: 12),
            _Field(
              controller: _email,
              label: 'E-Mail',
              keyboard: TextInputType.emailAddress,
              hints: const [AutofillHints.email],
              onChanged: _refresh,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _password,
              label: 'Passwort',
              obscure: _hide,
              hints: const [AutofillHints.newPassword],
              onChanged: _refresh,
              onSubmitted: (_) => _valid && !_busy ? _submit() : null,
              suffix: IconButton(
                tooltip: _hide ? 'Passwort zeigen' : 'Passwort verbergen',
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
            child: Text(_password.text.length < 8 ? 'Min. 8 Zeichen' : word,
                style: TextStyle(fontSize: 12, color: AppColors.textDim)),
          ),
        ]),
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
                    const TextSpan(text: 'Ich akzeptiere die '),
                    _link('Nutzungsbedingungen', LegalTexts.terms),
                    const TextSpan(text: ' und habe die '),
                    _link('Datenschutzerklärung', LegalTexts.privacy),
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
        _PrimaryButton('Konto erstellen', busy: _busy, onPressed: _valid ? _submit : null),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () =>
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignInScreen())),
            child: const Text('Ich habe schon ein Konto'),
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
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _valid => _email.text.contains('@') && _password.text.isNotEmpty;

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final account = await AccountService.login(email: _email.text, password: _password.text);
      await Settings.setOnboardingDone(true);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      await _bringAccountData(account, _password.text);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.popUntil(context, (r) => r.isFirst);
    } catch (e) {
      HapticFeedback.heavyImpact();
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // the account's data from its other devices; asks before it replaces
  // data of someone else (or a guest) on this device
  Future<void> _bringAccountData(Account account, String password) async {
    try {
      await CloudSync.unlock(account.id, password);
      final remote = await CloudSync.fetch();
      if (remote == null) return await CloudSync.push();
      final ownHere = (DB.getTx().isNotEmpty || DB.getHoldings().isNotEmpty) && !DemoData.active;
      if (ownHere && !CloudSync.ownsLocalData(account.id) && mounted) {
        final load = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Dein Konto hat schon Daten'),
            content: const Text('Auf diesem Gerät liegen andere Daten als in deinem Konto. '
                'Lädst du die Kontodaten, ersetzen sie die auf diesem Gerät. '
                'Behältst du die Gerätedaten, ersetzen sie die in deinem Konto.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Gerätedaten behalten')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kontodaten laden')),
            ],
          ),
        );
        if (load != true) return await CloudSync.push();
      }
      await CloudSync.apply(remote);
    } catch (_) {
      // signed in anyway; the data here stays and nothing is overwritten
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 3200),
            content: Text('Deine gesicherten Daten konnten gerade nicht geladen werden. Beim nächsten Start versuche ich es wieder.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Willkommen zurück',
      subtitle: 'Melde dich mit deiner E-Mail an.',
      children: [
        AutofillGroup(
          child: Column(children: [
            _Field(
              controller: _email,
              label: 'E-Mail',
              keyboard: TextInputType.emailAddress,
              hints: const [AutofillHints.email],
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            _Field(
              controller: _password,
              label: 'Passwort',
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
        ),
        _ErrorText(_error),
        const SizedBox(height: 24),
        _PrimaryButton('Anmelden', busy: _busy, onPressed: _valid ? _submit : null),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () =>
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
            child: const Text('Neu hier? Konto erstellen'),
          ),
        ),
      ],
    );
  }
}

// --- first start: how to fill the app ---

class StartChoiceScreen extends StatefulWidget {
  final bool guest;
  const StartChoiceScreen({super.key, this.guest = false});

  @override
  State<StartChoiceScreen> createState() => _StartChoiceScreenState();
}

class _StartChoiceScreenState extends State<StartChoiceScreen> {
  bool _busy = false;

  Future<void> _finish({bool demo = false, bool bank = false}) async {
    setState(() => _busy = true);
    if (demo) await DemoData.load();
    // for guests this flips the root from welcome to the app
    if (widget.guest) await Settings.setGuest(true);
    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
    if (bank) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectionsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = AccountService.current.value?.firstName;
    // a guest can still change their mind and go back to the welcome screen
    final canGoBack = widget.guest && Navigator.canPop(context);
    return Scaffold(
      appBar: canGoBack ? AppBar(backgroundColor: Colors.transparent, elevation: 0) : null,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, canGoBack ? 4 : 32, 24, 24),
          children: [
            Text(name != null ? 'Hallo $name 👋' : 'Los geht\'s 👋',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
            const SizedBox(height: 8),
            Text('Wie möchtest du starten?', style: TextStyle(fontSize: 17, color: AppColors.textDim)),
            const SizedBox(height: 28),
            if (!widget.guest) ...[
              _ChoiceCard(
                icon: Icons.account_balance_rounded,
                title: 'Bankkonto verbinden',
                text: 'Kontostand und Umsätze kommen automatisch. Dauert etwa eine Minute.',
                badge: 'Empfohlen',
                onTap: _busy ? null : () => _finish(bank: true),
              ),
              const SizedBox(height: 12),
            ],
            _ChoiceCard(
              icon: Icons.auto_awesome_rounded,
              title: 'Mit Beispieldaten',
              text: 'Sieh dir alle Funktionen mit einem halben Jahr Beispielfinanzen an.',
              onTap: _busy ? null : () => _finish(demo: true),
            ),
            const SizedBox(height: 12),
            _ChoiceCard(
              icon: Icons.edit_note_rounded,
              title: 'Selbst erfassen',
              text: 'Starte leer und trage Einnahmen und Ausgaben selbst ein.',
              onTap: _busy ? null : () => _finish(),
            ),
            if (widget.guest) ...[
              const SizedBox(height: 20),
              Text('Um dein Bankkonto zu verbinden, brauchst du ein Konto. Das geht später jederzeit im Profil.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.4)),
            ],
            if (_busy)
              const Padding(padding: EdgeInsets.only(top: 24), child: Center(child: CircularProgressIndicator())),
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
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(title, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
            const SizedBox(height: 8),
            Text(subtitle, style: TextStyle(fontSize: 16, color: AppColors.textDim, height: 1.4)),
            const SizedBox(height: 28),
            ...children,
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
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const _SecondaryButton(this.label, {this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        backgroundColor: AppColors.surfaceAlt,
        foregroundColor: AppColors.text,
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
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
            border: Border.all(color: highlighted ? AppColors.primary : Colors.transparent, width: 1.5),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: AppColors.primary),
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
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(999)),
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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/account_service.dart';
import '../services/db.dart';
import '../services/demo_data.dart';
import '../services/settings_service.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import 'connections_screen.dart';

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
    } else {
      await Settings.setGuest(true);
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

  Widget _slide(({IconData icon, String title, String text}) s) {
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

  // 0..3: length, mixed case, digit or symbol
  int get _strength {
    final p = _password.text;
    if (p.length < 8) return p.isEmpty ? 0 : 1;
    var s = 1;
    if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) s++;
    if (RegExp(r'[0-9\W_]').hasMatch(p)) s++;
    return s;
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
      await AccountService.register(name: _name.text, email: _email.text, password: _password.text);
      await Settings.setOnboardingDone(true);
      TextInput.finishAutofillContext();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const StartChoiceScreen()));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = _strength;
    const labels = ['', 'Schwach', 'Gut', 'Stark'];
    final colors = [AppColors.border, AppColors.error, AppColors.warning, AppColors.positive];
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
                icon: Icon(_hide ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AppColors.textDim),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (int i = 1; i <= 3; i++)
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                decoration: BoxDecoration(
                  color: strength >= i ? colors[strength] : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: Text(_password.text.length < 8 ? 'Min. 8 Zeichen' : labels[strength],
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
                child: Text('Ich akzeptiere die Nutzungsbedingungen und habe die Datenschutzerklärung gelesen.',
                    style: TextStyle(fontSize: 13, color: AppColors.textDim, height: 1.4)),
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
      await AccountService.login(email: _email.text, password: _password.text);
      await Settings.setOnboardingDone(true);
      TextInput.finishAutofillContext();
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
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
                Expanded(child: Text(error!, style: const TextStyle(color: AppColors.error, fontSize: 14))),
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

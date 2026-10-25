import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/account_service.dart';
import '../services/buddy_service.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import 'auth_screens.dart';

// Chat with Buddy, the finance coach that knows your numbers.
class BuddyScreen extends StatefulWidget {
  // asked right away, e.g. from a suggestion on the home screen
  final String? question;
  const BuddyScreen({super.key, this.question});

  static const suggestions = [
    (icon: Icons.savings_rounded, text: 'Wo kann ich sparen?'),
    (icon: Icons.donut_large_rounded, text: 'Wofür gebe ich am meisten aus?'),
    (icon: Icons.flight_takeoff_rounded, text: 'Kann ich mir 800 € Urlaub leisten?'),
    (icon: Icons.receipt_long_rounded, text: 'Welche Abos und Verträge habe ich?'),
  ];

  @override
  State<BuddyScreen> createState() => _BuddyScreenState();
}

class _BuddyScreenState extends State<BuddyScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];
  bool _thinking = false;
  bool? _live;
  StreamSubscription<String>? _sub;

  static Box get _settings => Hive.box('settings');

  @override
  void initState() {
    super.initState();
    BuddyService.live().then((v) {
      if (!mounted) return;
      setState(() => _live = v);
      if (widget.question != null) _send(widget.question!);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // the finance summary leaves the device only after the user agreed once
  Future<bool> _consent() async {
    if (_settings.get('aiConsent', defaultValue: false) == true) return true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const BuddyOrb(size: 48),
            const SizedBox(height: 16),
            const Text('Buddy mit KI nutzen?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'Damit Buddy deine Fragen beantworten kann, schickt BudgetBuddy eine Zusammenfassung deiner Finanzen '
              '(Summen je Monat und Kategorie, Budgets, Verträge, Händlernamen) an die KI von Anthropic. '
              'Keine Kontonummern, keine Zugangsdaten. Anthropic nutzt die Daten nicht zum Training.',
              style: TextStyle(color: AppColors.textDim, height: 1.45),
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Einverstanden'),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Nur offline antworten', style: TextStyle(color: AppColors.textDim)),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) await _settings.put('aiConsent', true);
    return ok == true;
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _thinking) return;
    HapticFeedback.selectionClick();
    var live = _live ?? false;
    if (live && !await _consent()) live = false;

    _input.clear();
    setState(() {
      _messages.add(_Message(true, question));
      _messages.add(_Message(false, '', offline: !live));
      _thinking = true;
    });
    _scrollDown();

    final history = [
      for (final m in _messages.sublist(0, _messages.length - 1))
        if (m.text.isNotEmpty) ChatMessage(m.fromUser, m.text)
    ];
    final answer = _messages.last;
    _sub = BuddyService.ask(history, live: live).listen(
      (piece) {
        setState(() => answer.text += piece);
        _scrollDown();
      },
      onError: (e) {
        HapticFeedback.heavyImpact();
        setState(() {
          answer.text = '$e';
          answer.error = true;
          _thinking = false;
        });
      },
      onDone: () {
        if (mounted) setState(() => _thinking = false);
        HapticFeedback.lightImpact();
      },
    );
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          BuddyOrb(size: 30, active: _thinking),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Buddy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Row(children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _live == true ? AppColors.positive : AppColors.textDim,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _live == null ? 'verbindet …' : (_live! ? 'KI-Finanzcoach' : 'Offline-Modus'),
                style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w500),
              ),
            ]),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(child: _messages.isEmpty ? _welcome() : _chat()),
        _inputBar(),
      ]),
    );
  }

  Widget _welcome() {
    final name = AccountService.current.value?.firstName;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      children: [
        const Center(child: BuddyOrb(size: 120)),
        const SizedBox(height: 32),
        Text(name != null ? 'Hi $name 👋' : 'Hi 👋',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1)),
        const SizedBox(height: 8),
        Text('Ich kenne deine Zahlen. Frag mich, was du über dein Geld wissen willst.',
            style: TextStyle(fontSize: 17, color: AppColors.textDim, height: 1.4)),
        const SizedBox(height: 24),
        for (final s in BuddyScreen.suggestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _send(s.text),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(children: [
                    Icon(s.icon, color: AppColors.primary, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(s.text, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Icon(Icons.north_east_rounded, color: AppColors.textDim, size: 18),
                  ]),
                ),
              ),
            ),
          ),
        if (_live == false) ...[
          const SizedBox(height: 8),
          _offlineHint(),
        ],
      ],
    );
  }

  Widget _offlineHint() {
    final guest = AccountService.current.value == null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.textDim),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            guest
                ? 'Offline-Modus: Buddy rechnet direkt auf deinem Gerät. Mit einem Konto antwortet er mit KI.'
                : 'Offline-Modus: Buddy rechnet direkt auf deinem Gerät, die KI ist gerade nicht verbunden.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35),
          ),
        ),
        if (guest)
          TextButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
            child: const Text('Konto'),
          ),
      ]),
    );
  }

  Widget _chat() {
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        if (m.fromUser) return _userBubble(m.text);
        final waiting = m.text.isEmpty && _thinking && i == _messages.length - 1;
        return _buddyBubble(m, waiting);
      },
    );
  }

  Widget _userBubble(String text) => Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 48, bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF8B6BFF), AppColors.primaryDeep]),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
        ),
      );

  Widget _buddyBubble(_Message m, bool waiting) {
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 4), child: BuddyOrb(size: 26, active: waiting)),
        const SizedBox(width: 10),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: m.error ? AppColors.error.withValues(alpha: 0.12) : AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: waiting ? const _TypingDots() : RichMarkdown(m.text),
            ),
            if (m.offline && m.text.isNotEmpty && !m.error)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text('Offline berechnet aus deinen Daten',
                    style: TextStyle(fontSize: 11, color: AppColors.textDim)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Frag Buddy …',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: _input.text.trim().isEmpty || _thinking ? 0.4 : 1,
              child: GestureDetector(
                onTap: () => _send(_input.text),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: AppColors.heroBrand),
                  ),
                  child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Buddy kann sich irren. Keine Anlage- oder Steuerberatung.',
              style: TextStyle(fontSize: 11, color: AppColors.textDim)),
        ]),
      ),
    );
  }
}

class _Message {
  final bool fromUser;
  String text;
  final bool offline;
  bool error = false;
  _Message(this.fromUser, this.text, {this.offline = false});
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (int i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(0, -4 * (1 - ((_c.value * 3 - i).abs() % 3).clamp(0.0, 1.0))),
              child: Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(color: AppColors.textDim, shape: BoxShape.circle),
              ),
            ),
        ]),
      ),
    );
  }
}

// The little markdown Buddy writes: **bold** and "- " bullet lines.
class RichMarkdown extends StatelessWidget {
  final String text;
  const RichMarkdown(this.text, {super.key});

  List<TextSpan> _spans(String line) {
    final spans = <TextSpan>[];
    final parts = line.split('**');
    for (int i = 0; i < parts.length; i++) {
      spans.add(TextSpan(
        text: parts[i],
        style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null,
      ));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(color: AppColors.text, fontSize: 15, height: 1.45);
    final lines = text.split('\n');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final raw in lines)
        if (raw.trim().isEmpty)
          const SizedBox(height: 6)
        else if (raw.trimLeft().startsWith('- ') || raw.trimLeft().startsWith('• '))
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8, left: 2),
                child: Container(
                    width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
              ),
              Expanded(child: Text.rich(TextSpan(children: _spans(raw.trimLeft().substring(2))), style: base)),
            ]),
          )
        else
          Text.rich(TextSpan(children: _spans(raw)), style: base),
    ]);
  }
}

// Entry on the home screen: Buddy's orb, a question that changes every few
// seconds, and two one-tap questions.
class BuddyCard extends StatefulWidget {
  const BuddyCard({super.key});

  @override
  State<BuddyCard> createState() => _BuddyCardState();
}

class _BuddyCardState extends State<BuddyCard> {
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _i = (_i + 1) % BuddyScreen.suggestions.length);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _open([String? question]) {
    HapticFeedback.selectionClick();
    Navigator.push(context, MaterialPageRoute(builder: (_) => BuddyScreen(question: question)));
  }

  @override
  Widget build(BuildContext context) {
    final s = BuddyScreen.suggestions;
    // a 1.5 px gradient border around the card
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [Color(0xFFA48BFF), Color(0xFF38BDF8), Color(0xFFF472B6)]),
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(20.5),
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const BuddyOrb(size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Frag Buddy', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                          child: child,
                        ),
                      ),
                      child: Text('„${s[_i].text}“',
                          key: ValueKey(_i),
                          style: TextStyle(color: AppColors.textDim, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
              ]),
              const SizedBox(height: 14),
              Row(children: [
                for (final q in s.take(2)) ...[
                  Expanded(
                    child: Material(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _open(q.text),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Row(children: [
                            Icon(q.icon, size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(q.text,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
                  if (q != s[1]) const SizedBox(width: 8),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

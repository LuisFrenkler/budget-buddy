import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/buddy_tips.dart';
import '../services/account_service.dart';
import '../services/buddy_service.dart';
import '../services/plus_service.dart';
import 'plus_screen.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import 'buddy_actions.dart';
import 'auth_screens.dart';
import 'about_screen.dart';
import '../legal/legal_texts.dart';

// Chat with Buddy, the finance coach that knows your numbers.
class BuddyScreen extends StatefulWidget {
  // asked right away, e.g. from a suggestion on the home screen
  final String? question;
  // the Buddy tab of the app shell: the one chat the rest of the app talks to
  final bool tab;
  const BuddyScreen({super.key, this.question, this.tab = false});

  // a question for the Buddy tab ('' just opens it); the shell switches to the tab
  static final ask = ValueNotifier<String?>(null);

  // from anywhere: back to the shell and on into the Buddy chat
  static void open(BuildContext context, [String? question]) {
    HapticFeedback.selectionClick();
    Navigator.popUntil(context, (r) => r.isFirst);
    ask.value = question ?? '';
  }

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
      if (widget.tab) _asked();
    });
    if (widget.tab) BuddyScreen.ask.addListener(_asked);
  }

  void _asked() {
    final q = BuddyScreen.ask.value;
    // until Buddy knows whether it is online, the question waits (initState asks again)
    if (q == null || _live == null) return;
    // cleared after this round, so the shell sees the question too
    WidgetsBinding.instance.addPostFrameCallback((_) => BuddyScreen.ask.value = null);
    if (q.isNotEmpty) _send(q);
  }

  @override
  void dispose() {
    if (widget.tab) BuddyScreen.ask.removeListener(_asked);
    _sub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // the finance summary leaves the device only after the user agreed once;
  // a "no" is remembered too (and both can be changed in Profil)
  Future<bool> _consent() async {
    final given = _settings.get('aiConsent');
    if (given == true) return true;
    if (given == false) return false;
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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: LegalTexts.privacy))),
                child: const Text('Datenschutzerklärung lesen'),
              ),
            ),
            const SizedBox(height: 8),
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
    // closing the sheet without choosing asks again next time
    if (ok != null) await _settings.put('aiConsent', ok);
    return ok == true;
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if (question.isEmpty || _thinking) return;
    HapticFeedback.selectionClick();
    var live = _live ?? false;
    if (live && !await _consent()) live = false;
    // AI answers cost money: the free tier has a few per month
    if (live && !PlusService.allowed(PlusFeature.aiQuestion)) {
      if (!mounted) return;
      await showPlus(context, reason: 'Du hast deine ${PlusService.freeAiQuestions} Gratis-Fragen genutzt');
      if (!PlusService.active.value) return;
    }
    if (!mounted) return;

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
        final text = '$e';
        if (!mounted) return;
        setState(() {
          // the server's reasons are German; a dropped connection is not
          answer.text = RegExp(r'Exception|Error|Failed|Socket|Timeout').hasMatch(text)
              ? 'Buddy ist gerade nicht erreichbar. Prüf die Verbindung und frag gleich noch einmal.'
              : text;
          answer.error = true;
          _thinking = false;
        });
      },
      onDone: () {
        // only an answer that arrived uses up one of the free questions
        if (live && !answer.error) PlusService.count(PlusFeature.aiQuestion);
        if (mounted) {
          setState(() {
            _thinking = false;
            if (!answer.error) answer.actions = BuddyActions.forQuestion(question, BuddyService.snapshot());
          });
          _scrollDown();
        }
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
        // without a back button the tab's title keeps the page margin
        titleSpacing: widget.tab ? 20 : 0,
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
                _live == null
                    ? 'verbindet …'
                    : (_live! ? 'KI-Finanzcoach' : (AccountService.current.value == null ? 'ohne Konto' : 'Offline-Modus')),
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
        // a guest isn't offline, just without the account the AI runs through
        Icon(guest ? Icons.phone_iphone_rounded : Icons.wifi_off_rounded, size: 18, color: AppColors.textDim),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            guest
                ? 'Buddy rechnet direkt auf deinem Gerät. Mit einem Konto antwortet er mit KI.'
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
            if (m.actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in m.actions)
                    ActionChip(
                      avatar: Icon(a.icon, size: 18, color: AppColors.primary),
                      label: Text(a.label),
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        a.run(context);
                      },
                    ),
                ]),
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
              child: Semantics(
                button: true,
                label: 'Senden',
                enabled: _input.text.trim().isNotEmpty && !_thinking,
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
              )),
            ),
          ]),
          const SizedBox(height: 6),
          if (_live == true && !PlusService.active.value)
            Text('Noch ${PlusService.left(PlusFeature.aiQuestion)} von ${PlusService.freeAiQuestions} Gratis-Fragen diesen Monat',
                style: TextStyle(fontSize: 11, color: AppColors.primaryText, fontWeight: FontWeight.w600)),
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
  List<BuddyAction> actions = const []; // next steps under an answer
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

// Entry on the home screen: Buddy's orb with a short tip from the user's own
// numbers (or, when nothing stands out, a question that changes every few
// seconds) and one-tap questions.
class BuddyCard extends StatefulWidget {
  final BuddyTip? tip;
  const BuddyCard({super.key, this.tip});

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
      // a tip stays put; only the general questions take turns
      if (mounted && widget.tip == null) setState(() => _i = (_i + 1) % BuddyScreen.suggestions.length);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  void _open([String? question]) => BuddyScreen.open(context, question);

  @override
  Widget build(BuildContext context) {
    final tip = widget.tip;
    final s = [
      if (tip != null) (icon: Icons.lightbulb_rounded, text: tip.question),
      ...BuddyScreen.suggestions,
    ];
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
          onTap: () => _open(tip?.question),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const BuddyOrb(size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tip != null ? 'Buddy hat einen Tipp' : 'Frag Buddy',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    if (tip != null)
                      Text(tip.text, style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35))
                    else
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      // old and new question cross-fade in the same place
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.centerLeft, children: [...previous, if (current != null) current]),
                      child: Text('„${s[_i % s.length].text}“',
                          key: ValueKey(_i),
                          style: TextStyle(color: AppColors.textDim, fontSize: 13),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
              ]),
              const SizedBox(height: 14),
              // all suggestions, full text, swipeable
              SizedBox(
                height: 38,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: s.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => Material(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _open(s[i].text),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          Icon(s[i].icon, size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(s[i].text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

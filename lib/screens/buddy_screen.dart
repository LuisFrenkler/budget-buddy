import '../services/buddy_entries.dart';
import '../services/buddy_wizard.dart';
import '../services/goals_service.dart';
import '../services/price_service.dart';
import '../utils/instruments.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/buddy_tips.dart';
import '../services/buddy_suggestions.dart';
import '../services/buddy_service.dart';
import '../services/account_service.dart';
import '../services/plus_service.dart';
import 'plus_screen.dart';
import '../utils/errors.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import 'buddy_actions.dart';
import 'depot_screen.dart';
import 'goals_screen.dart';
import 'vorsorge_screen.dart';
import 'about_screen.dart';
import '../legal/legal_texts.dart';

// Chat with Buddy, the finance coach that knows your numbers.
class BuddyScreen extends StatefulWidget {
  // asked right away, e.g. from a suggestion on the home screen
  final String? question;
  // the Buddy tab of the app shell: the one chat the rest of the app talks to
  final bool tab;
  // shell scroll: re-tapping Buddy jumps to the top of the chat
  final ScrollController? scroll;
  const BuddyScreen({super.key, this.question, this.tab = false, this.scroll});

  // a question for the Buddy tab ('' just opens it); the shell switches to the tab
  static final ask = ValueNotifier<String?>(null);

  // from anywhere: back to the shell and on into the Buddy chat
  static void open(BuildContext context, [String? question]) {
    HapticFeedback.selectionClick();
    Navigator.popUntil(context, (r) => r.isFirst);
    ask.value = question ?? '';
  }

  static List<BuddyChip> get suggestions => BuddySuggestions.fallback;

  @override
  State<BuddyScreen> createState() => _BuddyScreenState();
}

class _BuddyScreenState extends State<BuddyScreen> {
  final _input = TextEditingController();
  late final ScrollController _scroll = widget.scroll ?? ScrollController();
  final _messages = <_Message>[];
  bool _thinking = false;
  bool? _live;
  StreamSubscription<String>? _sub;
  // a photo picked for the next message (receipt, bank or broker screenshot)
  ({Uint8List bytes, String type})? _photo;
  // setup chat (Vorsorge, Sparziel, Depot) that ends in a confirm card
  final _wizard = BuddyWizard();

  static Box get _settings => Hive.box('settings');

  late final ValueListenable _consentListenable;
  late final VoidCallback _consentListener;

  @override
  void initState() {
    super.initState();
    // Profil-Schalter und Chat-Schalter halten den Status synchron
    _consentListenable = _settings.listenable(keys: const ['aiConsent', 'aiConsentGoogle']);
    _consentListener = () {
      if (mounted) setState(() {});
    };
    _consentListenable.addListener(_consentListener);
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
    _consentListenable.removeListener(_consentListener);
    if (widget.tab) BuddyScreen.ask.removeListener(_asked);
    _sub?.cancel();
    _input.dispose();
    // shell owns the controller when Buddy is a tab
    if (widget.scroll == null) _scroll.dispose();
    super.dispose();
  }

  // server AI + user consent (what the subtitle and banners show)
  bool get _aiOn => _live == true && BuddyService.hasConsent;

  // consent sheet; [force] = also when the user said no before (KI einschalten)
  Future<bool> _askConsent({bool force = false}) async {
    await BuddyService.live();
    final given = _settings.get(BuddyService.consentKey);
    if (!force) {
      if (given == true) return true;
      if (given == false) return false;
    }
    if (!mounted) return false;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const BuddyOrb(size: 48),
            const SizedBox(height: 16),
            const Text('Buddy mit KI nutzen?', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'Damit Buddy deine Fragen beantworten kann, schickt BudgetBuddy eine Zusammenfassung deiner Finanzen '
              '(Summen, letzte Buchungen, Budgets, Sparziele, Verträge, Depot, Vermögen, Vorsorge, '
              'Splits und Plus-Status, ohne Kontonummern und ohne Zahlungsdaten) an die KI von '
              '${BuddyService.provider == 'google' ? 'Google (Gemini)' : 'Anthropic'}. '
              'Keine Kontonummern, keine Zugangsdaten. '
              '${BuddyService.provider == 'google' ? 'Im kostenlosen Gemini-Tarif kann Google die Daten nutzen, um seine Dienste zu verbessern.' : 'Anthropic nutzt die Daten nicht zum Training.'}',
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
              child: const Text('KI einschalten'),
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
    if (ok != null) await BuddyService.setConsent(ok);
    if (mounted) setState(() {});
    return ok == true;
  }

  // first message: ask once; later messages keep the remembered choice
  Future<bool> _consent() => _askConsent();

  // AppBar / Banner: KI an oder aus
  Future<void> _toggleAi() async {
    if (_live != true) return;
    HapticFeedback.selectionClick();
    if (BuddyService.hasConsent) {
      await BuddyService.setConsent(false);
      if (mounted) setState(() {});
    } else {
      await _askConsent(force: true);
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.firstOrNull;
    if (file?.bytes == null) return;
    final ext = (file!.extension ?? 'jpg').toLowerCase();
    setState(() => _photo = (bytes: file.bytes!, type: ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg'));
  }

  // something that happened ("200 € aufs Tagesgeld", a receipt photo):
  // Buddy proposes the entries, the user confirms each. Returns false when
  // there is nothing to book, so the message goes on as a question.
  Future<bool> _entries(String text, bool live) async {
    final photo = _photo;
    if (photo == null && !BuddyEntries.looksLikeEvent(text)) return false;
    if (!live && photo != null) {
      setState(() {
        _photo = null;
        _messages.add(_Message(true, text, image: photo.bytes));
        _messages.add(_Message(false, AccountService.current.value == null
            ? 'Fotos lesen kann ich mit einem kostenlosen Konto.'
            : 'Fotos lesen kann ich gerade nicht, die KI ist nicht erreichbar.')..error = true);
      });
      return true;
    }
    final offline = live ? null : BuddyEntries.offline(text);
    if (!live && offline == null) return false;
    _input.clear();
    final answer = _Message(false, '', offline: !live);
    setState(() {
      _photo = null;
      _messages.add(_Message(true, text, image: photo?.bytes));
      _messages.add(answer);
      _thinking = true;
    });
    _scrollDown();
    try {
      if (live) {
        final r = await BuddyEntries.read(text, image: photo?.bytes, mediaType: photo?.type ?? 'image/jpeg');
        if (r.entries.isEmpty && photo == null) {
          // nothing to book after all: answer it as a question
          setState(() {
            _messages.removeRange(_messages.length - 2, _messages.length);
            _thinking = false;
          });
          return false;
        }
        // photo path uses receiptScan; plain event text still uses aiQuestion
        PlusService.count(photo != null ? PlusFeature.receiptScan : PlusFeature.aiQuestion);
        answer.text = r.reply.isNotEmpty
            ? r.reply
            : (r.entries.isEmpty ? 'Auf dem Bild habe ich nichts zum Buchen gefunden.' : 'Das habe ich erkannt:');
        answer.entries = r.entries;
      } else {
        answer.text = 'So würde ich das buchen:';
        answer.entries = [offline!];
      }
    } catch (e) {
      // the AI is busy or out of quota: a simple booking is still read offline
      final fallback = '$e'.contains('ausgelastet') ? BuddyEntries.offline(text) : null;
      if (fallback != null) {
        answer
          ..text = 'Die KI ist gerade ausgelastet. Ohne sie würde ich es so buchen:'
          ..offline = true
          ..entries = [fallback];
      } else {
        answer
          ..text = friendlyError(e)
          ..error = true;
      }
    }
    if (mounted) setState(() => _thinking = false);
    _scrollDown();
    return true;
  }

  Future<void> _apply(_Message m, int i) async {
    final e = m.entries[i];
    if (e.type == 'goal' &&
        !PlusService.allowed(PlusFeature.goal, current: GoalsService.all().where((g) => !g.reached).length)) {
      await showPlus(context, reason: 'Mehr Sparziele — und Autopilot für Aufrunden & Monatsziel (ohne Überweisung)');
      if (!PlusService.allowed(PlusFeature.goal, current: GoalsService.all().where((g) => !g.reached).length)) return;
    }
    HapticFeedback.mediumImpact();
    try {
      final done = await BuddyEntries.apply(e);
      if (!mounted) return;
      setState(() => m.applied[i] = done);
      if (e.type == 'vorsorge' && done == 'Gespeichert') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Rentenrechner gespeichert'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Öffnen',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VorsorgeScreen())),
          ),
        ));
      } else if (e.type == 'goal' && done == 'Angelegt') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Sparziel angelegt'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Öffnen',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())),
          ),
        ));
      } else if (e.type == 'holding' && done == 'Im Depot') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Im Depot'),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'Öffnen',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DepotScreen())),
          ),
        ));
      }
    } catch (err) {
      if (mounted) setState(() => m.applied[i] = 'Ging nicht. ${friendlyError(err)}');
    }
  }

  // asks only for missing fields, then shows the same confirm card as a booking
  Future<void> _runWizard(String text) async {
    _input.clear();
    final answer = _Message(false, '');
    setState(() {
      _messages.add(_Message(true, text));
      _messages.add(answer);
      _thinking = true;
    });
    _scrollDown();
    try {
      var turn = _wizard.consume(text);
      if (turn.quoteFor != null) {
        final q = await _lookup(turn.quoteFor!);
        if (!mounted) return;
        turn = _wizard.quoted(instrument: q.instrument, cents: q.cents, live: q.live, options: q.options);
      }
      answer.text = turn.text.isEmpty ? 'Das habe ich nicht verstanden.' : turn.text;
      if (turn.proposal != null) answer.entries = [turn.proposal!];
    } catch (e) {
      _wizard.reset();
      answer.text = friendlyError(e);
      answer.error = true;
    }
    if (mounted) setState(() => _thinking = false);
    _scrollDown();
  }

  Future<({Instrument? instrument, int cents, bool live, List<Instrument> options})> _lookup(String query) async {
    final q = query.trim().toLowerCase();
    final local = Instruments.search(q);
    Instrument? exact;
    for (final i in local) {
      final name = i.name.toLowerCase();
      if (name == q || i.symbol.toLowerCase() == q || name.startsWith('$q ')) exact = i;
    }
    final pick = exact ?? (local.length == 1 ? local.single : null);
    if (pick == null && local.length > 1) {
      return (instrument: null, cents: 0, live: false, options: local.take(4).toList());
    }
    var instrument = pick;
    if (instrument == null) {
      final remote = await PriceService.search(query);
      if (remote.length > 1) {
        return (instrument: null, cents: 0, live: false, options: remote.take(4).toList());
      }
      instrument = remote.firstOrNull;
    }
    if (instrument == null) return (instrument: null, cents: 0, live: false, options: const <Instrument>[]);
    int? live;
    try {
      live = await PriceService.livePrice(symbol: instrument.symbol, type: instrument.type);
    } catch (_) {}
    final cents = (live != null && live > 0) ? live : instrument.refCents;
    final fresh = live != null && live > 0;
    return (instrument: instrument, cents: cents, live: fresh, options: const <Instrument>[]);
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if ((question.isEmpty && _photo == null) || _thinking) return;
    HapticFeedback.selectionClick();
    // setup runs on the device: no KI quota, nothing saved until Übernehmen.
    // a photo is a receipt, not an answer to the wizard
    if (_photo != null) {
      _wizard.reset();
    } else if (question.isNotEmpty && (_wizard.isOpen || BuddyWizard.detect(question) != null)) {
      await _runWizard(question);
      return;
    }
    var live = _live ?? false;
    if (live && !await _consent()) live = false;
    // photo → Beleg-Scan quota (same as smart_entry)
    if (live && _photo != null && !PlusService.allowed(PlusFeature.receiptScan)) {
      if (!mounted) return;
      await showPlus(context,
          reason: 'Gratis-Scans aufgebraucht — mit Plus jeden Beleg in Sekunden erfassen');
      if (!PlusService.active.value) return;
    }
    // AI answers cost money: the free tier has a few per month
    if (live && _photo == null && !PlusService.allowed(PlusFeature.aiQuestion)) {
      if (!mounted) return;
      await showPlus(
          context,
          reason:
              'Gratis-Fragen aufgebraucht — mit Plus antwortet Buddy so oft du willst. '
              'Ohne Plus antwortet Buddy weiter offline aus deinen Daten.');
      // declined Plus → still answer offline (like consent decline)
      if (!PlusService.active.value) live = false;
    }
    if (!mounted) return;
    // last free question: soft note, never blocks send
    if (live && _photo == null && PlusService.left(PlusFeature.aiQuestion) == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Noch 1 Gratis-Frage diesen Monat'), behavior: SnackBarBehavior.floating),
      );
    }
    if (await _entries(question, live)) return;
    if (!mounted || question.isEmpty) return;

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
        final text = '$e';
        if (!mounted) return;
        // the free AI's quota is used up for now: answer from the data on the device
        if (live &&
            (text.contains('ausgelastet') ||
                text.contains('Tageslimit') ||
                text.contains('429') ||
                text.contains('Limit'))) {
          setState(() {
            answer.text = '';
            answer.offline = true;
          });
          _sub = BuddyService.ask(history, live: false).listen(
            (piece) => setState(() => answer.text += piece),
            onDone: () {
              if (mounted) setState(() => _thinking = false);
              _scrollDown();
            },
          );
          return;
        }
        HapticFeedback.heavyImpact();
        setState(() {
          answer.text = friendlyError(e,
              fallback: 'Buddy ist gerade nicht erreichbar. Prüf die Verbindung und frag gleich noch einmal.');
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
            // tippen schaltet die KI um, wenn der Server sie anbietet
            InkWell(
              onTap: _live == true ? _toggleAi : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _aiOn ? AppColors.positive : AppColors.textDim,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _statusLabel,
                    style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w500),
                  ),
                  if (_live == true) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.expand_more_rounded, size: 14, color: AppColors.textDim),
                  ],
                ]),
              ),
            ),
          ]),
        ]),
        actions: [
          if (_live == true)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                tooltip: _aiOn ? 'KI ausschalten' : 'KI einschalten',
                onPressed: _toggleAi,
                icon: Icon(
                  _aiOn ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                  color: _aiOn ? AppColors.primaryText : AppColors.textDim,
                ),
              ),
            ),
        ],
      ),
      body: Column(children: [
        if (_live == true && !BuddyService.hasConsent) _aiOffBanner(),
        Expanded(child: _messages.isEmpty ? _welcome() : _chat()),
        _inputBar(),
      ]),
    );
  }

  String get _statusLabel {
    if (_live == null) return 'verbindet …';
    if (_live != true) return 'Offline-Modus';
    return _aiOn ? 'KI an' : 'KI aus · tippen zum Einschalten';
  }

  String get _quotaLine {
    final left = PlusService.left(PlusFeature.aiQuestion);
    if (left == 0) return 'Gratis-KI-Fragen aufgebraucht · Offline-Antworten gehen weiter';
    if (left == 1) return 'Noch 1 Gratis-KI-Frage diesen Monat';
    return 'Noch $left von ${PlusService.freeAiQuestions} Gratis-KI-Fragen diesen Monat';
  }

  Widget _welcome() {
    final name = AccountService.current.value?.firstName;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
      children: [
        const Center(child: BuddyOrb(size: 120)),
        const SizedBox(height: 32),
        Text(name != null ? 'Hallo $name, ich bin Buddy.' : 'Hallo, ich bin Buddy.',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6)),
        const SizedBox(height: 8),
        Text(
          AccountService.current.value == null
              ? 'Mit Konto antwortet Buddy online und kann Belege lesen. Ohne Anmeldung rechnet er offline auf deinem Gerät.'
              : 'Dein Finanzcoach für den Alltag. Frag, ob du dir etwas leisten kannst — '
                  'ich nutze deine Ausgaben, Budgets und Verträge.',
          style: TextStyle(fontSize: 15.5, color: AppColors.textDim, height: 1.45),
        ),
        const SizedBox(height: 24),
        for (final s in BuddySuggestions.pick(BuddyService.snapshot()))
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
        if (AccountService.current.value == null) ...[
          const SizedBox(height: 12),
          _signInHint(),
        ] else if (_live == false) ...[
          const SizedBox(height: 12),
          _offlineHint(),
        ],
      ],
    );
  }

  Widget _aiOffBanner() {
    return Material(
      color: AppColors.surfaceAlt,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(children: [
          Icon(Icons.auto_awesome_outlined, size: 18, color: AppColors.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'KI ist aus — Buddy antwortet offline aus deinen Daten. Tippe oben auf „KI an“.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35),
            ),
          ),
          TextButton(
            onPressed: _toggleAi,
            child: const Text('Einschalten'),
          ),
        ]),
      ),
    );
  }

  Widget _offlineHint() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Icon(Icons.wifi_off_rounded, size: 18, color: AppColors.textDim),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Offline-Modus: Buddy rechnet auf deinem Gerät. KI-Antworten brauchen Internet und „KI an“.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35),
          ),
        ),
      ]),
    );
  }

  Widget _signInHint() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.person_outline_rounded, size: 18, color: AppColors.primaryText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Kostenloses Konto: KI-Fragen, Beleg-Scan und Sync auf allen Geräten. '
            'Offline-Antworten gehen auch ohne.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35),
          ),
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
        if (m.fromUser) return _userBubble(m.text, m.image);
        final waiting = m.text.isEmpty && _thinking && i == _messages.length - 1;
        return _buddyBubble(m, waiting);
      },
    );
  }

  Widget _userBubble(String text, [Uint8List? image]) => Align(
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(image, height: 140, fit: BoxFit.cover),
              ),
            if (image != null && text.isNotEmpty) const SizedBox(height: 8),
            if (text.isNotEmpty) Text(text, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
          ]),
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
                child: Text('Ohne KI berechnet aus deinen Daten',
                    style: TextStyle(fontSize: 11, color: AppColors.textDim)),
              ),
            for (var i = 0; i < m.entries.length; i++) _entryCard(m, i),
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

  // one proposed entry; nothing is stored until "Übernehmen"
  Widget _entryCard(_Message m, int i) {
    final e = m.entries[i];
    final done = m.applied[i];
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: done == null ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title, style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(e.summary, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3)),
          ]),
        ),
        const SizedBox(width: 8),
        done == null
            ? FilledButton(
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => _apply(m, i),
                child: const Text('Übernehmen'),
              )
            : Text('✓ $done', style: TextStyle(color: AppColors.positiveText, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_photo != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_photo!.bytes, height: 72, width: 72, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      tooltip: 'Foto entfernen',
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: () => setState(() => _photo = null),
                      icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          Row(children: [
            IconButton(
              tooltip: 'Foto senden',
              onPressed: _thinking ? null : _pickPhoto,
              icon: Icon(Icons.add_photo_alternate_rounded, color: AppColors.primaryText),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Frag Buddy oder erzähl, was passiert ist …',
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
              opacity: (_input.text.trim().isEmpty && _photo == null) || _thinking ? 0.4 : 1,
              child: Semantics(
                button: true,
                label: 'Senden',
                enabled: (_input.text.trim().isNotEmpty || _photo != null) && !_thinking,
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
            Text(_quotaLine,
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
  bool offline;
  bool error = false;
  List<BuddyAction> actions = const []; // next steps under an answer
  List<BuddyEntry> entries = const []; // what Buddy would book, each confirmed by the user
  final Map<int, String> applied = {}; // entry index -> what was done
  Uint8List? image; // a photo the user sent
  _Message(this.fromUser, this.text, {this.offline = false, this.image});
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
  final List<BuddyChip>? chips;
  const BuddyCard({super.key, this.tip, this.chips});

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
      if (mounted && widget.tip == null) {
        final n = (widget.chips ?? BuddyScreen.suggestions).length;
        if (n > 0) setState(() => _i = (_i + 1) % n);
      }
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
    final base = widget.chips ?? BuddyScreen.suggestions;
    final s = [
      if (tip != null) (icon: Icons.lightbulb_rounded, text: tip.question),
      ...base,
    ];
    // a 1.5 px gradient border around the card
    return Container(
      padding: const EdgeInsets.all(1.25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(colors: [
          AppColors.primary.withValues(alpha: 0.9),
          const Color(0xFF38BDF8).withValues(alpha: 0.75),
          const Color(0xFFF472B6).withValues(alpha: 0.6),
        ]),
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22.75),
        child: InkWell(
          borderRadius: BorderRadius.circular(22.75),
          onTap: () {
            HapticFeedback.selectionClick();
            _open(tip?.question);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const BuddyOrb(size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tip != null ? 'Buddy hat einen Tipp' : 'Frag Buddy',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    const SizedBox(height: 3),
                    if (tip != null)
                      Text(tip.text, style: TextStyle(color: AppColors.textDim, fontSize: 13.5, height: 1.35))
                    else
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      layoutBuilder: (current, previous) =>
                          Stack(alignment: Alignment.centerLeft, children: [...previous, if (current != null) current]),
                      child: Text('„${s[_i % s.length].text}“',
                          key: ValueKey(_i),
                          style: TextStyle(color: AppColors.textDim, fontSize: 13.5),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
                Icon(Icons.north_east_rounded, size: 18, color: AppColors.textDim.withValues(alpha: 0.75)),
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

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
import '../services/buddy_history.dart';
import '../services/buddy_markers.dart';
import '../services/buddy_memory.dart';
import '../services/account_service.dart';
import '../services/db.dart';
import '../services/guest_buddy.dart';
import '../services/hints_service.dart';
import '../services/life_stages.dart';
import '../services/plus_service.dart';
import '../services/settings_service.dart';
import '../services/voice_input.dart';
import 'plus_screen.dart';
import '../utils/dates.dart';
import '../utils/errors.dart';
import '../utils/theme.dart';
import '../widgets/brand.dart';
import '../widgets/buddy_orb.dart';
import '../widgets/buddy_text.dart';
import '../widgets/life_stage_sheet.dart';
import '../widgets/share_card.dart';
import 'auth_screens.dart';
import 'buddy_actions.dart';
import 'buddy_memory_screen.dart';
import 'depot_screen.dart';
import 'goals_screen.dart';
import 'vorsorge_screen.dart';
import 'about_screen.dart';
import '../legal/legal_texts.dart';
import '../l10n/l10n.dart';

export '../widgets/buddy_text.dart' show RichMarkdown;

bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

// Chat with Buddy, the finance coach that knows your numbers. Also the very
// first screen before sign-up ([guest]): useful from the first message, no
// account and no bank link needed.
class BuddyScreen extends StatefulWidget {
  // asked right away, e.g. from a suggestion on the home screen
  final String? question;
  // the Buddy tab of the app shell: the one chat the rest of the app talks to
  final bool tab;
  // shell scroll: re-tapping Buddy jumps to the top of the chat
  final ScrollController? scroll;
  // before sign-up: general answers, a few AI questions a day, sign-up in the header
  final bool guest;
  const BuddyScreen({super.key, this.question, this.tab = false, this.scroll, this.guest = false});

  // a question for the Buddy tab ('' just opens it); the shell switches to the tab
  static final ask = ValueNotifier<String?>(null);

  // from anywhere: back to the shell and on into the Buddy chat
  static void open(BuildContext context, [String? question]) {
    HapticFeedback.selectionClick();
    Navigator.popUntil(context, (r) => r.isFirst);
    ask.value = question ?? '';
  }

  // shared with Beleg-Scan (Schnell erfassen), same sheet, same consent key
  static Future<bool> requestAiConsent(BuildContext context, {bool force = false}) async {
    await BuddyService.live();
    final given = Hive.box('settings').get(BuddyService.consentKey);
    if (!force) {
      if (given == true) return true;
      if (given == false) return false;
    }
    if (!context.mounted) return false;
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
            Text(tr('Buddy mit KI nutzen?'), style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              tr('Buddy holt sich nur die Daten, die er für deine Fragen braucht: eine Zusammenfassung deiner Finanzen (Summen, letzte Buchungen, Budgets, Sparziele, Verträge, Depot, Vermögen, Vorsorge, Splits, Plus-Status und was du Buddy zu merken erlaubt hast). Sie geht an die KI von {x}, ohne Kontonummern und ohne Zugangsdaten. {x2}', {'x': BuddyService.provider == 'google' ? tr('Google (Gemini)') : tr('Anthropic'), 'x2': BuddyService.provider == 'google' ? tr('Im kostenlosen Gemini-Tarif kann Google die Daten nutzen, um seine Dienste zu verbessern.') : tr('Anthropic nutzt die Daten nicht zum Training.')}),
              style: TextStyle(color: AppColors.textDim, height: 1.45),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: LegalTexts.privacy))),
                child: Text(tr('Datenschutzerklärung lesen')),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('KI einschalten')),
            ),
            const SizedBox(height: 6),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Nur offline antworten'), style: TextStyle(color: AppColors.textDim)),
              ),
            ),
          ]),
        ),
      ),
    );
    if (ok != null) await BuddyService.setConsent(ok);
    return ok == true;
  }

  static List<BuddyChip> get suggestions => BuddySuggestions.fallback;

  // the first questions before sign-up: the moments of a first job
  static const guestSuggestions = <BuddyChip>[
    (icon: Icons.receipt_long_rounded, text: 'Wie prüfe ich meine erste Gehaltsabrechnung?'),
    (icon: Icons.savings_outlined, text: 'Wie viel Notgroschen brauche ich?'),
    (icon: Icons.work_outline_rounded, text: 'Lohnt sich die Betriebsrente?'),
    (icon: Icons.show_chart_rounded, text: 'Was ist ein ETF-Sparplan?'),
  ];

  @override
  State<BuddyScreen> createState() => _BuddyScreenState();
}

class _BuddyScreenState extends State<BuddyScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  late final ScrollController _scroll = widget.scroll ?? ScrollController();
  final _messages = <_Message>[];
  bool _thinking = false;
  bool? _live;
  StreamSubscription<String>? _sub;
  // a photo picked for the next message (receipt, bank or broker screenshot)
  ({Uint8List bytes, String type})? _photo;
  // setup chat (Vorsorge, Sparziel, Depot) that ends in a confirm card
  final _wizard = BuddyWizard();
  // the "jump to the latest message" button
  bool _away = false;
  // the guest's sign-up card was closed for this session
  bool _ctaClosed = false;
  // Buddy's little hop after something good happened
  bool _cheer = false;
  Timer? _cheerTimer;

  void _celebrate() {
    _cheerTimer?.cancel();
    setState(() => _cheer = true);
    _cheerTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _cheer = false);
    });
  }

  BuddyMood get _mood => _thinking ? BuddyMood.thinking : (_cheer ? BuddyMood.happy : BuddyMood.idle);

  bool get _guest => widget.guest;
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
    _scroll.addListener(_onScroll);
    _focus.addListener(_onFocus);
    VoiceInput.listening.addListener(_onFocus);
    _restore();
    (_guest ? GuestBuddy.live() : BuddyService.live()).then((v) {
      if (!mounted) return;
      setState(() => _live = v);
      if (widget.question != null) _send(widget.question!);
      if (widget.tab) _asked();
      if (!_guest) _checkIn();
    });
    if (widget.tab) BuddyScreen.ask.addListener(_asked);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  // the conversation from last time (and, right after sign-up, the guest chat)
  void _restore() {
    final saved = BuddyHistory.load(guest: _guest);
    for (final m in saved) {
      _messages.add(_Message(m.fromUser, m.text, at: m.at, offline: m.offline)..restored = true);
    }
    if (_messages.isNotEmpty) _scrollDown(jump: true);
  }

  Future<void> _persist() => BuddyHistory.save([
        for (final m in _messages)
          if (!m.error && m.text.trim().isNotEmpty)
            SavedMessage(m.fromUser, m.fromUser ? m.text : BuddyMarkers.parse(m.text).text, m.at, offline: m.offline)
      ], guest: _guest);

  // Buddy speaks first, rarely: once a day at most, only when something
  // really matters (a budget tipping over, a contract got pricier)
  void _checkIn() {
    if (_guest || _thinking) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final last = _settings.get('buddyCheckIn');
    if (last is Map && last['day'] == today) return;
    Hint? hint;
    try {
      hint = HintsService.current(
        tx: DB.getTx(),
        budgets: DB.getBudgets(),
        goals: GoalsService.all(),
        subscription: PlusService.subscription.value,
        bankValidUntil: Settings.bankValidUntil,
      ).where((h) => h.urgent).firstOrNull;
    } catch (_) {
      return;
    }
    if (hint == null || (last is Map && last['id'] == hint.id)) return;
    _settings.put('buddyCheckIn', {'day': today, 'id': hint.id});
    setState(() {
      _messages.add(_Message(false, tr('Kurz von mir: **{title}**. {text}', {'title': hint!.title, 'text': hint.text}))
        ..checkIn = true
        ..followUps = [tr('Was kann ich da tun?'), tr('Wie wirkt sich das auf den Monat aus?')]);
    });
    _persist();
    _scrollDown();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final away = _scroll.position.maxScrollExtent - _scroll.offset > 280;
    if (away != _away) setState(() => _away = away);
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
    _scroll.removeListener(_onScroll);
    _focus.removeListener(_onFocus);
    VoiceInput.listening.removeListener(_onFocus);
    if (VoiceInput.listening.value) VoiceInput.stop();
    _sub?.cancel();
    _cheerTimer?.cancel();
    _input.dispose();
    _focus.dispose();
    // shell owns the controller when Buddy is a tab
    if (widget.scroll == null) _scroll.dispose();
    super.dispose();
  }

  // server AI + user consent (what the subtitle and banners show)
  bool get _aiOn => _guest ? (_live == true && GuestBuddy.left() > 0) : (_live == true && BuddyService.hasConsent);

  // consent sheet; [force] = also when the user said no before (KI einschalten)
  Future<bool> _askConsent({bool force = false}) async {
    final ok = await BuddyScreen.requestAiConsent(context, force: force);
    if (mounted) setState(() {});
    return ok;
  }

  // first message: ask once; later messages keep the remembered choice
  Future<bool> _consent() => _askConsent();

  // AppBar / Banner: KI an oder aus
  Future<void> _toggleAi() async {
    if (_live != true || _guest) return;
    HapticFeedback.selectionClick();
    if (BuddyService.hasConsent) {
      await BuddyService.setConsent(false);
      if (mounted) setState(() {});
    } else {
      await _askConsent(force: true);
    }
  }

  // speak a question or "Döner 8,50 gestern"; the words fill the field
  Future<void> _voice() async {
    if (VoiceInput.listening.value) {
      HapticFeedback.selectionClick();
      await VoiceInput.stop();
      return;
    }
    HapticFeedback.mediumImpact();
    final ok = await VoiceInput.start((text, done) {
      if (!mounted) return;
      setState(() {
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
      });
    });
    if (!ok && mounted) {
      _snack(tr('Spracheingabe geht hier gerade nicht. Erlaube das Mikrofon oder tipp deine Frage.'));
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
            ? tr('Fotos lesen kann ich mit einem kostenlosen Konto.')
            : tr('Fotos lesen kann ich gerade nicht, die KI ist nicht erreichbar.'))..error = true);
      });
      return true;
    }
    final offline = live ? null : BuddyEntries.offline(text);
    if (!live && offline == null) return false;
    _input.clear();
    final answer = _Message(false, '', offline: !live)..streaming = true;
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
            : (r.entries.isEmpty ? tr('Auf dem Bild habe ich nichts zum Buchen gefunden.') : tr('Das habe ich erkannt:'));
        answer.entries = r.entries;
      } else {
        answer.text = tr('So würde ich das buchen:');
        answer.entries = [offline!];
      }
    } catch (e) {
      // the AI is busy or out of quota: a simple booking is still read offline
      final fallback = '$e'.contains('ausgelastet') ? BuddyEntries.offline(text) : null;
      if (fallback != null) {
        answer
          ..text = tr('Die KI ist gerade ausgelastet. Ohne sie würde ich es so buchen:')
          ..offline = true
          ..entries = [fallback];
      } else {
        answer
          ..text = friendlyError(e)
          ..error = true;
      }
    }
    if (mounted) {
      setState(() {
        _thinking = false;
        answer.streaming = false;
      });
    }
    _persist();
    _scrollDown();
    return true;
  }

  Future<void> _apply(_Message m, int i) async {
    final e = m.entries[i];
    if (e.type == 'goal' &&
        !PlusService.allowed(PlusFeature.goal, current: GoalsService.all().where((g) => !g.reached).length)) {
      await showPlus(context,
          reason: tr('Du hast schon ein aktives Sparziel. Plus = beliebig viele Ziele.'));
      if (!PlusService.allowed(PlusFeature.goal, current: GoalsService.all().where((g) => !g.reached).length)) return;
    }
    HapticFeedback.mediumImpact();
    try {
      final done = await BuddyEntries.apply(e);
      if (!mounted) return;
      setState(() => m.applied[i] = done);
      _celebrate();
      _tickLifeStage(e);
      if (e.type == 'recategorize' || e.type == 'recategorize_all') {
        _snack(tr('{done}. Buddy merkt sich die Regel für künftige Buchungen.', {'done': done}));
      } else if (e.type == 'vorsorge' && done == 'Gespeichert') {
        _snack(tr('Rentenrechner gespeichert'),
            open: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const VorsorgeScreen())));
      } else if (e.type == 'goal' && done == 'Angelegt') {
        _snack(tr('Sparziel angelegt'),
            open: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GoalsScreen())));
      } else if (e.type == 'holding' && done == 'Im Depot') {
        _snack(tr('Im Depot'), open: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DepotScreen())));
      }
    } catch (err) {
      if (mounted) setState(() => m.applied[i] = tr('Ging nicht. {x}', {'x': friendlyError(err)}));
    }
  }

  // a confirmed savings goal "Notgroschen" ticks off that step of the life stage
  void _tickLifeStage(BuddyEntry e) {
    final stage = LifeStages.current;
    if (stage == null || e.type != 'goal') return;
    final name = '${e.note} ${e.name}'.toLowerCase();
    for (final step in stage.steps) {
      if (name.contains('notgroschen') && step.id == 'notgroschen') LifeStages.setDone(stage, step, true);
      if (name.contains('umzug') && step.id == 'kaution') LifeStages.setDone(stage, step, true);
    }
  }

  void _snack(String text, {VoidCallback? open}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      behavior: SnackBarBehavior.floating,
      action: open == null ? null : SnackBarAction(label: tr('Öffnen'), onPressed: open),
    ));
  }

  Future<void> _remember(_Message m) async {
    final fact = m.remember;
    if (fact == null) return;
    HapticFeedback.mediumImpact();
    final ok = await BuddyMemory.add(fact);
    if (!mounted) return;
    setState(() => m.rememberState = ok ? 'saved' : 'known');
    if (ok) _celebrate();
  }

  // asks only for missing fields, then shows the same confirm card as a booking
  Future<void> _runWizard(String text) async {
    _input.clear();
    final answer = _Message(false, '')..streaming = true;
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
      answer.text = turn.text.isEmpty ? tr('Das habe ich nicht verstanden.') : turn.text;
      if (turn.proposal != null) answer.entries = [turn.proposal!];
    } catch (e) {
      _wizard.reset();
      answer.text = friendlyError(e);
      answer.error = true;
    }
    if (mounted) {
      setState(() {
        _thinking = false;
        answer.streaming = false;
      });
    }
    _persist();
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

  // "Merk dir, dass …": Buddy repeats it as a card; it is kept only on "Merken"
  bool _rememberCommand(String text) {
    if (_guest) return false;
    final fact = BuddyMemory.fromCommand(text);
    if (fact == null) return false;
    _input.clear();
    final allowed = BuddyMemory.allowed(fact);
    setState(() {
      _messages.add(_Message(true, text));
      _messages.add(_Message(
          false,
          allowed
              ? tr('Soll ich mir das merken? Dann muss ich nicht jedes Mal neu fragen.')
              : tr('Das merke ich mir lieber nicht. Gesundheit, Glaube, Politik und Zugangsdaten bleiben bei dir.'))
        ..remember = allowed ? fact : null);
    });
    _persist();
    _scrollDown();
    return true;
  }

  Future<void> _send(String text) async {
    final question = text.trim();
    if ((question.isEmpty && _photo == null) || _thinking) return;
    if (VoiceInput.listening.value) VoiceInput.stop();
    HapticFeedback.selectionClick();
    if (_guest) return _sendGuest(question);
    if (_photo == null && _rememberCommand(question)) return;
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
          reason: tr('Gratis-Scans aufgebraucht. Mit Plus erfasst du jeden Beleg in Sekunden.'));
      if (!PlusService.active.value) return;
    }
    // AI answers cost money: the free tier has a few per month
    if (live && _photo == null && !PlusService.allowed(PlusFeature.aiQuestion)) {
      if (!mounted) return;
      await showPlus(
          context,
          reason:
              tr('Gratis-Fragen aufgebraucht. Mit Plus antwortet Buddy, so oft du willst. Ohne Plus antwortet Buddy weiter offline aus deinen Daten.'));
      // declined Plus → still answer offline (like consent decline)
      if (!PlusService.active.value) live = false;
    }
    if (!mounted) return;
    // last free question: soft note, never blocks send
    if (live && _photo == null && PlusService.left(PlusFeature.aiQuestion) == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Noch 1 Gratis-Frage diesen Monat')), behavior: SnackBarBehavior.floating),
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

    final history = _history();
    final answer = _messages.last;
    _stream(answer, BuddyService.ask(history, live: live),
        question: question,
        countsQuestion: live,
        onLimit: live
            ? () => _stream(answer, BuddyService.ask(history, live: false), question: question, degraded: true)
            : null);
  }

  List<ChatMessage> _history() => [
        for (final m in _messages.sublist(0, _messages.length - 1))
          if (m.text.isNotEmpty && !m.error)
            ChatMessage(m.fromUser, m.fromUser ? m.text : BuddyMarkers.parse(m.text).text)
      ];

  // before sign-up: real AI while the day's free answers last, then offline
  Future<void> _sendGuest(String question) async {
    if (question.isEmpty) return;
    _input.clear();
    final live = _live == true && GuestBuddy.left() > 0;
    setState(() {
      _messages.add(_Message(true, question));
      _messages.add(_Message(false, '', offline: !live));
      _thinking = true;
    });
    _scrollDown();
    final answer = _messages.last;
    if (!live) {
      _stream(answer, _typed(GuestBuddy.offline(question)), question: question);
      return;
    }
    final history = [for (final m in _history()) (fromUser: m.fromUser, text: m.text)];
    _stream(answer, GuestBuddy.ask(history),
        question: question,
        anyErrorFallsBack: true,
        onLimit: () => _stream(answer, _typed(GuestBuddy.offline(question)), question: question, degraded: true));
  }

  // a ready answer, handed out in small pieces so it reads like a live one
  static Stream<String> _typed(String text) async* {
    for (final word in RegExp(r'\S+\s*').allMatches(text)) {
      await Future.delayed(const Duration(milliseconds: 16));
      yield word.group(0)!;
    }
  }

  // runs one answer stream into [answer]; [onLimit] retries offline when the
  // AI is out of quota (or, with [anyErrorFallsBack], on any error)
  void _stream(_Message answer, Stream<String> pieces,
      {required String question,
      VoidCallback? onLimit,
      bool degraded = false,
      bool countsQuestion = false,
      bool anyErrorFallsBack = false}) {
    _sub?.cancel();
    setState(() {
      answer
        ..text = ''
        ..streaming = true
        ..error = false;
      if (degraded) {
        answer
          ..offline = true
          ..degraded = true;
      }
    });
    _sub = pieces.listen(
      (piece) {
        if (!mounted) return;
        setState(() => answer.text += piece);
        _scrollDown();
      },
      onError: (e) {
        if (!mounted) return;
        final text = '$e';
        final limit = text.contains('ausgelastet') ||
            text.contains('Tageslimit') ||
            text.contains('429') ||
            text.contains('Limit') ||
            text.contains('aufgebraucht');
        if (onLimit != null && (limit || anyErrorFallsBack)) {
          onLimit();
          return;
        }
        HapticFeedback.heavyImpact();
        setState(() {
          answer
            ..text = friendlyError(e,
                fallback: tr('Buddy ist gerade nicht erreichbar. Prüf die Verbindung und frag gleich noch einmal.'))
            ..error = true
            ..streaming = false;
          _thinking = false;
        });
      },
      onDone: () {
        // only an answer that arrived uses up one of the free questions
        if (countsQuestion && !answer.error && !answer.degraded) PlusService.count(PlusFeature.aiQuestion);
        if (!mounted || answer.error) return;
        setState(() {
          _thinking = false;
          answer.streaming = false;
          _finish(answer, question);
        });
        _persist();
        _scrollDown();
        HapticFeedback.lightImpact();
      },
    );
  }

  // an answer is complete: follow-ups, a fact to remember, next-step buttons
  void _finish(_Message answer, String question) {
    final parsed = BuddyMarkers.parse(answer.text);
    answer.followUps = parsed.followUps.isNotEmpty ? parsed.followUps : _localFollowUps(question);
    final fact = parsed.remember;
    if (!_guest && fact != null && BuddyMemory.allowed(fact) && !BuddyMemory.knows(fact)) answer.remember = fact;
    if (!_guest) answer.actions = BuddyActions.forQuestion(question, BuddyService.snapshot());
  }

  // offline answers have no follow-ups from the AI: the next steps of the
  // matching life stage, or two good general questions
  List<String> _localFollowUps(String question) {
    final step = LifeStages.stepFor(question);
    if (step != null) {
      for (final stage in LifeStages.all) {
        final i = stage.steps.indexWhere((s) => identical(s, step));
        if (i >= 0) return [for (final s in stage.steps.skip(i + 1).take(2)) s.title];
      }
    }
    final pool = _guest ? BuddyScreen.guestSuggestions : BuddySuggestions.fallback;
    return [for (final c in pool) if (c.text.toLowerCase() != question.toLowerCase()) c.text].take(2).toList();
  }

  // a follow-up that names a life stage step sends that step's full question
  void _follow(String f) {
    for (final stage in LifeStages.all) {
      for (final s in stage.steps) {
        if (s.title == f) return _send(s.prompt).ignore();
      }
    }
    _send(f);
  }

  void _scrollDown({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (jump) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      }
    });
  }

  Future<void> _newChat() async {
    if (_thinking) return;
    HapticFeedback.mediumImpact();
    _sub?.cancel();
    _wizard.reset();
    setState(() => _messages.clear());
    await BuddyHistory.clear(guest: _guest);
  }

  void _openStage(LifeStage stage) =>
      showLifeStage(context, stage, onAsk: (q) => _send(q), save: !_guest).then((_) {
        if (mounted) setState(() {});
      });

  void _message(_Message m) {
    final plain = m.fromUser ? m.text : BuddyMarkers.parse(m.text).text;
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: Text(tr('Kopieren')),
            onTap: () async {
              Navigator.pop(sheet);
              await Clipboard.setData(ClipboardData(text: plain.replaceAll('**', '')));
              if (mounted) _snack(tr('Kopiert'));
            },
          ),
          if (!m.fromUser && !m.error)
            ListTile(
              leading: const Icon(Icons.ios_share_rounded),
              title: Text(tr('Als Karte teilen')),
              subtitle: Text(tr('Beträge kannst du vorher ausblenden')),
              onTap: () {
                Navigator.pop(sheet);
                _shareAnswer(m);
              },
            ),
        ]),
      ),
    );
  }

  void _shareAnswer(_Message m) {
    final i = _messages.indexOf(m);
    final question = i > 0 && _messages[i - 1].fromUser ? _messages[i - 1].text : tr('Frag Buddy');
    final body = BuddyMarkers.parse(m.text).text;
    showShareCard(
      context,
      ShareCardData(
        kicker: tr('Frag Buddy'),
        headline: question.length > 90 ? '${question.substring(0, 89)}…' : question,
        body: body.length > 420 ? '${body.substring(0, 419)}…' : body,
        text: tr('{q} Buddy von Ahead hat mir das in Sekunden ausgerechnet.', {'q': question}),
      ),
    );
  }

  // ---------------------------------------------------------------- layout

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _guest ? _guestBar() : _bar(),
      body: Column(children: [
        if (!_guest && _live == true && !BuddyService.hasConsent) _aiOffBanner(),
        Expanded(
          child: Stack(children: [
            Positioned.fill(child: _messages.isEmpty ? _welcome() : _chat()),
            Positioned(
              right: 16,
              bottom: 10,
              child: AnimatedScale(
                scale: _away && _messages.isNotEmpty ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Material(
                  color: AppColors.surfaceAlt,
                  shape: const CircleBorder(),
                  elevation: 2,
                  child: IconButton(
                    tooltip: tr('Zur neuesten Nachricht'),
                    onPressed: () => _scrollDown(),
                    icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                  ),
                ),
              ),
            ),
          ]),
        ),
        _inputBar(),
      ]),
    );
  }

  PreferredSizeWidget _bar() => AppBar(
        // without a back button the tab's title keeps the page margin
        titleSpacing: widget.tab ? 20 : 0,
        title: Row(children: [
          BuddyOrb(size: 34, mood: _mood),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Buddy'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
            // tippen schaltet die KI um, wenn der Server sie anbietet
            InkWell(
              onTap: _live == true ? _toggleAi : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _thinking ? AppColors.brand : (_aiOn ? AppColors.positive : AppColors.textDim),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _thinking ? tr('schreibt …') : _statusLabel,
                    style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w500),
                  ),
                ]),
              ),
            ),
          ]),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: tr('Mehr'),
            icon: const Icon(Icons.more_horiz_rounded),
            color: AppColors.surfaceAlt,
            onSelected: (v) {
              switch (v) {
                case 'memory':
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const BuddyMemoryScreen()));
                case 'stage':
                  _openStage(LifeStages.current ?? LifeStages.firstJob);
                case 'new':
                  _newChat();
                default:
                  _toggleAi();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'stage', child: _menuRow(Icons.flag_outlined, tr('Lebenslage'))),
              PopupMenuItem(value: 'memory', child: _menuRow(Icons.bookmark_outline_rounded, tr('Was Buddy weiß'))),
              if (_messages.isNotEmpty)
                PopupMenuItem(value: 'new', child: _menuRow(Icons.add_comment_outlined, tr('Neuer Chat'))),
              if (_live == true)
                PopupMenuItem(
                    value: 'ai',
                    child: _menuRow(_aiOn ? Icons.cloud_off_outlined : Icons.cloud_outlined,
                        _aiOn ? tr('KI ausschalten') : tr('KI einschalten'))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      );

  Widget _menuRow(IconData icon, String text) => Row(children: [
        Icon(icon, size: 20, color: AppColors.textDim),
        const SizedBox(width: 12),
        Text(text),
      ]);

  // before sign-up the opening is copper, like the landing page; once the
  // chat starts the bar turns quiet
  PreferredSizeWidget _guestBar() {
    final copper = _messages.isEmpty;
    const ink = Color(0xFF16120F);
    return AppBar(
      titleSpacing: 20,
      backgroundColor: copper ? AppColors.brand : null,
      foregroundColor: copper ? Colors.white : null,
      systemOverlayStyle: copper ? SystemUiOverlayStyle.light : null,
      title: Row(children: [
        BrandMark(size: 30, inverse: copper),
        const SizedBox(width: 10),
        copper
            ? const Text('Ahead.',
                style: TextStyle(
                    fontFamily: AppFonts.display,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.9,
                    color: Colors.white))
            : const Wordmark(size: 21),
      ]),
      actions: [
        TextButton(
          style: copper ? TextButton.styleFrom(foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignInScreen())),
          child: Text(tr('Anmelden')),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12, left: 2),
          child: FilledButton(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              backgroundColor: copper ? ink : AppColors.brand,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
            child: Text(tr('Starten')),
          ),
        ),
      ],
    );
  }

  // the guest's opening: the landing page's question on copper, with the
  // coin rolling in from the right
  Widget _guestHero() => Container(
        color: AppColors.brand,
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            right: -70,
            bottom: -60,
            child: Container(
              width: 210,
              height: 210,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                    center: Alignment(-0.3, -0.4), colors: [Color(0xFFC77847), Color(0xFF9C5226)], stops: [0, 0.75]),
              ),
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: CustomPaint(painter: MarkPainter(color: const Color(0x66FFF6EF))),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: tr('Was mach ich jetzt mit meinem ')),
                  TextSpan(text: tr('Gehalt?'), style: const TextStyle(color: Color(0xFF2A140A))),
                ]),
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontSize: 44,
                  height: 0.98,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.6,
                  color: Color(0xFFFFF6EF),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(right: 70),
                child: Text(
                  tr('Frag Buddy. Ohne Anmeldung, ohne Bank. Er erklärt jeden Begriff und sagt dir den nächsten Schritt.'),
                  style: const TextStyle(fontSize: 15.5, height: 1.45, color: Color(0xEBFFF6EF)),
                ),
              ),
            ]),
          ),
        ]),
      );

  String get _statusLabel {
    if (_live == null) return tr('verbindet …');
    if (_live != true) return tr('Offline-Modus');
    return _aiOn ? tr('KI an') : tr('KI aus · tippen zum Einschalten');
  }

  String? get _quotaLine {
    if (_guest) {
      final left = GuestBuddy.left();
      if (_live != true) return tr('Offline: Grundlagen ohne KI');
      if (left == 0) return tr('KI für heute aufgebraucht, Grundlagen gehen weiter');
      return left == 1 ? tr('Noch 1 KI-Antwort heute') : tr('Noch {n} KI-Antworten heute', {'n': left});
    }
    if (_live != true || PlusService.active.value) return null;
    final left = PlusService.left(PlusFeature.aiQuestion);
    if (left == 0) return tr('Gratis-KI-Fragen aufgebraucht');
    if (left == 1) return tr('Noch 1 Gratis-KI-Frage diesen Monat');
    return tr('Noch {left} von {x} Gratis-KI-Fragen', {'left': left, 'x': PlusService.limit(PlusFeature.aiQuestion)});
  }

  // --------------------------------------------------------------- welcome

  // the empty chat fits one screen: who Buddy is, where you stand, three
  // ways in, and the input right below
  Widget _welcome() {
    final name = AccountService.current.value?.firstName;
    final stage = _guest ? null : LifeStages.current;
    final others = LifeStages.all.where((s) => s.id != stage?.id).toList();
    final chips = (_guest ? BuddyScreen.guestSuggestions : BuddySuggestions.pick(BuddyService.snapshot(), max: 5))
        .take(3)
        .toList();
    if (_guest) {
      return ListView(padding: EdgeInsets.zero, children: [
        _guestHero(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _sectionLabel(tr('Wo stehst du gerade?')),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final s in others) _stageChip(s)]),
            const SizedBox(height: 18),
            _sectionLabel(tr('Oder frag einfach')),
            const SizedBox(height: 8),
            for (final s in chips) _suggestion(s),
            const SizedBox(height: 10),
            _trustLine(),
          ]),
        ),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const _HeroOrb(),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _guest
                  ? tr('Hi, ich bin Buddy.')
                  : (name != null ? tr('Hey {name}, was steht an?', {'name': name}) : tr('Hey, was steht an?')),
              style: const TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Text(
          _guest
              ? tr('Frag mich alles rund um Geld im ersten Job, ohne Anmeldung. Ich sag dir, was du als Nächstes tun kannst.')
              : tr('Ich sag dir, was du jetzt tun kannst, mit deinen echten Zahlen.'),
          style: TextStyle(fontSize: 15, color: AppColors.textDim, height: 1.45),
        ),
        const SizedBox(height: 18),
        if (stage != null) ...[
          _stageProgress(stage),
          const SizedBox(height: 18),
        ],
        _sectionLabel(stage == null ? tr('Wo stehst du gerade?') : tr('Andere Lebenslagen')),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final s in others) _stageChip(s)]),
        const SizedBox(height: 18),
        _sectionLabel(tr('Oder frag einfach')),
        const SizedBox(height: 8),
        for (final s in chips) _suggestion(s),
        const SizedBox(height: 10),
        _trustLine(),
      ],
    );
  }

  Widget _stageChip(LifeStage s) => Material(
        color: AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => _openStage(s),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(s.icon, size: 17, color: AppColors.brand),
              const SizedBox(width: 7),
              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
            ]),
          ),
        ),
      );

  Widget _sectionLabel(String text) => Text(text.toUpperCase(),
      style: TextStyle(fontSize: 11.5, letterSpacing: 0.9, fontWeight: FontWeight.w700, color: AppColors.brand));

  Widget _stageProgress(LifeStage s) {
    final done = LifeStages.progress(s);
    final next = s.steps.where((st) => !LifeStages.isDone(s, st)).firstOrNull;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => _openStage(s),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(s.icon, color: AppColors.brand, size: 20),
              const SizedBox(width: 8),
              Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              const Spacer(),
              Text(tr('{done} von {all}', {'done': done, 'all': s.steps.length}),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              for (var i = 0; i < s.steps.length; i++)
                Expanded(
                  child: Container(
                    height: 5,
                    margin: EdgeInsets.only(right: i < s.steps.length - 1 ? 4 : 0),
                    decoration: BoxDecoration(
                      color: LifeStages.isDone(s, s.steps[i]) ? AppColors.brand : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ]),
            if (next != null) ...[
              const SizedBox(height: 14),
              Text(tr('Als Nächstes'), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(child: Text(next.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                FilledButton(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppColors.brand,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => _send(next.prompt),
                  child: Text(tr('Loslegen')),
                ),
              ]),
            ] else ...[
              const SizedBox(height: 12),
              Text(tr('Alles erledigt. Stark.'),
                  style: TextStyle(color: AppColors.positiveText, fontWeight: FontWeight.w700)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _suggestion(BuddyChip s) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _send(s.text),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(children: [
                Icon(s.icon, color: AppColors.brand, size: 19),
                const SizedBox(width: 12),
                Expanded(child: Text(s.text, style: const TextStyle(fontWeight: FontWeight.w600))),
                Icon(Icons.arrow_forward_rounded, color: AppColors.textDim, size: 17),
              ]),
            ),
          ),
        ),
      );

  Widget _trustLine() {
    final text = _guest
        ? tr('Ohne Konto gehen nur deine Fragen an die KI, keine Finanzdaten. Mit Konto rechnet Buddy mit deinen echten Zahlen.')
        : _live == false
            ? tr('Offline-Modus: Buddy rechnet auf deinem Gerät. KI-Antworten brauchen Internet und „KI an“.')
            : tr('Buddy bereitet vor, du entscheidest. Nichts wird gespeichert, bevor du es bestätigst.');
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(_guest ? Icons.lock_outline_rounded : Icons.verified_user_outlined, size: 16, color: AppColors.textDim),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4))),
    ]);
  }

  Widget _aiOffBanner() {
    return Material(
      color: AppColors.surfaceAlt,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.textDim),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('KI ist aus. Buddy antwortet offline aus deinen Daten.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35),
            ),
          ),
          TextButton(onPressed: _toggleAi, child: Text(tr('Einschalten'))),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ chat

  int get _guestAnswers => _messages.where((m) => !m.fromUser && !m.error && !m.streaming).length;

  bool get _showCta => _guest && !_ctaClosed && !_thinking && _guestAnswers >= 2;

  Widget _chat() {
    final count = _messages.length + (_showCta ? 1 : 0);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: count,
      itemBuilder: (_, i) {
        if (i == _messages.length) return _signUpCard();
        final m = _messages[i];
        final prev = i > 0 ? _messages[i - 1] : null;
        final newDay = prev == null || !_sameDay(prev.at, m.at);
        final first = prev == null || prev.fromUser != m.fromUser || newDay;
        final last = i == _messages.length - 1;
        final bubble = m.fromUser ? _userBubble(m) : _buddyMessage(m, first: first, last: last);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (newDay) _dayChip(m.at),
          _Appear(key: ObjectKey(m), animate: !m.restored, child: bubble),
        ]);
      },
    );
  }

  Widget _dayChip(DateTime at) {
    final now = DateTime.now();
    final label = _sameDay(at, now)
        ? tr('Heute')
        : _sameDay(at, now.subtract(const Duration(days: 1)))
            ? tr('Gestern')
            : Dates.dayMonth(at);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
          child: Text(label,
              style: TextStyle(fontSize: 11.5, color: AppColors.textDim, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  Widget _userBubble(_Message m) => Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onLongPress: () => _message(m),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width.clamp(0, 480) * 0.8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                  bottomLeft: Radius.circular(22),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                if (m.image != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.memory(m.image!, height: 150, fit: BoxFit.cover),
                  ),
                if (m.image != null && m.text.isNotEmpty) const SizedBox(height: 8),
                if (m.text.isNotEmpty)
                  Text(m.text, style: TextStyle(color: AppColors.onPrimary, fontSize: 15.5, height: 1.4)),
              ]),
            ),
          ),
        ),
      );

  Widget _buddyMessage(_Message m, {required bool first, required bool last}) {
    final text = BuddyMarkers.parse(m.text).text;
    final waiting = text.isEmpty && m.streaming;
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 30,
          child: first
              ? Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: BuddyOrb(
                      size: 28,
                      mood: m.streaming
                          ? BuddyMood.thinking
                          : (m.checkIn && last ? BuddyMood.alert : BuddyMood.idle)))
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (m.checkIn)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(Icons.notifications_none_rounded, size: 14, color: AppColors.brand),
                  const SizedBox(width: 4),
                  Text(tr('Buddy meldet sich'),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brand)),
                ]),
              ),
            GestureDetector(
              onLongPress: waiting ? null : () => _message(m),
              child: m.error
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(text, style: TextStyle(color: AppColors.text, height: 1.45)),
                    )
                  : Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: waiting ? const TypingDots() : RichMarkdown(text, streaming: m.streaming, onAsk: _send),
                    ),
            ),
            if (m.offline && text.isNotEmpty && !m.error && !m.streaming)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    m.degraded
                        ? (_guest
                            ? tr('KI gerade nicht verfügbar · Antwort aus Buddys Grundwissen')
                            : tr('KI gerade ausgelastet · Antwort offline aus deinen Daten'))
                        : (_guest ? tr('Ohne KI · aus Buddys Grundwissen') : tr('Ohne KI berechnet aus deinen Daten')),
                    style: TextStyle(fontSize: 11, color: AppColors.textDim)),
              ),
            if (m.entries.isNotEmpty && !m.streaming) _confirmNote(),
            if (!m.streaming)
              for (var i = 0; i < m.entries.length; i++) _entryCard(m, i),
            if (m.remember != null) _rememberCard(m),
            if (m.actions.isNotEmpty && !m.streaming)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in m.actions)
                    _Pill(
                      icon: a.icon,
                      label: a.label,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        a.run(context);
                      },
                    ),
                ]),
              ),
            if (last && m.followUps.isNotEmpty && !m.streaming && !_thinking)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in m.followUps)
                    _Pill(icon: Icons.subdirectory_arrow_right_rounded, label: f, quiet: true, onTap: () => _follow(f)),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _confirmNote() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textDim),
          const SizedBox(width: 5),
          Text(tr('Passiert erst, wenn du bestätigst'),
              style: TextStyle(fontSize: 11.5, color: AppColors.textDim, fontWeight: FontWeight.w500)),
        ]),
      );

  // one proposed entry; nothing is stored until "Übernehmen"
  Widget _entryCard(_Message m, int i) {
    final e = m.entries[i];
    final done = m.applied[i];
    final dropped = m.dismissed.contains(i);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: dropped ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: done == null && !dropped ? AppColors.brand.withValues(alpha: 0.55) : AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(e.title, style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(e.summary, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: done != null
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                      child: Text('✓ $done',
                          style: TextStyle(color: AppColors.positiveText, fontWeight: FontWeight.w700)),
                    )
                  : dropped
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          child: Text(tr('Verworfen'),
                              style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
                        )
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(
                            style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact, foregroundColor: AppColors.textDim),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => m.dismissed.add(i));
                            },
                            child: Text(tr('Verwerfen')),
                          ),
                          const SizedBox(width: 4),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: AppColors.brand,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _apply(m, i),
                            child: Text(tr('Übernehmen')),
                          ),
                        ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _rememberCard(_Message m) {
    final state = m.rememberState;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: state == null ? AppColors.brand.withValues(alpha: 0.45) : Colors.transparent),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(state == 'saved' ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                size: 19, color: AppColors.brand),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  state == 'saved'
                      ? tr('Gemerkt')
                      : state == 'known'
                          ? tr('Weiß ich schon')
                          : state == 'no'
                              ? tr('Nicht gemerkt')
                              : tr('Soll Buddy sich das merken?'),
                  style: TextStyle(fontSize: 12, color: AppColors.textDim, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(m.remember!, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
            ]),
          ),
        ]),
        if (state == null || state == 'saved')
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (state == null) ...[
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.textDim),
                    onPressed: () => setState(() => m.rememberState = 'no'),
                    child: Text(tr('Nein')),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () => _remember(m),
                    child: Text(tr('Merken')),
                  ),
                ] else
                  TextButton(
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const BuddyMemoryScreen())),
                    child: Text(tr('Ansehen')),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _signUpCard() => Padding(
        padding: const EdgeInsets.only(left: 42, bottom: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
          decoration: BoxDecoration(
            color: AppColors.brand.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.brand.withValues(alpha: 0.35)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(tr('Soll ich mit deinen echten Zahlen rechnen?'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
              ),
              IconButton(
                tooltip: tr('Schließen'),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _ctaClosed = true),
                icon: Icon(Icons.close_rounded, size: 18, color: AppColors.textDim),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                tr('Mit einem kostenlosen Konto weiß ich, was du ausgibst, und sage dir, was bis Monatsende bleibt. Unser Chat kommt mit.'),
                style: TextStyle(color: AppColors.textDim, height: 1.4, fontSize: 13.5),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand, foregroundColor: Colors.white),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SignUpScreen())),
              child: Text(tr('Kostenlos starten')),
            ),
          ]),
        ),
      );

  // ----------------------------------------------------------------- input

  Widget _inputBar() {
    final canSend = (_input.text.trim().isNotEmpty || _photo != null) && !_thinking;
    final note = _quotaLine;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_photo != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_photo!.bytes, height: 72, width: 72, fit: BoxFit.cover),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      tooltip: tr('Foto entfernen'),
                      visualDensity: VisualDensity.compact,
                      style: IconButton.styleFrom(backgroundColor: Colors.black54),
                      onPressed: () => setState(() => _photo = null),
                      icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.fromLTRB(4, 4, 5, 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: _focus.hasFocus ? AppColors.textDim.withValues(alpha: 0.6) : AppColors.border),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (!_guest)
                IconButton(
                  tooltip: tr('Foto senden'),
                  onPressed: _thinking ? null : _pickPhoto,
                  icon: Icon(Icons.add_rounded, color: AppColors.textDim),
                )
              else
                const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: _send,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 15.5),
                  decoration: InputDecoration(
                    hintText: VoiceInput.listening.value
                        ? tr('Ich höre zu …')
                        : (_guest ? tr('Frag Buddy etwas …') : tr('Frag Buddy oder erzähl was …')),
                    hintMaxLines: 1,
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // empty field: talk instead of typing; with text: send
              if (!canSend && !_thinking && _photo == null)
                ValueListenableBuilder<bool>(
                  valueListenable: VoiceInput.listening,
                  builder: (_, on, __) => Semantics(
                    button: true,
                    label: on ? tr('Zuhören beenden') : tr('Sprechen'),
                    child: GestureDetector(
                      onTap: _voice,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: on ? AppColors.brand : AppColors.surfaceAlt,
                          boxShadow: on
                              ? [BoxShadow(color: AppColors.brand.withValues(alpha: 0.5), blurRadius: 14, spreadRadius: 1)]
                              : null,
                        ),
                        child: Icon(on ? Icons.stop_rounded : Icons.mic_none_rounded,
                            size: 21, color: on ? Colors.white : AppColors.text),
                      ),
                    ),
                  ),
                )
              else
                Semantics(
                  button: true,
                  label: tr('Senden'),
                  enabled: canSend,
                  child: GestureDetector(
                    onTap: () => _send(_input.text),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: canSend ? AppColors.brand : AppColors.surfaceAlt,
                      ),
                      child:
                          Icon(Icons.arrow_upward_rounded, size: 21, color: canSend ? Colors.white : AppColors.textDim),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 5),
          if (PlusService.syncError.value != null && !_guest)
            GestureDetector(
              onTap: () => PlusService.syncWithServer(fresh: true),
              child: Text(tr('{syncError} Erneut versuchen', {'syncError': PlusService.syncError.value}),
                  style: TextStyle(fontSize: 11, color: AppColors.textDim, decoration: TextDecoration.underline)),
            )
          else
            Text(
              [if (note != null) note, tr('Buddy kann sich irren, keine Anlageberatung')].join(' · '),
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 12, color: AppColors.textDim, height: 1.3),
            ),
        ]),
      ),
    );
  }
}

class _Message {
  final bool fromUser;
  String text;
  final DateTime at;
  bool offline;
  bool degraded = false; // live KI failed → offline fallback
  bool error = false;
  bool streaming = false;
  bool restored = false; // from last time: no entry animation
  bool checkIn = false; // Buddy spoke first
  List<BuddyAction> actions = const []; // next steps under an answer
  List<BuddyEntry> entries = const []; // what Buddy would book, each confirmed by the user
  final Map<int, String> applied = {}; // entry index -> what was done
  final Set<int> dismissed = {}; // entries the user waved away
  List<String> followUps = const [];
  String? remember; // a fact Buddy suggests to keep
  String? rememberState; // saved, known, no
  Uint8List? image; // a photo the user sent
  _Message(this.fromUser, this.text, {DateTime? at, this.offline = false, this.image}) : at = at ?? DateTime.now();
}

// a short fade and lift for new messages
class _Appear extends StatefulWidget {
  final Widget child;
  final bool animate;
  const _Appear({super.key, required this.child, this.animate = true});

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: widget.animate ? 0 : 1)
        ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(curve),
        child: widget.child,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool quiet;
  const _Pill({required this.icon, required this.label, required this.onTap, this.quiet = false});

  @override
  Widget build(BuildContext context) => Material(
        color: quiet ? Colors.transparent : AppColors.surface,
        shape: StadiumBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: quiet ? AppColors.textDim : AppColors.brand),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text)),
              ),
            ]),
          ),
        ),
      );
}

// the large orb on the welcome screen, breathing slowly
class _HeroOrb extends StatefulWidget {
  const _HeroOrb();

  @override
  State<_HeroOrb> createState() => _HeroOrbState();
}

class _HeroOrbState extends State<_HeroOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = Curves.easeInOut.transform(_c.value);
            return Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(alpha: 0.18 + 0.17 * t),
                    blurRadius: 18 + 14 * t,
                    spreadRadius: 1 + 3 * t,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: const BuddyOrb(size: 52),
        ),
      );
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
    return Container(
      padding: const EdgeInsets.all(1.25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: AppColors.border,
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
                    Text(tip != null ? tr('Buddy hat einen Tipp') : tr('Frag Buddy'),
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

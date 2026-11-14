// Buddy, the AI finance coach. Uses Claude through the Ahead server
// when the user is signed in and the server has AI configured; otherwise the
// offline answers of LocalBuddy and the offline QuickParser.
import 'money_accounts.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import '../l10n/l10n.dart';
import '../models/goal.dart';
import '../models/holding.dart';
import '../models/money_account.dart';
import '../models/split.dart';
import '../models/transaction.dart';
import '../utils/theme.dart';
import 'account_service.dart';
import 'backend_service.dart';
import 'buddy_memory.dart';
import 'buddy_proposals.dart';
import 'buddy_tasks.dart';
import 'buddy_tools.dart';
import 'life_stages.dart';
import 'db.dart';
import 'finance_snapshot.dart';
import 'goals_service.dart';
import 'onboarding_service.dart';
import 'ledger_busy.dart';
import 'forecast_service.dart';
import 'local_buddy.dart';
import 'plus_service.dart';
import 'quick_parser.dart';
import 'recurring_service.dart';
import 'split_service.dart';
import 'vorsorge.dart';
import 'wealth.dart';

class ChatMessage {
  final bool fromUser;
  final String text;
  const ChatMessage(this.fromUser, this.text);
}

class BuddyService {
  static bool? _serverAi;
  // the server runs Buddy as an agent with tools (Claude); otherwise the
  // older one-shot chat with a summary of the finances (Gemini fallback)
  static bool _serverAgent = false;
  // what Buddy is looking at while he works ("deine Ausgaben"), for the chat
  static final activity = ValueNotifier<String?>(null);
  // seams for tests
  @visibleForTesting
  static http.Client Function() client = http.Client.new;
  // the tools on this device (tests and the test catalog swap them)
  static BuddyTools Function() tools = BuddyTools.device;
  // who answers on the server: 'anthropic', or 'google' (Gemini, free tier)
  static String provider = 'anthropic';

  static Box get _settings => Hive.box('settings');
  // Anthropic and Google each have their own consent key
  static String get consentKey => provider == 'google' ? 'aiConsentGoogle' : 'aiConsent';

  // Profil-Schalter und Buddy-Frage: true = Daten dürfen zur KI
  static bool get hasConsent => _settings.get(consentKey) == true;

  // Profil: An/Aus für beide Provider, damit ein Server-Wechsel den Schalter nicht umgeht
  static Future<void> setConsent(bool on) async {
    await _settings.put('aiConsent', on);
    await _settings.put('aiConsentGoogle', on);
  }

  // true when the server has AI configured (ignores consent, used to offer the ask)
  static Future<bool> live() async {
    // signed in + server with AI, consent is checked separately before sending data
    if (AccountService.current.value == null) return false;
    if (_serverAi != null) return _serverAi!;
    try {
      final res = await http.get(Uri.parse('${BackendService.base}/health')).timeout(const Duration(seconds: 4));
      final health = jsonDecode(res.body) as Map;
      _serverAi = res.statusCode == 200 && health['ai'] == true;
      provider = '${health['aiProvider'] ?? 'anthropic'}';
      _serverAgent = health['agent'] == true;
    } catch (_) {
      return false; // offline now; ask again next time
    }
    return _serverAi!;
  }

  // server AI and user consent, the only path that may leave the device
  static Future<bool> liveAllowed() async => await live() && hasConsent;

  static FinanceSnapshot snapshot() {
    final tx = DB.getTx();
    final holdings = DB.getHoldings();
    final goals = _goals();
    final today = DateTime.now();
    final cushion = _cushion(tx, today);
    return FinanceSnapshot.build(
      tx: tx,
      openingCents: MoneyAccounts.openingTotal,
      budgets: DB.getBudgets(),
      holdings: holdings,
      now: today,
      accounts: _accounts(tx),
      accountNames: _accountNames(),
      goals: goals,
      recurring: _recurring(),
      splits: _splits(),
      debts: _debts(),
      policies: _policies(),
      emergencyTargetCents: cushion.target,
      emergencyHaveCents: cushion.have,
      vorsorge: _vorsorge(holdings, goals),
      plus: _plus(today),
    );
  }

  // what the month leaves after fixed costs, when the balance is known
  static int? freeCents() => _try(() {
        if (!OnboardingService.balanceKnown) return null;
        final tx = DB.getTx();
        if (tx.isEmpty) return null;
        final cash = LedgerBusy.cashOr(DB.balanceOf(tx) + MoneyAccounts.openingTotal);
        return ForecastService.build(tx, goals: GoalsService.all(), balanceCents: cash)?.freeCents;
      }, null);

  static T _try<T>(T Function() fn, T fallback) {
    try {
      return fn();
    } catch (_) {
      return fallback;
    }
  }

  static List<Goal> _goals() => _try(
        () => Hive.isBoxOpen('goals') ? GoalsService.all() : const <Goal>[],
        const <Goal>[],
      );

  static List<AccountSnap> _accounts(List<Transaction> tx) => _try(() {
        if (!Hive.isBoxOpen('settings')) return const <AccountSnap>[];
        return [
          for (final a in MoneyAccounts.all)
            (name: a.name, art: MoneyAccount.kinds[a.kind] ?? 'Konto', cents: MoneyAccounts.balanceOf(a, tx)),
        ];
      }, const <AccountSnap>[]);

  static Map<String, String> _accountNames() => _try(() {
        if (!Hive.isBoxOpen('settings')) return const {};
        return {for (final a in MoneyAccounts.all) a.id: a.name};
      }, const {});

  static List<RecurringSnap> _recurring() => _try(() {
        final rules = DB.getRules();
        rules.sort((a, b) {
          if (a.active != b.active) return a.active ? -1 : 1;
          return b.amountCents.compareTo(a.amountCents);
        });
        return [
          for (final r in rules.take(20))
            (
              title: (r.note?.trim().isNotEmpty ?? false) ? r.note!.trim() : r.category,
              cents: r.amountCents,
              income: r.isIncome,
              category: r.category,
              interval: r.interval,
              active: r.active,
              next: RecurringService.nextDate(r).toIso8601String().substring(0, 10),
            ),
        ];
      }, const <RecurringSnap>[]);

  static List<SplitSnap> _splits() => _try(() {
        if (!Hive.isBoxOpen('splits')) return const <SplitSnap>[];
        return [for (final g in SplitService.all().take(8)) _split(g)];
      }, const <SplitSnap>[]);

  static SplitSnap _split(SplitGroup g) {
    final b = SplitMath.balances(g);
    final me = g.members.isEmpty ? 0 : g.me.clamp(0, g.members.length - 1);
    return (
      name: g.name,
      myCents: me < b.length ? b[me] : 0,
      salden: [
        for (var i = 0; i < g.members.length && i < b.length; i++) (name: g.members[i], cents: b[i]),
      ],
      ausgleich: [
        for (final t in SplitMath.settleUp(g).take(6))
          if (t.from < g.members.length && t.to < g.members.length)
            (von: g.members[t.from], an: g.members[t.to], cents: t.cents),
      ],
    );
  }

  static List<({String name, int cents})> _debts() => _try(() {
        if (!Hive.isBoxOpen('settings')) return const [];
        return [for (final d in Wealth.debts().take(15)) (name: d.name, cents: d.cents)];
      }, const []);

  static List<({String name, int monthlyCents})> _policies() => _try(() {
        if (!Hive.isBoxOpen('settings')) return const [];
        return [for (final p in Wealth.policies().take(15)) (name: p.name, monthlyCents: p.monthlyCents)];
      }, const []);

  static ({int? target, int have}) _cushion(List<Transaction> tx, DateTime today) => _try(() {
        if (!Hive.isBoxOpen('settings')) return (target: null, have: 0);
        final fund = Wealth.emergency(tx, now: today);
        return (target: fund.targetCents > 0 ? fund.targetCents : null, have: fund.haveCents);
      }, (target: null, have: 0));

  static VorsorgeResult? _vorsorge(List<Holding> holdings, List<Goal> goals) => _try(() {
        if (!Hive.isBoxOpen('settings') || !Vorsorge.configured) return null;
        return Vorsorge.build(input: Vorsorge.load(), holdings: holdings, goals: goals);
      }, null);

  static PlusSnap _plus(DateTime today) => _try(() {
        final sub = PlusService.subscription.value;
        final on = PlusService.active.value && sub != null;
        String? bis;
        if (on) {
          final end = sub.inTrial(today)
              ? sub.trialEnds
              : sub.cancelled
                  ? sub.endsAt!
                  : sub.periodEnd(today);
          bis = end.toIso8601String().substring(0, 10);
        }
        int? left(PlusFeature f) {
          if (on || !Hive.isBoxOpen('settings')) return null;
          return PlusService.left(f, now: today);
        }

        return (
          active: on,
          plan: on ? (sub.plan == PlusPlan.yearly ? 'jährlich' : 'monatlich') : null,
          trial: on && sub.inTrial(today),
          cancelled: on && sub.cancelled,
          bis: bis,
          fragenRest: left(PlusFeature.aiQuestion),
          scansRest: left(PlusFeature.receiptScan),
        );
      }, FinanceSnapshot.plusOff);

  // Buddy's answer to the last user message, piece by piece
  static Stream<String> ask(List<ChatMessage> history, {required bool live}) async* {
    if (!live) {
      // offline: the answer is ready at once; hand it out in small pieces so
      // it reads like the live one
      final text = LocalBuddy.answer(
        history.last.text,
        snapshot(),
        history: [for (final m in history) (fromUser: m.fromUser, text: m.text)],
      );
      for (final word in RegExp(r'\S+\s*').allMatches(text)) {
        await Future.delayed(const Duration(milliseconds: 18));
        yield word.group(0)!;
      }
      return;
    }

    if (_serverAgent) {
      yield* _agent(history);
      return;
    }

    final req = http.Request('POST', Uri.parse('${BackendService.base}/ai/chat'))
      ..headers.addAll({'Content-Type': 'application/json', ...BackendService.authHeaders})
      ..body = jsonEncode({
        'finances': {
          ...snapshot().toJson(),
          // facts the person let Buddy remember, and their life stage
          'erinnerungen': BuddyMemory.texts(),
          if (LifeStages.snapshot() != null) 'lebenslage': LifeStages.snapshot(),
        },
        'history': [
          for (final m in history) {'role': m.fromUser ? 'user' : 'assistant', 'text': m.text}
        ],
      });
    final client = http.Client();
    try {
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        final body = await res.stream.bytesToString();
        throw _error(body, res.statusCode);
      }
      await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) continue;
        final event = jsonDecode(line.substring(6)) as Map<String, dynamic>;
        if (event['t'] != null) yield event['t'] as String;
        if (event['error'] != null) throw '${event['error']}';
      }
    } finally {
      client.close();
    }
  }

  // Buddy as an agent: the server asks Claude, the tools run here. Each step
  // streams text; when Claude asks for tools, they run on this device and
  // their results go into the next step. At most 6 steps; the last one has
  // to answer with what it has.
  static const maxSteps = 6;

  @visibleForTesting
  static void useAgent(bool on) => _serverAgent = on;

  static Map<String, dynamic> _context() => {
        if (AccountService.current.value != null) 'name': AccountService.current.value!.firstName,
        'erinnerungen': BuddyMemory.textsForAgent(),
        if (LifeStages.snapshot() != null) 'lebenslage': LifeStages.snapshot(),
        'offeneAufgaben': BuddyTasks.forAgent(),
        'sprache': L10n.lang.value,
      };

  // the cards and charts the last answer's tools produced, taken once by the chat
  static BuddyTools? _lastTools;
  static ({List<BuddyProposal> proposals, List<BuddyChart> charts, List<String> tools}) takeExtras() {
    final t = _lastTools;
    _lastTools = null;
    return (proposals: [...?t?.proposals], charts: [...?t?.charts], tools: [...?t?.used]);
  }

  // a thumbs up or down; question and answer go along so the team can turn a
  // bad answer into a test case
  static Future<void> feedback({
    required bool up,
    required String question,
    required String answer,
    String reason = '',
    String note = '',
    List<String> tools = const [],
  }) async {
    try {
      await http
          .post(Uri.parse('${BackendService.base}/ai/feedback'),
              headers: {'Content-Type': 'application/json', ...BackendService.authHeaders},
              body: jsonEncode({
                'rating': up ? 'up' : 'down',
                'reason': reason,
                'note': note,
                'question': question,
                'answer': answer,
                'tools': tools,
                'lang': L10n.lang.value,
              }))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // feedback is a bonus: never bother the person when it does not arrive
    }
  }

  static Stream<String> _agent(List<ChatMessage> history) async* {
    final messages = <Map<String, dynamic>>[
      for (final m in history)
        if (m.text.trim().isNotEmpty) {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}
    ];
    Map<String, dynamic> context;
    try {
      context = _context();
    } catch (_) {
      context = {};
    }
    // the tools of this answer; their short summary goes along at once
    BuddyTools? toolbox;
    _lastTools = null;
    try {
      toolbox = tools();
      _lastTools = toolbox;
      context = {...context, 'kurzinfo': toolbox.kurzinfo()};
    } catch (_) {}
    var wrote = false;
    try {
      for (var step = 0; step < maxSteps; step++) {
        final req = http.Request('POST', Uri.parse('${BackendService.base}/ai/agent'))
          ..headers.addAll({'Content-Type': 'application/json', ...BackendService.authHeaders})
          ..body = jsonEncode({'messages': messages, 'context': context, 'last': step == maxSteps - 1});
        final conn = client();
        Map<String, dynamic>? done;
        var stepWrote = false;
        try {
          final res = await conn.send(req).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) {
            final body = await res.stream.bytesToString();
            throw _error(body, res.statusCode);
          }
          await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
            if (!line.startsWith('data: ')) continue;
            final event = jsonDecode(line.substring(6)) as Map<String, dynamic>;
            if (event['t'] != null) {
              // a new step after earlier text starts a new paragraph
              if (!stepWrote && wrote) yield '\n\n';
              activity.value = null;
              stepWrote = wrote = true;
              yield event['t'] as String;
            }
            if (event['step'] != null) done = (event['step'] as Map).cast<String, dynamic>();
            if (event['error'] != null) throw '${event['error']}';
          }
        } finally {
          conn.close();
        }
        if (done == null) throw 'Buddy hat nicht zu Ende geantwortet. Bitte gleich noch einmal.';
        final calls = [for (final c in (done['tools'] as List? ?? const [])) (c as Map).cast<String, dynamic>()];
        if (calls.isEmpty) return;
        toolbox ??= tools();
        _lastTools = toolbox;
        activity.value = '${calls.first['zeigt'] ?? 'deine Zahlen'}';
        messages.add({'role': 'assistant', 'content': done['content']});
        messages.add({
          'role': 'user',
          'content': [
            for (final c in calls)
              () {
                final result = toolbox!.run('${c['name']}', (c['input'] as Map?)?.cast<String, dynamic>() ?? const {});
                return {
                  'type': 'tool_result',
                  'tool_use_id': c['id'],
                  'content': jsonEncode(result),
                  if (result.containsKey('fehler')) 'is_error': true,
                };
              }(),
          ],
        });
      }
    } finally {
      activity.value = null;
    }
  }

  static List<String> get _categories => <String>{
        for (final c in Categories.expense) c['name']!,
        for (final c in Categories.income) c['name']!,
      }.toList();

  // a quick note -> booking; Claude when live + consented, otherwise the offline parser
  static Future<ParsedBooking?> parse(String text) async {
    final local = QuickParser.parse(text);
    if (!await liveAllowed()) return local;
    try {
      final res = await http
          .post(Uri.parse('${BackendService.base}/ai/parse'),
              headers: {'Content-Type': 'application/json', ...BackendService.authHeaders},
              body: jsonEncode({'text': text, 'categories': _categories}))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return local;
      return _booking((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['booking'] as Map) ?? local;
    } catch (_) {
      return local;
    }
  }

  // a photo of a receipt -> booking (needs the AI and consent)
  static Future<ParsedBooking> receipt(Uint8List bytes, String mediaType) async {
    if (AccountService.current.value == null) {
      throw 'Belege scannen geht mit einem kostenlosen Konto.';
    }
    if (!await live()) throw 'Belege scannen braucht die KI auf dem Server.';
    if (!hasConsent) throw 'Belege scannen braucht „Buddy mit KI“ in den Einstellungen.';
    final res = await http
        .post(Uri.parse('${BackendService.base}/ai/receipt'),
            headers: {'Content-Type': 'application/json', ...BackendService.authHeaders},
            body: jsonEncode({'image': base64Encode(bytes), 'mediaType': mediaType, 'categories': _categories}))
        .timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) throw _error(res.body, res.statusCode);
    final booking = _booking((jsonDecode(utf8.decode(res.bodyBytes)) as Map)['booking'] as Map);
    if (booking == null) throw 'Auf dem Bild habe ich keinen Betrag gefunden.';
    return booking;
  }

  static ParsedBooking? _booking(Map b) {
    final amount = (b['amount'] as num?)?.toDouble() ?? 0;
    if (amount <= 0) return null;
    final date = DateTime.tryParse('${b['date']}') ?? DateTime.now();
    return ParsedBooking(
      (amount * 100).round(),
      b['isIncome'] == true,
      '${b['category'] ?? 'Sonstiges'}',
      '${b['note'] ?? ''}'.trim(),
      DateTime(date.year, date.month, date.day, 12),
    );
  }

  static String _error(String body, int status) {
    try {
      return '${(jsonDecode(body) as Map)['error']}';
    } catch (_) {
      return 'Buddy ist gerade nicht erreichbar ($status).';
    }
  }
}

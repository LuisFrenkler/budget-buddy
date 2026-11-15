// Push notifications: Buddy speaks up before something goes wrong.
//
// Two kinds:
// - reminders planned ahead (weekly report on Sunday 18:00, the day before a
//   large fixed payment, the trial ending, the bank link running out, a goal
//   deadline). The phone shows them even when the app is closed. Browsers
//   cannot schedule, so on the web only the instant kind exists.
// - urgent hints shown right away when they come up (budget exceeded, price
//   rise, unusual expense), each one only once.
//
// Everything is off until the user turns it on; each topic can be switched
// off on its own.
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive/hive.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../models/goal.dart';
import '../models/transaction.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import 'buddy_service.dart';
import 'buddy_tasks.dart';
import 'cancellation_service.dart';
import 'contracts.dart';
import 'db.dart';
import 'goals_service.dart';
import 'hints_service.dart';
import 'plus_service.dart';
import 'settings_service.dart';
import 'weekly_report.dart';
import '../l10n/l10n.dart';

enum NotifyTopic { spending, contracts, weekly, account, buddy }

extension NotifyTopicLabel on NotifyTopic {
  String get label => switch (this) {
        NotifyTopic.spending => tr('Budgets & Ausgaben'),
        NotifyTopic.contracts => tr('Verträge & Abbuchungen'),
        NotifyTopic.weekly => 'Wochenbericht',
        NotifyTopic.account => 'Abo & Bankverbindung',
        NotifyTopic.buddy => 'Buddy-Momente',
      };

  String get description => switch (this) {
        NotifyTopic.spending => tr('Budget überschritten, ungewöhnliche Ausgaben, Sparziele'),
        NotifyTopic.contracts => tr('Preiserhöhungen und große Abbuchungen am Tag vorher'),
        NotifyTopic.weekly => tr('Jeden Sonntag um 18 Uhr'),
        NotifyTopic.account => 'Ende des Gratis-Tests, ablaufende Bankverbindung',
        NotifyTopic.buddy => tr('Gehalt ist da, Ziel erreicht'),
      };
}

// A reminder planned for later. [payload] says where tapping it leads.
class Reminder {
  final int id;
  final DateTime when;
  final String title;
  final String body;
  final NotifyTopic topic;
  final String payload;
  const Reminder(this.id, this.when, this.title, this.body, this.topic, this.payload);
}

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  // set by the app to open the right page when a notification is tapped
  static void Function(String payload)? onTap;

  static Box get _box => Hive.box('settings');

  static final enabled = ValueNotifier<bool>(false);

  // warnings are on once notifications are; the nice-to-know ones (weekly
  // report, Buddy moments) Buddy offers in the chat after the first week
  static bool topic(NotifyTopic t) =>
      _box.get('notify_${t.name}', defaultValue: t != NotifyTopic.weekly && t != NotifyTopic.buddy) as bool;

  static Future<void> setTopic(NotifyTopic t, bool on) async {
    await _box.put('notify_${t.name}', on);
    await sync();
  }

  static Future<void> init() async {
    enabled.value = _box.get('notifyOn', defaultValue: false) as bool;
    try {
      tzdata.initializeTimeZones();
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          web: WebInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) {
          if (r.payload != null) onTap?.call(r.payload!);
        },
      );
      _ready = ok == true;
      // the app was opened by tapping a notification
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        Future.delayed(const Duration(milliseconds: 600), () => onTap?.call(payload));
      }
    } catch (_) {
      _ready = false;
    }
  }

  // why the last enable() did not work, in words for the user
  static String problem = '';

  // false when asking makes no sense: no support here, or the browser has
  // already been told "no" (it will not ask again). Prompts then stay away.
  static bool get canAsk {
    if (enabled.value) return true;
    if (!_ready) return false;
    if (kIsWeb) {
      final web = _plugin.resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>();
      if (web != null && web.permissionStatus == WebNotificationPermission.denied) return false;
    }
    return true;
  }

  // asks the system for permission; call only from a tap
  static Future<bool> enable() async {
    if (!_ready) await init();
    if (!_ready) {
      problem = tr('Dieser Browser unterstützt keine Mitteilungen. In der App für iPhone und Android geht es.');
      return false;
    }
    bool? granted;
    if (kIsWeb) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      granted = await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } else {
      granted = true;
    }
    if (granted != true) {
      problem = tr('Mitteilungen sind ausgeschaltet. Du kannst sie in den Einstellungen {x} für Ahead erlauben.', {'x': kIsWeb ? 'deines Browsers' : tr('deines Geräts')});
      return false;
    }
    await _box.put('notifyOn', true);
    enabled.value = true;
    // what is already on screen should not arrive as a burst of pushes
    await _markShown(_urgentHints(DateTime.now()).map((h) => h.id));
    await sync();
    return true;
  }

  static Future<void> disable() async {
    await _box.put('notifyOn', false);
    enabled.value = false;
    if (_ready) await _plugin.cancelAllPendingNotifications();
  }

  // a short confirmation right after turning it on
  static Future<void> hello() => _show(
        1,
        tr('Buddy meldet sich ab jetzt'),
        tr('Nur wenn es wichtig ist. Du kannst das jederzeit im Profil ändern.'),
        'home',
      );

  static NotificationDetails get _details => NotificationDetails(
    android: AndroidNotificationDetails(
      'buddy',
      'Buddy',
      channelDescription: tr('Hinweise, Erinnerungen und Wochenbericht'),
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    web: WebNotificationDetails(),
  );

  static Future<void> _show(int id, String title, String body, String payload) async {
    if (!_ready || !enabled.value) return;
    try {
      await _plugin.show(id: id, title: title, body: body, notificationDetails: _details, payload: payload);
    } catch (_) {}
  }

  static Set<String> get _shown => ((_box.get('notifiedHints') as List?) ?? const []).cast<String>().toSet();

  static Future<void> _markShown(Iterable<String> ids) async {
    // writing an unchanged list would rebuild every screen that listens to settings
    if (ids.isEmpty) return;
    final list = [..._shown, ...ids];
    await _box.put('notifiedHints', list.length > 300 ? list.sublist(list.length - 300) : list);
  }

  static NotifyTopic? _topicOf(HintKind k) => switch (k) {
        HintKind.budgetOver || HintKind.budgetClose || HintKind.budgetUnreal || HintKind.bigExpense || HintKind.lowMonth =>
          NotifyTopic.spending,
        HintKind.salaryIn || HintKind.salaryUp || HintKind.taxReturn || HintKind.goalReached || HintKind.monthReview || HintKind.goalBehind => NotifyTopic.buddy,
        HintKind.doubleCharge || HintKind.bankFees || HintKind.returnedDebit || HintKind.dunning => NotifyTopic.contracts,
        HintKind.overdraft => NotifyTopic.spending,
        HintKind.weekPlan => NotifyTopic.buddy,
        HintKind.priceUp || HintKind.stillCharging => NotifyTopic.contracts,
        _ => null, // the rest is planned ahead as a reminder
      };

  static List<Hint> _urgentHints(DateTime now) => HintsService.build(
        tx: DB.getTx(),
        budgets: DB.getBudgets(),
        goals: GoalsService.all(),
        subscription: PlusService.subscription.value,
        bankValidUntil: Settings.bankValidUntil,
        cancellations: CancellationService.all,
        freeCents: BuddyService.freeCents(),
        balanceCents: BuddyService.cashCents(),
        now: now,
      ).where((h) => _topicOf(h.kind) != null).toList();

  static int _idFor(String key) => key.hashCode & 0x3fffffff;

  static Timer? _debounce;

  // after a burst of changes (a bank sync, an import) sync once
  static void syncSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), sync);
  }

  // brings notifications in line with the data
  static Future<void> sync({DateTime? now}) async {
    if (!_ready || !enabled.value) return;
    final today = now ?? DateTime.now();

    // 1. urgent hints, each only once. A finance buddy that spams loses
    // trust: at most one a day and three a week, the most urgent first
    final seen = _shown;
    final log = _sentLog(today);
    final room = quietRoom(log, today);
    final fresh =
        _urgentHints(today).where((h) => !seen.contains(h.id) && topic(_topicOf(h.kind)!)).take(room).toList();
    for (final h in fresh) {
      // a hint with a question opens Buddy's chat with it
      await _show(_idFor(h.id), h.title, h.text, h.question != null ? 'buddy:${h.question}' : 'hint:${h.target.name}');
    }
    await _markShown(fresh.map((h) => h.id));
    if (fresh.isNotEmpty) await _box.put('notifyLog', [...log, for (final _ in fresh) today.toIso8601String()]);

    // 2. the browser cannot schedule: show this week's report once when it is ready
    if (kIsWeb) {
      if (topic(NotifyTopic.weekly)) {
        final report = WeeklyReportService.build(DB.getTx(), now: today);
        final key = 'weekly-${report?.start.toIso8601String().substring(0, 10)}';
        final fresh = report != null && today.difference(report.end).inDays < 2 && !_shown.contains(key);
        if (fresh) {
          await _show(_idFor(key), tr('Dein Wochenbericht ist da'), report.summary, 'weekly');
          await _markShown([key]);
        }
      }
      return;
    }

    // 3. reminders ahead, replaced on every sync
    try {
      await _plugin.cancelAllPendingNotifications();
      final planned = plan(
        tx: DB.getTx(),
        goals: GoalsService.all(),
        subscription: PlusService.subscription.value,
        bankValidUntil: Settings.bankValidUntil,
        tasks: [
          for (final t in BuddyTasks.open(now: today))
            if (t.due != null) (text: t.text, due: t.due!)
        ],
        now: today,
      ).where((r) => topic(r.topic) || r.payload.startsWith('buddy:'));
      for (final r in planned) {
        await _plugin.zonedSchedule(
          id: r.id,
          // an exact instant; UTC avoids needing the device's zone name
          scheduledDate: tz.TZDateTime.from(r.when.toUtc(), tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: r.title,
          body: r.body,
          payload: r.payload,
        );
      }
    } catch (_) {}
  }

  static const maxPerWeek = 3;

  // when hints went out in the last week
  static List<String> _sentLog(DateTime now) => [
        for (final t in (_box.get('notifyLog') as List? ?? const []).cast<String>())
          if (now.difference(DateTime.tryParse(t) ?? DateTime(2000)).inDays < 7) t
      ];

  // how many hints may go out now: none if one went out today, and never
  // more than three in seven days
  static int quietRoom(List<String> log, DateTime now) {
    final times = [for (final t in log) DateTime.tryParse(t)].whereType<DateTime>();
    if (times.any((t) => t.year == now.year && t.month == now.month && t.day == now.day)) return 0;
    final week = times.where((t) => now.difference(t).inDays < 7).length;
    return (maxPerWeek - week).clamp(0, 1);
  }

  // planned nudges, calm: account things (trial ending, bank link expiring)
  // always; everything else at most once a day and three times a week
  static List<Reminder> calm(List<Reminder> planned) {
    final sorted = [...planned]..sort((a, b) => a.when.compareTo(b.when));
    final days = <String>{};
    final weeks = <String, int>{};
    final out = <Reminder>[];
    for (final r in sorted) {
      if (r.topic == NotifyTopic.account) {
        out.add(r);
        continue;
      }
      final day = '${r.when.year}-${r.when.month}-${r.when.day}';
      final monday = DateTime(r.when.year, r.when.month, r.when.day - (r.when.weekday - 1));
      final week = '${monday.year}-${monday.month}-${monday.day}';
      if (days.contains(day) || (weeks[week] ?? 0) >= maxPerWeek) continue;
      days.add(day);
      weeks[week] = (weeks[week] ?? 0) + 1;
      out.add(r);
    }
    return out;
  }

  // what to remind of, and when (pure, so it can be tested)
  static List<Reminder> plan({
    required List<Transaction> tx,
    required List<Goal> goals,
    Subscription? subscription,
    DateTime? bankValidUntil,
    // reminders the person asked Buddy for
    List<({String text, DateTime due})> tasks = const [],
    required DateTime now,
  }) {
    final out = <Reminder>[];
    DateTime at(DateTime d, int hour) => DateTime(d.year, d.month, d.day, hour);

    // asked for, so always on: in the morning of the day, the chat opens with help
    for (final t in tasks) {
      final when = at(t.due, 9);
      if (when.isAfter(now)) {
        out.add(Reminder(_idFor('task-${t.text}-${t.due}'), when, tr('Erinnerung von Buddy'), t.text, NotifyTopic.buddy,
            'buddy:Hilf mir bei diesem Schritt: ${t.text}'));
      }
    }
    DateTime before(DateTime d, int days, int hour) => DateTime(d.year, d.month, d.day - days, hour);

    final weekly = WeeklyReportService.nextReady(now);
    out.add(Reminder(_idFor('weekly-$weekly'), weekly, tr('Dein Wochenbericht ist da'),
        tr('Buddy hat deine Woche ausgewertet: was gut lief und wo noch was geht.'), NotifyTopic.weekly, 'weekly'));

    for (final c in Contracts.detect(tx, now: now)) {
      if (c.monthlyCents < 5000) continue;
      final when = before(c.nextDate, 1, 9);
      if (when.isAfter(now) && c.nextDate.difference(now).inDays <= 35) {
        out.add(Reminder(_idFor('pay-${c.name}-${c.nextDate}'), when, 'Morgen: ${c.name}',
            '${Money.format(c.monthlyCents)} werden voraussichtlich abgebucht.', NotifyTopic.contracts, 'contracts'));
      }
    }

    final sub = subscription;
    if (sub != null && !sub.cancelled && sub.inTrial(now)) {
      final when = before(sub.trialEnds, 2, 10);
      if (when.isAfter(now)) {
        out.add(Reminder(
            _idFor('trial-${sub.trialEnds}'),
            when,
            tr('Dein Gratis-Test endet in 2 Tagen'),
            tr('Ab {x} kostet Plus {y}. Wenn du nicht weitermachen willst, kündige vorher.', {'x': Dates.dayMonth(sub.trialEnds), 'y': Money.format(sub.priceCents)}),
            NotifyTopic.account,
            'subscription'));
      }
    }

    if (bankValidUntil != null) {
      final when = before(bankValidUntil, 3, 10);
      if (when.isAfter(now)) {
        out.add(Reminder(_idFor('bank-$bankValidUntil'), when, tr('Bankverbindung läuft in 3 Tagen ab'),
            tr('Einmal kurz bestätigen, dann kommen deine Umsätze weiter.'), NotifyTopic.account, 'connections'));
      }
    }

    for (final g in goals) {
      final d = g.deadline;
      if (d == null || g.reached) continue;
      final when = before(d, 7, 10);
      if (when.isAfter(now)) {
        out.add(Reminder(_idFor('goal-${g.id}-$d'), when, tr('{x} {y}: noch eine Woche', {'x': g.emoji, 'y': g.name}),
            'Es fehlen ${Money.format(g.remainingCents)}. Ein kleiner Endspurt?', NotifyTopic.spending, 'goals'));
      }
    }

    // keep well below the systems' limits (iOS: 64 pending)
    final limit = at(now, 0).add(const Duration(days: 60));
    out.removeWhere((r) => r.when.isBefore(now) || r.when.isAfter(limit));
    return calm(out).take(40).toList();
  }
}

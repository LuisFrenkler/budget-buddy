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
import 'cancellation_service.dart';
import 'contracts.dart';
import 'db.dart';
import 'goals_service.dart';
import 'hints_service.dart';
import 'plus_service.dart';
import 'settings_service.dart';
import 'weekly_report.dart';

enum NotifyTopic { spending, contracts, weekly, account }

extension NotifyTopicLabel on NotifyTopic {
  String get label => switch (this) {
        NotifyTopic.spending => 'Budgets & Ausgaben',
        NotifyTopic.contracts => 'Verträge & Abbuchungen',
        NotifyTopic.weekly => 'Wochenbericht',
        NotifyTopic.account => 'Abo & Bankverbindung',
      };

  String get description => switch (this) {
        NotifyTopic.spending => 'Budget überschritten, ungewöhnliche Ausgaben, Sparziele',
        NotifyTopic.contracts => 'Preiserhöhungen und große Abbuchungen am Tag vorher',
        NotifyTopic.weekly => 'Jeden Sonntag um 18 Uhr',
        NotifyTopic.account => 'Ende des Gratis-Tests, ablaufende Bankverbindung',
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

  static bool topic(NotifyTopic t) => _box.get('notify_${t.name}', defaultValue: true) as bool;

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

  // asks the system for permission; call only from a tap
  static Future<bool> enable() async {
    if (!_ready) await init();
    if (!_ready) return false;
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
    if (granted != true) return false;
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
        'Buddy meldet sich ab jetzt 👋',
        'Nur wenn es wichtig ist. Du kannst das jederzeit im Profil ändern.',
        'home',
      );

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'buddy',
      'Buddy',
      channelDescription: 'Hinweise, Erinnerungen und Wochenbericht',
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
    final list = [..._shown, ...ids];
    await _box.put('notifiedHints', list.length > 300 ? list.sublist(list.length - 300) : list);
  }

  static NotifyTopic? _topicOf(HintKind k) => switch (k) {
        HintKind.budgetOver || HintKind.bigExpense => NotifyTopic.spending,
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

    // 1. urgent hints, each only once, at most three at a time
    final seen = _shown;
    final fresh = _urgentHints(today).where((h) => !seen.contains(h.id) && topic(_topicOf(h.kind)!)).take(3).toList();
    for (final h in fresh) {
      await _show(_idFor(h.id), h.title, h.text, 'hint:${h.target.name}');
    }
    await _markShown(fresh.map((h) => h.id));

    // 2. the browser cannot schedule: show this week's report once when it is ready
    if (kIsWeb) {
      if (topic(NotifyTopic.weekly)) {
        final report = WeeklyReportService.build(DB.getTx(), now: today);
        final key = 'weekly-${report?.start.toIso8601String().substring(0, 10)}';
        final fresh = report != null && today.difference(report.end).inDays < 2 && !_shown.contains(key);
        if (fresh) {
          await _show(_idFor(key), 'Dein Wochenbericht ist da 📊', report.summary, 'weekly');
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
        now: today,
      ).where((r) => topic(r.topic));
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

  // what to remind of, and when (pure, so it can be tested)
  static List<Reminder> plan({
    required List<Transaction> tx,
    required List<Goal> goals,
    Subscription? subscription,
    DateTime? bankValidUntil,
    required DateTime now,
  }) {
    final out = <Reminder>[];
    DateTime at(DateTime d, int hour) => DateTime(d.year, d.month, d.day, hour);
    DateTime before(DateTime d, int days, int hour) => DateTime(d.year, d.month, d.day - days, hour);

    final weekly = WeeklyReportService.nextReady(now);
    out.add(Reminder(_idFor('weekly-$weekly'), weekly, 'Dein Wochenbericht ist da 📊',
        'Buddy hat deine Woche ausgewertet: was gut lief und wo noch was geht.', NotifyTopic.weekly, 'weekly'));

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
            'Dein Gratis-Test endet in 2 Tagen',
            'Ab ${Dates.dayMonth(sub.trialEnds)} kostet Plus ${Money.format(sub.priceCents)}. '
                'Wenn du nicht weitermachen willst, kündige vorher.',
            NotifyTopic.account,
            'subscription'));
      }
    }

    if (bankValidUntil != null) {
      final when = before(bankValidUntil, 3, 10);
      if (when.isAfter(now)) {
        out.add(Reminder(_idFor('bank-$bankValidUntil'), when, 'Bankverbindung läuft in 3 Tagen ab',
            'Einmal kurz bestätigen, dann kommen deine Umsätze weiter.', NotifyTopic.account, 'connections'));
      }
    }

    for (final g in goals) {
      final d = g.deadline;
      if (d == null || g.reached) continue;
      final when = before(d, 7, 10);
      if (when.isAfter(now)) {
        out.add(Reminder(_idFor('goal-${g.id}-$d'), when, '${g.emoji} ${g.name}: noch eine Woche',
            'Es fehlen ${Money.format(g.remainingCents)}. Ein kleiner Endspurt?', NotifyTopic.spending, 'goals'));
      }
    }

    // keep well below the systems' limits (iOS: 64 pending)
    final limit = at(now, 0).add(const Duration(days: 60));
    out.removeWhere((r) => r.when.isBefore(now) || r.when.isAfter(limit));
    out.sort((a, b) => a.when.compareTo(b.when));
    return out.take(40).toList();
  }
}

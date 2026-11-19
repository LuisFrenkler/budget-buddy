import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/ahead_agent.dart';
import '../services/app_nav.dart';
import '../services/buddy_service.dart';
import '../services/db.dart';
import '../services/goals_service.dart';
import '../services/hints_service.dart';
import '../services/plus_service.dart';
import '../services/settings_service.dart';
import '../services/tax_estimate.dart';
import 'smart_entry_sheet.dart';
import 'package:flutter/services.dart';
import 'splits_screen.dart';
import 'goals_screen.dart';
import '../services/auto_save.dart';
import '../services/buddy_history.dart';
import '../services/invite_service.dart';
import '../services/account_service.dart';
import '../services/cloud_sync.dart';
import '../services/split_service.dart';
import '../services/money_accounts.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/add_account_choice.dart';
import '../utils/errors.dart';
import '../utils/motion.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import '../widgets/tx_row.dart';
import '../widgets/vault_banner.dart';
import '../widgets/brand.dart';
import '../widgets/user_avatar.dart';
import 'account_screen.dart';
import 'add_holding_screen.dart';
import 'budget_screen.dart';
import 'buddy_log_screen.dart';
import 'buddy_memory_screen.dart';
import 'buddy_screen.dart';
import 'connections_screen.dart';
import 'contracts_screen.dart';
import 'data_screen.dart';
import 'depot_screen.dart';
import 'guarantee_screen.dart';
import 'invite_screen.dart';
import 'notification_settings_screen.dart';
import 'overview_screen.dart';
import 'plus_screen.dart';
import 'profile_screen.dart';
import 'recurring_screen.dart';
import 'refund_check_screen.dart';
import 'tax_screen.dart';
import 'vorsorge_screen.dart';
import 'wealth_screen.dart';
import 'weekly_report_screen.dart';
import '../l10n/l10n.dart';

// One place the agent can open: what the person calls it, and either its tab
// (Konto with its section) or the screen that goes on top.
class ShellPlace {
  final String label;
  final int? tab, segment;
  final Widget? screen;
  const ShellPlace.tab(this.label, int this.tab, [this.segment]) : screen = null;
  const ShellPlace.screen(this.label, Widget this.screen)
      : tab = null,
        segment = null;
}

// App shell: Ahead, Konto and Depot side by side in one pager that follows
// the finger. One quiet row on top says which is in front; nothing at the bottom.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  // every name in AppNav.places; null for a name the shell does not know
  static ShellPlace? place(String name, {int? year}) => switch (name) {
        'ueberblick' => ShellPlace.tab(tr('Überblick'), 0),
        'konto' => ShellPlace.tab(tr('Konto'), 1, 0),
        'budgets' => ShellPlace.tab(tr('Budgets'), 1, 1),
        'analyse' => ShellPlace.tab(tr('Analyse'), 1, 2),
        'depot' => ShellPlace.tab(tr('Depot'), 2),
        'agent' => ShellPlace.tab(tr('Ahead'), 3),
        'vertraege' => ShellPlace.screen(tr('Verträge & Abos'), const ContractsScreen()),
        'ziele' => ShellPlace.screen(tr('Sparziele'), const GoalsScreen()),
        'steuer' => ShellPlace.screen(tr('Steuererklärung'), TaxScreen(year: year)),
        'steuer_check' => ShellPlace.screen(tr('Rückhol-Check'), const RefundCheckScreen()),
        'vorsorge' => ShellPlace.screen(tr('Vorsorge'), const VorsorgeScreen()),
        'vermoegen' => ShellPlace.screen(tr('Vermögen & Absicherung'), const WealthScreen()),
        'wochenbericht' => ShellPlace.screen(tr('Wochenbericht'), const WeeklyReportScreen()),
        'dauerauftraege' => ShellPlace.screen(tr('Wiederkehrend'), const RecurringScreen()),
        'gruppen' => ShellPlace.screen(tr('Geteilt'), const SplitsScreen()),
        'bank' => ShellPlace.screen(tr('Verbindungen'), const ConnectionsScreen()),
        'daten' => ShellPlace.screen(tr('Wo deine Daten liegen'), const DataScreen()),
        'profil' => ShellPlace.screen(tr('Profil'), const ProfileScreen()),
        'benachrichtigungen' => ShellPlace.screen(tr('Mitteilungen'), const NotificationSettingsScreen()),
        'garantie' => ShellPlace.screen(tr('Mitgliedschaft mit Garantie'), const GuaranteeScreen()),
        'gedaechtnis' => ShellPlace.screen(tr('Was Ahead weiß'), const BuddyMemoryScreen()),
        'protokoll' => ShellPlace.screen(tr('Was Ahead getan hat'), const BuddyLogScreen()),
        'plus' => ShellPlace.screen(tr('Ahead Plus'), const PlusScreen()),
        'einladen' => ShellPlace.screen(tr('Freunde einladen'), const InviteScreen()),
        _ => null,
      };

  // switch shell tab from anywhere (e.g. an action in the chat → Überblick / Prognose)
  static final goTab = ValueNotifier<int?>(null);

  // the menu for adding by hand (quick entry, receipt, keypad, transfer);
  // lives in the Konto tab since the agent took over adding from the nav bar
  static VoidCallback? addMenu;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // current tab index (1 = Konto, 2 = Depot, 3 = the agent; 0, the Überblick, goes on top)
  // Ahead opens in the chat: the agent is the start screen
  int _tab = 3;
  // the pager's pages in swipe order (Ahead, Konto, Depot), each built when it is first swiped in
  // Ahead first, then the three places of the menu, in its order
  static const _places = [3, 0, 1, 2];
  final _pages = PageController();
  // where the pager last came to rest: only a swipe that ends somewhere new ticks
  int _rest = 3;
  // a tap moves the pager, not a finger: the pages it passes are not places to show
  bool _glide = false;

  // section inside the account (0 = Umsätze, 1 = Budgets, 2 = Analyse)
  final _segment = ValueNotifier<int>(0);

  // one scroll per tab (index = tab): the active segment again jumps Konto or Depot to the top
  final _scrolls = List.generate(4, (_) => ScrollController());

  // the refund check before sign-up keeps its answers; the feed then shows each year with money in it
  Future<void> _refundCheckToTax() async {
    if (await TaxEstimate.adoptRefundCheck(now: DateTime.now()) != null) AheadAgent.changed.value++;
  }

  @override
  void initState() {
    super.initState();
    HomeScreen.addMenu = _showAddMenu;
    // the chat from before sign-up continues here (before the Buddy tab loads it)
    BuddyHistory.adoptGuest();
    // friends who joined through the invite link: bonus questions for Buddy
    InviteService.refresh();
    // a goal filled by the autopilot gets its celebration, too
    AutoSave.reached.addListener(_goalReached);
    // an invite link opened the app: straight to joining, also right after signing in
    AccountService.current.addListener(_pendingJoin);
    BuddyScreen.ask.addListener(_toBuddy);
    HomeScreen.goTab.addListener(_toTab);
    AppNav.go.addListener(_toPlace);
    AccountScreen.pendingSegment.addListener(_toAccountSection);
    CloudSync.conflict.addListener(_vaultConflict);
    _ledger.addListener(_countSoon);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refundCheckToTax();
      _pendingJoin();
      _vaultConflict();
      _toAccountSection();
      _toPlace();
      // after the first frames: the feed scans the ledger at the same moment
      _countSoon();
    });
  }

  // finds that wait for a yes, shown on the orb. Counted a moment after the
  // ledger, the settings or the agent's own state changed and on a tab
  // switch, never in build.
  int _waiting = 0;
  Timer? _counting;
  late final _ledger =
      Listenable.merge([Hive.box('transactions').listenable(), Hive.box('settings').listenable(), AheadAgent.changed]);

  void _countSoon() {
    _counting?.cancel();
    _counting = Timer(const Duration(milliseconds: 400), _countFinds);
  }

  void _countFinds() {
    if (!mounted) return;
    var n = 0;
    try {
      final tx = DB.getTx();
      // the same hints the feed lays out, so the count matches what waits there
      List<Hint> hints = const [];
      try {
        hints = HintsService.current(
          tx: tx,
          budgets: DB.getBudgets(),
          goals: GoalsService.all(),
          subscription: PlusService.subscription.value,
          bankValidUntil: Settings.bankValidUntil,
          freeCents: BuddyService.freeCents(),
          balanceCents: BuddyService.cashCents(),
        );
      } catch (_) {}
      n = AheadAgent.run(tx: tx, hints: hints).where((f) => f.kind == FindKind.tax || f.kind == FindKind.money).length;
    } catch (_) {}
    if (n != _waiting) setState(() => _waiting = n);
  }

  bool _askingVault = false;
  // local edits while offline vs. a newer copy from another device
  void _vaultConflict() async {
    final remote = CloudSync.conflict.value;
    if (remote == null || !mounted || _askingVault) return;
    if (ModalRoute.of(context)?.isCurrent != true) {
      Future.delayed(const Duration(milliseconds: 800), _vaultConflict);
      return;
    }
    _askingVault = true;
    final keepDevice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(tr('Daten unterscheiden sich')),
        content: Text(tr(
            'Hier sind Änderungen, im Konto eine neuere Sicherung von einem anderen Gerät.\n\nKein Zusammenführen: eine Kopie gewinnt (Buchungen, Budgets, Depot), die andere ist weg.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Kontodaten laden'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Gerätedaten behalten'))),
        ],
      ),
    );
    _askingVault = false;
    if (!mounted) return;
    try {
      if (keepDevice == true) {
        await CloudSync.keepDevice();
      } else {
        await CloudSync.keepCloud();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(duration: const Duration(milliseconds: 3500), content: Text(friendlyError(e))));
    }
  }

  // waits until the start screen is really on top (not under the sign-up or
  // the "Wie möchtest du starten?" choice), then opens the join sheet once
  bool _joining = false;
  void _pendingJoin() {
    final code = SplitService.pendingJoin;
    if (code == null || !mounted || _joining) return;
    if (AccountService.current.value == null) return;
    if (ModalRoute.of(context)?.isCurrent != true) {
      Future.delayed(const Duration(milliseconds: 800), _pendingJoin);
      return;
    }
    _joining = true;
    joinSplitGroup(context, code: code).whenComplete(() => _joining = false);
  }

  void _goalReached() {
    final g = AutoSave.reached.value;
    if (g == null || !mounted) return;
    AutoSave.reached.value = null;
    celebrateGoal(context, g);
  }

  void _toBuddy() {
    if (BuddyScreen.ask.value != null && mounted) _open(3);
  }

  void _toTab() {
    final t = HomeScreen.goTab.value;
    if (t == null || !mounted) return;
    HomeScreen.goTab.value = null;
    if (t != 3) BuddyScreen.ask.value = null;
    _open(t);
  }

  // the agent asked for a place (a tool call, a button under an answer)
  void _toPlace() {
    final go = AppNav.go.value;
    if (go == null || !mounted) return;
    AppNav.go.value = null;
    final p = HomeScreen.place(go.place, year: go.year);
    if (p == null) return;
    final fromChat = _tab == 3;
    Navigator.popUntil(context, (r) => r.isFirst);
    if (p.tab == 3) {
      // already in the chat: stay where the conversation is
      if (!fromChat) _open(3);
      return;
    }
    BuddyScreen.ask.value = null;
    if (p.segment != null) {
      AccountScreen.pendingSegment.value = p.segment;
    } else if (p.tab != null) {
      if (p.tab != _tab) _open(p.tab!);
    } else {
      HapticFeedback.lightImpact();
      Navigator.push(context, MaterialPageRoute(builder: (_) => p.screen!));
    }
    if (!fromChat) return;
    // a quiet line: where the person is now, and the way back
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      persist: false,
      duration: const Duration(seconds: 5),
      content: Text(tr('Ahead hat „{x}“ geöffnet', {'x': p.label})),
      action: SnackBarAction(
        label: tr('Zurück zu Ahead'),
        textColor: AppColors.primary,
        onPressed: () {
          if (mounted) BuddyScreen.open(context);
        },
      ),
    ));
  }

  void _toAccountSection() {
    final segment = AccountScreen.pendingSegment.value;
    if (segment == null || !mounted) return;
    AccountScreen.pendingSegment.value = null;
    _open(1, segment: segment);
  }

  @override
  void dispose() {
    BuddyScreen.ask.removeListener(_toBuddy);
    HomeScreen.goTab.removeListener(_toTab);
    AppNav.go.removeListener(_toPlace);
    _ledger.removeListener(_countSoon);
    _counting?.cancel();
    AccountScreen.pendingSegment.removeListener(_toAccountSection);
    AutoSave.reached.removeListener(_goalReached);
    AccountService.current.removeListener(_pendingJoin);
    CloudSync.conflict.removeListener(_vaultConflict);
    _segment.dispose();
    _pages.dispose();
    for (final c in _scrolls) {
      c.dispose();
    }
    super.dispose();
  }

  // switch to a tab, optionally to a section of the account
  void _open(int tab, {int? segment}) {
    if (segment != null) _segment.value = segment;
    if (_tab == tab) {
      final c = _scrolls[tab];
      // never the agent: the top of a chat is its oldest message
      if (tab != 3 && c.hasClients) {
        HapticFeedback.selectionClick();
        c.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
      }
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _tab = tab);
    _countSoon();
    final page = _places.indexOf(tab);
    _glide = true;
    // no slide with less motion, nor under a screen that is still leaving
    if (Motion.reduce(context) || (ModalRoute.of(context)?.secondaryAnimation?.value ?? 0) > 0) {
      _pages.jumpToPage(page);
      _glide = false;
    } else {
      _pages.animateToPage(page, duration: Motion.reveal, curve: Motion.out);
    }
  }

  // past half-way the switch shows the new place
  void _pageChanged(int page) {
    if (_glide || _places[page] == _tab) return;
    setState(() => _tab = _places[page]);
  }

  bool _scrolled(ScrollNotification n) {
    // a list inside a page
    if (n.depth != 0) return false;
    // a finger took over, also from a tap's slide
    if (n is ScrollStartNotification && n.dragDetails != null) _glide = false;
    if (n is! ScrollEndNotification) return false;
    final p = _pages.page!;
    // held mid-way, not at rest
    if ((p - p.round()).abs() > 0.01) return false;
    final t = _places[p.round()];
    final swiped = !_glide && t != _rest;
    _glide = false;
    _rest = t;
    if (t != _tab) setState(() => _tab = t);
    if (swiped) {
      HapticFeedback.selectionClick();
      // the chat's keyboard has no business on Konto or Depot
      FocusManager.instance.primaryFocus?.unfocus();
      _countSoon();
    }
    return false;
  }

  Widget _page(int i) => switch (i) {
        0 => OverviewScreen(scroll: _scrolls[0], onOpen: (tab, {segment}) => _open(tab, segment: segment)),
        1 => _titled(tr('Konto'), AccountScreen(segment: _segment, scroll: _scrolls[1])),
        2 => _titled(tr('Depot'), DepotScreen(scroll: _scrolls[2])),
        _ => BuddyScreen(tab: true, scroll: _scrolls[3]),
      };

  // Konto and Depot under one small header: the name of the place and, top right, the profile.
  // It belongs to its page and swipes with it; Ahead carries the same avatar in its own bar.
  Widget _titled(String title, Widget page) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
          child: Row(children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontFamily: AppFonts.display, fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.8)),
            ),
            Semantics(
              button: true,
              label: tr('Profil'),
              excludeSemantics: true,
              child: InkWell(
                key: const Key('profile-avatar'),
                customBorder: const CircleBorder(),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: UserAvatar(
                      name: AccountService.current.value?.firstName ?? '',
                      size: 32,
                      fontSize: 14,
                      brandGradient: false),
                ),
              ),
            ),
          ]),
        ),
        Expanded(child: page),
      ]);

  @override
  Widget build(BuildContext context) {
    // rebuild the whole shell when the theme mode toggles, so every tab
    // re-reads the current colors instead of keeping stale ones
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      // Android's back button leads from the other tabs to Buddy before it leaves the app
      builder: (context, _, __) => PopScope(
        canPop: _tab == 3,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _open(3);
        },
        child: Scaffold(
          body: Column(children: [
            const VaultBanner(),
            Expanded(
              child: SafeArea(
                bottom: false,
                // the bar below takes the home indicator's room, so no page pads for it again
                // the context inside the Scaffold: it already took the keyboard's room out, the outer one would add it again
                child: Builder(
                  builder: (inner) => MediaQuery.removePadding(
                    context: inner,
                    removeBottom: !keyboard,
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _scrolled,
                      child: PageView.builder(
                        controller: _pages,
                        onPageChanged: _pageChanged,
                        itemCount: _places.length,
                        itemBuilder: (_, i) => _Kept(
                          // only the place that is shown runs its animations
                          child: TickerMode(enabled: _places[i] == _tab, child: _page(_places[i])),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _navigation(),
          ]),
        ),
      ),
    );
  }

  // The navigation the app had before: a floating pill with the places and the large orb for Ahead beside it.
  Widget _navigation() {
    // while typing (a question to Buddy) the keyboard takes that room
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    final night = ThemeController.isDark.value;
    final pill = Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: night ? const Color(0x1AFFFFFF) : const Color(0xEB17120E),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: night ? const Color(0x24FFFFFF) : const Color(0x00000000)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: night ? 0.4 : 0.18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      // small phones: the pill shrinks a little instead of overflowing
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _navItem(Icons.insights_rounded, tr('Überblick'), 0, 'seg-ueberblick'),
        _navItem(Icons.account_balance_wallet_outlined, tr('Konto'), 1, 'seg-konto'),
          _navItem(Icons.show_chart_rounded, tr('Depot'), 2, 'seg-depot'),
        ]),
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Ahead: the orb, with the number of finds that wait for a yes
          Semantics(
            key: const Key('seg-ahead'),
            button: true,
            selected: _tab == 3,
            label: tr('Ahead'),
            value: _waiting > 0 ? tr('{n} offen', {'n': _waiting}) : null,
            excludeSemantics: true,
            child: Stack(clipBehavior: Clip.none, children: [
              _BuddyButton(active: _tab == 3, onTap: () => _open(3)),
              if (_waiting > 0)
                Positioned(
                  top: -2,
                  right: -2,
                  child: IgnorePointer(
                    child: Container(
                      key: const Key('agent-count'),
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: night ? const Color(0xFFF5EFEA) : const Color(0xFF17120E),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_waiting > 9 ? '9+' : '$_waiting',
                          style: TextStyle(
                              fontSize: 11,
                              height: 1,
                              fontWeight: FontWeight.w700,
                              color: night ? const Color(0xFF0C0A09) : Colors.white)),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: night
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: pill),
                  )
                : pill,
          ),
        ]),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i, String key) {
    final active = _tab == i;
    final night = ThemeController.isDark.value;
    final idle = night ? const Color(0xFFA79C93) : const Color(0xFFCFC4BB);
    final onActive = night ? const Color(0xFF0C0A09) : const Color(0xFF17120E);
    final activeBg = night ? const Color(0xFFF5EFEA) : Colors.white;
    return Semantics(
      key: Key(key),
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => _open(i),
          borderRadius: BorderRadius.circular(23),
          focusColor: const Color(0x66F4C7A1),
          hoverColor: const Color(0x18FFFFFF),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            height: 46,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: EdgeInsets.symmetric(horizontal: active ? 12 : 11),
            decoration: BoxDecoration(
              color: active ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(23),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: active ? onActive : idle, size: 22),
              AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: active
                    ? Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child:
                            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onActive)),
                      )
                    : const SizedBox.shrink(),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showAddMenu() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Text(tr('Neu'),
                    style: TextStyle(
                        fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
              ),
              _sectionLabel(tr('Schnell')),
              _addOption(sheet, Icons.edit_note_rounded, tr('Schnell erfassen'),
                  tr('Eintippen wie „Döner 8,50 gestern“'), () => showSmartEntry(context)),
              _addOption(sheet, Icons.document_scanner_rounded, tr('Beleg scannen'), tr('Foto vom Kassenbon genügt'),
                  () => showSmartEntry(context, scan: true)),
              _addOption(sheet, Icons.receipt_long_rounded, tr('Umsatz erfassen'), tr('Mit Ziffernblock'), () async {
                if (await TxRow.openEditor(context) && mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(duration: Duration(milliseconds: 2800), content: Text(tr('Hinzugefügt'))));
                }
              }),
              if (MoneyAccounts.several)
                _addOption(sheet, Icons.swap_horiz_rounded, tr('Geld verschieben'), tr('Zwischen deinen Konten'),
                    () => showTransferSheet(context)),
              const SizedBox(height: 8),
              _sectionLabel(tr('Einrichten')),
              _addOption(sheet, Icons.account_balance_rounded, tr('Konto hinzufügen'),
                  tr('Bank verbinden oder von Hand'), () => showAddAccountChoice(context)),
              _addOption(
                  sheet,
                  Icons.show_chart_rounded,
                  tr('Depot hinzufügen'),
                  tr('Trade Republic & Co. oder Position von Hand'),
                  () => showAddAccountChoice(context, depot: true, byHand: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AddHoldingScreen()));
                      })),
              _addOption(sheet, Icons.savings_rounded, tr('Budget anlegen'), tr('Limit für eine Kategorie'),
                  () => showAddBudgetDialog(context)),
              _addOption(sheet, Icons.call_split_rounded, tr('Ausgabe teilen'), tr('WG, Paar, Urlaub'), () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SplitsScreen()));
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDim)),
      );

  Widget _addOption(BuildContext sheet, IconData icon, String title, String subtitle, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.pop(sheet);
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.text, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textDim.withValues(alpha: 0.7), size: 20),
            ]),
          ),
        ),
      ),
    );
  }
}

// a page swiped away stays as it was: scroll position, loaded charts, the chat
class _Kept extends StatefulWidget {
  final Widget child;
  const _Kept({required this.child});

  @override
  State<_Kept> createState() => _KeptState();
}

class _KeptState extends State<_Kept> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// Buddy beside the navigation: a big glowing orb on his own. He breathes
// softly while you are elsewhere, and wears a ring while his chat is open.
class _BuddyButton extends StatefulWidget {
  final bool active;
  final VoidCallback onTap;
  const _BuddyButton({required this.active, required this.onTap});

  @override
  State<_BuddyButton> createState() => _BuddyButtonState();
}

class _BuddyButtonState extends State<_BuddyButton> with SingleTickerProviderStateMixin {
  bool _down = false;
  final _focus = FocusNode();
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final night = ThemeController.isDark.value;
    const size = 60.0;
    return Semantics(
      button: true,
      selected: widget.active,
      label: tr('Ahead'),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        shape: const CircleBorder(),
        child: InkWell(
          focusNode: _focus,
          customBorder: const CircleBorder(),
          focusColor: const Color(0x55F4C7A1),
          hoverColor: const Color(0x22FFFFFF),
          onHighlightChanged: (v) => setState(() => _down = v),
          onTap: () {
            HapticFeedback.mediumImpact();
            widget.onTap();
          },
          child: AnimatedBuilder(
            animation: _breath,
            builder: (_, child) {
              final b = reduce || widget.active ? 0.5 : Curves.easeInOut.transform(_breath.value);
              return Container(
                width: size + 6,
                height: size + 6,
                alignment: Alignment.center,
                // the ring shows that his chat is open
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.active || _focus.hasFocus
                        ? (night ? const Color(0xFFF4C7A1) : const Color(0xFFB06030))
                        : Colors.transparent,
                    width: _focus.hasFocus && !widget.active ? 3 : 2,
                  ),
                ),
                child: AnimatedScale(
                  scale: _down ? 0.9 : 1,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutBack,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BuddyOrb.sphere(size, glow: 0.8 + b * 0.7),
                    child: child,
                  ),
                ),
              );
            },
            child: CustomPaint(painter: MarkPainter(color: const Color(0xF2FFF7F0))),
          ),
        ),
      ),
    );
  }
}

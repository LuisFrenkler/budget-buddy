import 'package:flutter/material.dart';
import 'smart_entry_sheet.dart';
import 'package:flutter/services.dart';
import 'splits_screen.dart';
import 'goals_screen.dart';
import '../services/auto_save.dart';
import '../services/account_service.dart';
import '../services/cloud_sync.dart';
import '../services/split_service.dart';
import '../services/money_accounts.dart';
import '../widgets/transfer_sheet.dart';
import '../widgets/add_account_choice.dart';
import '../utils/errors.dart';
import '../utils/theme.dart';
import '../widgets/tx_row.dart';
import '../widgets/vault_banner.dart';
import 'account_screen.dart';
import 'add_holding_screen.dart';
import 'budget_screen.dart';
import 'buddy_screen.dart';
import 'depot_screen.dart';
import 'overview_screen.dart';

// App shell: four areas (Start, Konto, Depot, Buddy) in a floating navigation
// bar with a separate add button next to it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  // switch shell tab from anywhere (e.g. Buddy action → Start / Prognose)
  static final goTab = ValueNotifier<int?>(null);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // current tab index (0 = Start, 1 = Konto, 2 = Depot, 3 = Buddy)
  int _tab = 0;

  // section inside the account (0 = Umsätze, 1 = Budgets, 2 = Analyse)
  final _segment = ValueNotifier<int>(0);

  // one scroll per tab: tapping the active tab again jumps to the top
  final _scrolls = List.generate(4, (_) => ScrollController());

  @override
  void initState() {
    super.initState();
    // a goal filled by the autopilot gets its celebration, too
    AutoSave.reached.addListener(_goalReached);
    // an invite link opened the app: straight to joining, also right after signing in
    AccountService.current.addListener(_pendingJoin);
    BuddyScreen.ask.addListener(_toBuddy);
    HomeScreen.goTab.addListener(_toTab);
    AccountScreen.pendingSegment.addListener(_toAccountSection);
    CloudSync.conflict.addListener(_vaultConflict);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingJoin();
      _vaultConflict();
      _toAccountSection();
    });
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
        title: const Text('Daten unterscheiden sich'),
        content: const Text(
            'Auf diesem Gerät hast du Änderungen, und in deinem Konto liegt eine neuere Sicherung '
            'von einem anderen Gerät.\n\n'
            'Es gibt kein Zusammenführen: eine komplette Kopie gewinnt '
            '(Buchungen, Budgets, Depot). Die andere geht verloren.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Kontodaten laden')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gerätedaten behalten')),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(milliseconds: 3500), content: Text(friendlyError(e))));
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
    _open(t);
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
    AccountScreen.pendingSegment.removeListener(_toAccountSection);
    AutoSave.reached.removeListener(_goalReached);
    AccountService.current.removeListener(_pendingJoin);
    CloudSync.conflict.removeListener(_vaultConflict);
    _segment.dispose();
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
      if (c.hasClients) {
        HapticFeedback.selectionClick();
        c.animateTo(0, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
      }
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    // rebuild the whole shell when the theme mode toggles, so every tab
    // re-reads the current colors instead of keeping stale ones
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      // Android's back button leads from Konto or Depot to Start before it leaves the app
      builder: (context, _, __) => PopScope(
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _open(0);
        },
        child: Scaffold(
        // the tabs stay alive (scroll position, loaded charts) and cross-fade
        // with a slight rise when switching
        body: Column(children: [
          const VaultBanner(),
          Expanded(
            child: Stack(children: [
              for (final (i, tab) in [
                OverviewScreen(onOpen: _open, scroll: _scrolls[0]),
                AccountScreen(segment: _segment, scroll: _scrolls[1]),
                DepotScreen(scroll: _scrolls[2]),
                BuddyScreen(tab: true, scroll: _scrolls[3]),
              ].indexed)
                IgnorePointer(
                  ignoring: i != _tab,
                  // the fade itself must keep running when a tab goes inactive,
                  // so only the tab's own content is paused (TickerMode inside)
                  child: AnimatedOpacity(
                    opacity: i == _tab ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: AnimatedSlide(
                      offset: i == _tab ? Offset.zero : const Offset(0, 0.015),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      // a screen reader only reads the tab that is shown
                      child: ExcludeSemantics(
                        excluding: i != _tab,
                        child: TickerMode(enabled: i == _tab, child: tab),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
        bottomNavigationBar: _navigation(),
        ),
      ),
    );
  }

  // floating pill nav + add — inspired by modern finance apps (clear, springy, one primary CTA)
  Widget _navigation() {
    // while typing (a question to Buddy) the keyboard takes that room
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 64,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.85)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: ThemeController.isDark.value ? 0.35 : 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    _navItem(Icons.home_rounded, 'Start', 0),
                    _navItem(Icons.account_balance_wallet_rounded, 'Konto', 1),
                    _navItem(Icons.show_chart_rounded, 'Depot', 2),
                    _navItem(Icons.auto_awesome_rounded, 'Buddy', 3),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Semantics(
              button: true,
              label: 'Schnell erfassen. Lange drücken für mehr.',
              child: _AddFab(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  showSmartEntry(context);
                },
                onLongPress: _showAddMenu,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final active = _tab == i;
    final color = active ? AppColors.primaryText : AppColors.textDim;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _open(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: active ? AppColors.primary.withValues(alpha: 0.14) : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: active ? 1.08 : 1,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontSize: 10.5,
                        color: color,
                        fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                        letterSpacing: active ? -0.2 : 0)),
              ],
            ),
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
                child: Text('Neu', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              ),
              _sectionLabel('Schnell'),
              _addOption(sheet, Icons.auto_awesome_rounded, AppColors.primary, 'Schnell erfassen',
                  'Eintippen wie „Döner 8,50 gestern“', () => showSmartEntry(context)),
              _addOption(sheet, Icons.document_scanner_rounded, const Color(0xFFF472B6), 'Beleg scannen',
                  'Foto vom Kassenbon genügt', () => showSmartEntry(context, scan: true)),
              _addOption(sheet, Icons.receipt_long_rounded, AppColors.positive, 'Umsatz erfassen',
                  'Mit Ziffernblock', () async {
                if (await TxRow.openEditor(context) && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Hinzugefügt')));
                }
              }),
              if (MoneyAccounts.several)
                _addOption(sheet, Icons.swap_horiz_rounded, AppColors.accentBlue, 'Geld verschieben',
                    'Zwischen deinen Konten', () => showTransferSheet(context)),
              const SizedBox(height: 8),
              _sectionLabel('Einrichten'),
              _addOption(sheet, Icons.account_balance_rounded, AppColors.primary, 'Konto hinzufügen',
                  'Bank verbinden oder von Hand', () => showAddAccountChoice(context)),
              _addOption(sheet, Icons.show_chart_rounded, AppColors.accentBlue, 'Depot hinzufügen',
                  'Trade Republic & Co. oder Position von Hand',
                  () => showAddAccountChoice(context, depot: true, byHand: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AddHoldingScreen()));
                      })),
              _addOption(sheet, Icons.savings_rounded, AppColors.warning, 'Budget anlegen',
                  'Limit für eine Kategorie', () => showAddBudgetDialog(context)),
              _addOption(sheet, Icons.call_split_rounded, const Color(0xFF14B8A6), 'Ausgabe teilen',
                  'WG, Paar, Urlaub', () {
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
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textDim, letterSpacing: 0.4)),
      );

  Widget _addOption(BuildContext sheet, IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
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
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
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

// round + : tap = Schnell erfassen, long-press = volles Neu-Menü
class _AddFab extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _AddFab({required this.onTap, required this.onLongPress});

  @override
  State<_AddFab> createState() => _AddFabState();
}

class _AddFabState extends State<_AddFab> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: () {
        HapticFeedback.heavyImpact();
        widget.onLongPress();
      },
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.heroBrand,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
        ),
      ),
    );
  }
}

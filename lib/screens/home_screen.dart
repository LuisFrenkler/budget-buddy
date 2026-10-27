import 'package:flutter/material.dart';
import 'smart_entry_sheet.dart';
import 'package:flutter/services.dart';
import 'splits_screen.dart';
import 'goals_screen.dart';
import '../services/auto_save.dart';
import '../services/account_service.dart';
import '../services/split_service.dart';
import '../services/db.dart';
import '../services/money_accounts.dart';
import '../widgets/transfer_sheet.dart';
import '../utils/theme.dart';
import '../widgets/tx_row.dart';
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

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // current tab index (0 = Start, 1 = Konto, 2 = Depot, 3 = Buddy)
  int _tab = 0;

  // section inside the account (0 = Umsätze, 1 = Budgets, 2 = Analyse)
  final _segment = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // create default badges if they dont exist yet
    DB.initBadges();
    // a goal filled by the autopilot gets its celebration, too
    AutoSave.reached.addListener(_goalReached);
    // an invite link opened the app: straight to joining, also right after signing in
    AccountService.current.addListener(_pendingJoin);
    BuddyScreen.ask.addListener(_toBuddy);
    WidgetsBinding.instance.addPostFrameCallback((_) => _pendingJoin());
  }

  // waits until the start screen is really on top (not under the sign-up or
  // the "Wie möchtest du starten?" choice), then opens the join sheet once
  bool _joining = false;
  bool _guestHinted = false;
  void _pendingJoin() {
    final code = SplitService.pendingJoin;
    if (code == null || !mounted || _joining) return;
    if (ModalRoute.of(context)?.isCurrent != true) {
      Future.delayed(const Duration(milliseconds: 800), _pendingJoin);
      return;
    }
    // a guest gets the hint once; signing in brings the sheet back (listener)
    if (AccountService.current.value == null) {
      if (!_guestHinted) joinSplitGroup(context, code: code);
      _guestHinted = true;
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

  @override
  void dispose() {
    BuddyScreen.ask.removeListener(_toBuddy);
    AutoSave.reached.removeListener(_goalReached);
    AccountService.current.removeListener(_pendingJoin);
    _segment.dispose();
    super.dispose();
  }

  // switch to a tab, optionally to a section of the account
  void _open(int tab, {int? segment}) {
    if (segment != null) _segment.value = segment;
    if (_tab != tab) HapticFeedback.selectionClick();
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
        body: Stack(children: [
          for (final (i, tab) in [
            OverviewScreen(onOpen: _open),
            AccountScreen(segment: _segment),
            const DepotScreen(),
            const BuddyScreen(tab: true),
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
        bottomNavigationBar: _navigation(),
        ),
      ),
    );
  }

  // floating pill with the three areas and the round add button beside it
  Widget _navigation() {
    // while typing (a question to Buddy) the keyboard takes that room
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 62,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(31),
                  border: Border.all(color: AppColors.border),
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
              label: 'Hinzufügen',
              child: Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                elevation: 0,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _showAddMenu,
                  child: const SizedBox(
                    width: 62,
                    height: 62,
                    child: Icon(Icons.add_rounded, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final active = _tab == i;
    final color = active ? AppColors.primary : AppColors.textDim;
    return Expanded(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: active ? 1.1 : 1,
              duration: const Duration(milliseconds: 200),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
        ),
      ),
    );
  }

  // what can be added: a transaction, a depot position or a budget
  void _showAddMenu() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      // as tall as its options, not capped at half the screen
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _addOption(sheet, Icons.auto_awesome_rounded, AppColors.primary, 'Schnell erfassen',
                  'Eintippen wie „Döner 8,50 gestern“', () => showSmartEntry(context)),
              _addOption(sheet, Icons.document_scanner_rounded, const Color(0xFFF472B6), 'Beleg scannen',
                  'Foto vom Kassenbon genügt', () => showSmartEntry(context, scan: true)),
              _addOption(sheet, Icons.receipt_long_rounded, AppColors.positive, 'Umsatz erfassen',
                  'Mit Ziffernblock', () async {
                if (await TxRow.openEditor(context) && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(milliseconds: 2800), content: Text('Hinzugefügt')));
                }
              }),
              if (MoneyAccounts.several)
                _addOption(sheet, Icons.swap_horiz_rounded, AppColors.accentBlue, 'Geld verschieben',
                    'Zwischen deinen Konten, z. B. aufs Sparkonto', () => showTransferSheet(context)),
              _addOption(sheet, Icons.show_chart_rounded, AppColors.accentBlue, 'Position hinzufügen',
                  'Aktie, ETF oder Krypto', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AddHoldingScreen()));
              }),
              _addOption(sheet, Icons.savings_rounded, AppColors.warning, 'Budget anlegen',
                  'Limit für eine Kategorie', () => showAddBudgetDialog(context)),
              _addOption(sheet, Icons.call_split_rounded, const Color(0xFF14B8A6), 'Ausgabe teilen',
                  'WG, Paar, Urlaub: wer schuldet wem', () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SplitsScreen()));
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addOption(BuildContext sheet, IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: AppColors.textDim)),
      onTap: () {
        Navigator.pop(sheet);
        onTap();
      },
    );
  }
}

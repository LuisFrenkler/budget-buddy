import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
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
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import '../widgets/tx_row.dart';
import '../widgets/vault_banner.dart';
import '../widgets/brand.dart';
import 'account_screen.dart';
import 'add_holding_screen.dart';
import 'budget_screen.dart';
import 'buddy_screen.dart';
import 'depot_screen.dart';
import 'overview_screen.dart';
import '../l10n/l10n.dart';

// App shell: Buddy first, then Überblick, Konto, Depot in a floating navigation
// bar with a separate add button next to it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  // switch shell tab from anywhere (e.g. Buddy action → Überblick / Prognose)
  static final goTab = ValueNotifier<int?>(null);

  // the menu for adding by hand (quick entry, receipt, keypad, transfer);
  // lives in the Konto tab since Buddy took over adding from the nav bar
  static VoidCallback? addMenu;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // current tab index (0 = Überblick, 1 = Konto, 2 = Depot, 3 = Buddy)
  // Ahead opens in the chat: Buddy is the start screen
  int _tab = 3;
  // Buddy always; others on first visit, avoids mounting Überblick/Konto/Depot at cold start
  final _visited = <int>{3};

  // section inside the account (0 = Umsätze, 1 = Budgets, 2 = Analyse)
  final _segment = ValueNotifier<int>(0);

  // one scroll per tab: tapping the active tab again jumps to the top
  final _scrolls = List.generate(4, (_) => ScrollController());

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
        title: Text(tr('Daten unterscheiden sich')),
        content: Text(
            tr('Hier sind Änderungen, im Konto eine neuere Sicherung von einem anderen Gerät.\n\nKein Zusammenführen: eine Kopie gewinnt (Buchungen, Budgets, Depot), die andere ist weg.')),
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
    if (t != 3) BuddyScreen.ask.value = null;
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
    setState(() {
      _visited.add(tab);
      _tab = tab;
    });
  }

  Widget _page(int i) => switch (i) {
        0 => OverviewScreen(onOpen: _open, scroll: _scrolls[0]),
        1 => AccountScreen(segment: _segment, scroll: _scrolls[1]),
        2 => DepotScreen(scroll: _scrolls[2]),
        _ => BuddyScreen(tab: true, scroll: _scrolls[3]),
      };

  @override
  Widget build(BuildContext context) {
    // rebuild the whole shell when the theme mode toggles, so every tab
    // re-reads the current colors instead of keeping stale ones
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      // Android's back button leads from the other tabs to Buddy before it leaves the app
      builder: (context, _, __) => PopScope(
        canPop: _tab == 3,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _open(3);
        },
        child: Scaffold(
        // the tabs stay alive (scroll position, loaded charts) and cross-fade
        // with a slight rise when switching
        body: Column(children: [
          const VaultBanner(),
          Expanded(
            child: Stack(children: [
              for (final i in _visited)
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
                        child: TickerMode(
                            enabled: i == _tab, child: _page(i)),
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

  // Buddy is the heart of the app, so he is not one tab among four: the
  // tabs and "+" share a slim pill, and beside it Buddy stands on his own as
  // a big glowing orb that breathes softly
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
        _navItem(Icons.insights_rounded, tr('Überblick'), 0),
        _navItem(Icons.account_balance_wallet_outlined, tr('Konto'), 1),
        _navItem(Icons.show_chart_rounded, tr('Depot'), 2),
      ]),
      ),
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Flexible(
            child: night
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: pill),
                  )
                : pill,
          ),
          const SizedBox(width: 12),
          _BuddyButton(active: _tab == 3, onTap: () => _open(3)),
        ]),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final active = _tab == i;
    final night = ThemeController.isDark.value;
    final idle = night ? const Color(0xFFA79C93) : const Color(0xFFCFC4BB);
    final onActive = night ? const Color(0xFF0C0A09) : const Color(0xFF17120E);
    final activeBg = night ? const Color(0xFFF5EFEA) : Colors.white;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(i),
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
                      child: Text(label,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: onActive)),
                    )
                  : const SizedBox.shrink(),
            ),
          ]),
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
                child: Text(tr('Neu'), style: TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.4)),
              ),
              _sectionLabel(tr('Schnell')),
              _addOption(sheet, Icons.edit_note_rounded, tr('Schnell erfassen'),
                  tr('Eintippen wie „Döner 8,50 gestern“'), () => showSmartEntry(context)),
              _addOption(sheet, Icons.document_scanner_rounded, tr('Beleg scannen'),
                  tr('Foto vom Kassenbon genügt'), () => showSmartEntry(context, scan: true)),
              _addOption(sheet, Icons.receipt_long_rounded, tr('Umsatz erfassen'),
                  tr('Mit Ziffernblock'), () async {
                if (await TxRow.openEditor(context) && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(duration: Duration(milliseconds: 2800), content: Text(tr('Hinzugefügt'))));
                }
              }),
              if (MoneyAccounts.several)
                _addOption(sheet, Icons.swap_horiz_rounded, tr('Geld verschieben'),
                    tr('Zwischen deinen Konten'), () => showTransferSheet(context)),
              const SizedBox(height: 8),
              _sectionLabel(tr('Einrichten')),
              _addOption(sheet, Icons.account_balance_rounded, tr('Konto hinzufügen'),
                  tr('Bank verbinden oder von Hand'), () => showAddAccountChoice(context)),
              _addOption(sheet, Icons.show_chart_rounded, tr('Depot hinzufügen'),
                  tr('Trade Republic & Co. oder Position von Hand'),
                  () => showAddAccountChoice(context, depot: true, byHand: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const AddHoldingScreen()));
                      })),
              _addOption(sheet, Icons.savings_rounded, tr('Budget anlegen'),
                  tr('Limit für eine Kategorie'), () => showAddBudgetDialog(context)),
              _addOption(sheet, Icons.call_split_rounded, tr('Ausgabe teilen'),
                  tr('WG, Paar, Urlaub'), () {
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
                fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDim)),
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
  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..repeat(reverse: true);

  @override
  void dispose() {
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
      label: tr('Buddy'),
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
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
                  color: widget.active
                      ? (night ? const Color(0xFFF4C7A1) : const Color(0xFFB06030))
                      : Colors.transparent,
                  width: 2,
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
    );
  }
}

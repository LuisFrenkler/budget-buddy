import 'package:flutter/material.dart';
import 'smart_entry_sheet.dart';
import 'package:flutter/services.dart';
import 'splits_screen.dart';
import '../services/db.dart';
import '../utils/theme.dart';
import '../widgets/tx_row.dart';
import 'account_screen.dart';
import 'add_holding_screen.dart';
import 'budget_screen.dart';
import 'depot_screen.dart';
import 'overview_screen.dart';

// App shell: three areas (Start, Konto, Depot) in a floating navigation bar
// with a separate add button next to it.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // current tab index (0 = Start, 1 = Konto, 2 = Depot)
  int _tab = 0;

  // section inside the account (0 = Umsätze, 1 = Budgets, 2 = Analyse)
  final _segment = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // create default badges if they dont exist yet
    DB.initBadges();
  }

  @override
  void dispose() {
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
      builder: (context, _, __) => Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            OverviewScreen(onOpen: _open),
            AccountScreen(segment: _segment),
            const DepotScreen(),
          ],
        ),
        bottomNavigationBar: _navigation(),
      ),
    );
  }

  // floating pill with the three areas and the round add button beside it
  Widget _navigation() {
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
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Material(
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
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final active = _tab == i;
    final color = active ? AppColors.primary : AppColors.textDim;
    return Expanded(
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
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hinzugefügt')));
                }
              }),
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

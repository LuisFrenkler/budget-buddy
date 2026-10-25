import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/db.dart';
import '../models/transaction.dart';
import '../models/badge.dart' as badge_model;
import '../utils/theme.dart';
import '../utils/money.dart';
import '../widgets/hero_card.dart';
import 'add_screen.dart';
import 'budget_screen.dart';
import 'stats_screen.dart';
import 'depot_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // current tab index (0 = home, 1 = budget, 2 = stats, 3 = profile)
  int _tab = 0;
  
  // search text for filtering transactions
  String _search = '';

  @override
  void initState() {
    super.initState();
    // create default badges if they dont exist yet
    DB.initBadges();
  }

  @override
  Widget build(BuildContext context) {
    // rebuild the whole shell (tabs, nav, FAB) when the theme mode toggles,
    // so every tab re-reads the current colors instead of keeping stale ones
    return ValueListenableBuilder<bool>(
      valueListenable: ThemeController.isDark,
      builder: (context, _, __) => Scaffold(
        // tap navigation
        body: IndexedStack(
          index: _tab,
          children: [
            _homeTab(),
            BudgetScreen(),
            StatsScreen(),
            DepotScreen(),
            ProfileScreen(),
          ],
        ),

        // custom floating pill navigation
        bottomNavigationBar: _floatingNav(),

        // floating action button, only show on home tab
        floatingActionButton: _tab == 0
            ? FloatingActionButton(
                heroTag: 'fab_home',
                onPressed: _addTx,
                child: const Icon(Icons.add),
              )
            : null,
      ),
    );
  }

  // content
  Widget _homeTab() {
    return ValueListenableBuilder<Box>(
      valueListenable: Hive.box('transactions').listenable(),
      builder: (context, box, _) {
        // load data
        final tx = DB.getTx();
        final badges = DB.getBadges();
        final balance = DB.balance();
        final income = DB.income();
        final expenses = DB.expenses();
        final depot = DB.portfolioValue();

        // count unlockedbadges
        int unlockedCount = 0;
        for (var b in badges) {
          if (b.isUnlocked) unlockedCount++;
        }

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              children: [
              // greeting header
              _greetingHeader(),
              const SizedBox(height: 18),
              // balance card showing total, income, expenses
              _balanceCard(balance, income, expenses),
              const SizedBox(height: 24),

              // total net worth (cash + depot), only when there's a depot
              if (depot > 0) ...[
                _netWorthCard(balance, depot),
                const SizedBox(height: 24),
              ],

              // badges section header with count
              _sectionHeader('Abzeichen', '$unlockedCount/${badges.length}'),
              const SizedBox(height: 8),
              // horizontal scrollable badge list
              _badgeRow(badges),
              const SizedBox(height: 24),
              
              // transactions section header with count
              _sectionHeader('Transaktionen', '${tx.length}'),
              const SizedBox(height: 8),
              // search field to filter transactions
              _searchField(),
              const SizedBox(height: 16),
              
              // show empty message or list of transactions
              if (tx.isEmpty) 
                _emptyState() 
              else
                _txList(tx),
              ],
            ),
          ),
        );
      },
    );
  }

  // greeting row at the top of the home screen
  Widget _greetingHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Willkommen zurück', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
              const Text('BudgetBuddy', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: const Icon(Icons.person, color: AppColors.primary),
        ),
      ],
    );
  }

  // total net worth: cash balance + current depot value
  Widget _netWorthCard(int cash, int depot) {
    final total = cash + depot;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Gesamtvermögen', style: TextStyle(color: AppColors.textDim, fontSize: 13)),
          const SizedBox(height: 2),
          Text(Money.format(total), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Row(children: [
            _netStat(Icons.account_balance_wallet, 'Konto', Money.signed(cash),
                cash >= 0 ? AppColors.primary : AppColors.error),
            const SizedBox(width: 12),
            _netStat(Icons.trending_up, 'Depot', Money.format(depot), AppColors.accentBlue),
          ]),
        ],
      ),
    );
  }

  Widget _netStat(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: AppColors.textDim)),
                Text(value,
                    style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // big gradient hero card showing balance, income and expenses (all in cents)
  Widget _balanceCard(int balance, int income, int expenses) {
    return HeroCard(
      label: 'Kontostand',
      value: Money.signed(balance),
      gradient: AppColors.heroGreen,
      child: Row(
        children: [
          HeroPill(icon: Icons.south_west, label: 'Einnahmen', value: Money.format(income)),
          const SizedBox(width: 10),
          HeroPill(icon: Icons.north_east, label: 'Ausgaben', value: Money.format(expenses)),
        ],
      ),
    );
  }

  // custom floating pill navigation bar
  Widget _floatingNav() {
    const items = <List<Object>>[
      [Icons.home_rounded, 'Start'],
      [Icons.account_balance_wallet_rounded, 'Budget'],
      [Icons.pie_chart_rounded, 'Statistik'],
      [Icons.trending_up_rounded, 'Depot'],
      [Icons.person_rounded, 'Profil'],
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      height: 66,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (int i = 0; i < items.length; i++)
            _navItem(items[i][0] as IconData, items[i][1] as String, i),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int i) {
    final active = _tab == i;
    final color = active ? AppColors.primary : AppColors.textDim;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = i),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  // maps a category name to a representative icon
  IconData _categoryIcon(String c) {
    switch (c) {
      case 'Lebensmittel': return Icons.shopping_cart;
      case 'Transport': return Icons.directions_car;
      case 'Unterhaltung': return Icons.movie;
      case 'Wohnen': return Icons.home;
      case 'Kleidung': return Icons.checkroom;
      case 'Gesundheit': return Icons.favorite;
      case 'Bildung': return Icons.school;
      case 'Essen & Trinken': return Icons.restaurant;
      case 'Gehalt': return Icons.work;
      case 'Nebenjob': return Icons.handyman;
      case 'Investition': return Icons.trending_up;
      case 'Geschenk': return Icons.card_giftcard;
      default: return Icons.category;
    }
  }

  // section header
  Widget _sectionHeader(String title, String count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        // count badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Text(count, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // horizontal scrollable list of badge cards
  Widget _badgeRow(List<badge_model.Badge> badges) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: badges.length,
        // space between badges
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final b = badges[i];
          // each badge is tappable
          return GestureDetector(
            onTap: () => _showBadgeDialog(b),
            child: Container(
              width: 75,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                // green border if unlocked, gray if locked
                border: Border.all(color: b.isUnlocked ? AppColors.primary.withValues(alpha: 0.5) : AppColors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // emoji - gray if locked
                  Text(b.emoji, style: TextStyle(fontSize: 28, color: b.isUnlocked ? null : Colors.grey)),
                  const SizedBox(height: 4),
                  // badge name
                  Text(
                    b.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: b.isUnlocked ? AppColors.text : AppColors.textDim),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // text field to search/filter transactions
  Widget _searchField() {
    return TextField(
      // update search text when user types
      onChanged: (v) => setState(() => _search = v),
      decoration: InputDecoration(
        hintText: 'Suchen...',
        prefixIcon: const Icon(Icons.search),
        // show clear button only when there is text
        suffixIcon: _search.isNotEmpty
            ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _search = ''))
            : null,
      ),
    );
  }

  // shown when there are no transactions yet
  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.receipt_long, size: 64, color: AppColors.textDim),
            const SizedBox(height: 16),
            const Text('Keine Transaktionen', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Tippe auf + um loszulegen', style: TextStyle(color: AppColors.textDim)),
          ],
        ),
      ),
    );
  }

  // builds the list of transaction cards
  Widget _txList(List<Transaction> tx) {
    // filter transactions by search text
    final filtered = <Transaction>[];
    for (var t in tx) {
      final searchLower = _search.toLowerCase();
      // check if category or note contains search text
      final categoryMatch = t.category.toLowerCase().contains(searchLower);
      final noteMatch = t.note?.toLowerCase().contains(searchLower) ?? false;
      
      if (categoryMatch || noteMatch) {
        filtered.add(t);
      }
    }

    // build list of transaction cards
    final items = <Widget>[];
    for (var t in filtered) {
      items.add(
        // Dismissible allows swipe to delete
        Dismissible(
          key: Key(t.id),
          // only allow swipe from right to left
          direction: DismissDirection.endToStart,
          // red background with delete icon
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (_) => _confirmDeleteTx(t),
          child: Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              onTap: () => _addTx(tx: t),
              // rounded-square chip with a category icon
              leading: IconChip(_categoryIcon(t.category), t.isIncome ? AppColors.accent : AppColors.error),
              title: Text(t.category, style: const TextStyle(fontWeight: FontWeight.w500)),
              subtitle: Text(t.dateText),
              // amount on the right
              trailing: Text(
                t.amountText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: t.isIncome ? AppColors.primary : AppColors.error,
                ),
              ),
            ),
          ),
        ),
      );
    }
    
    return Column(children: items);
  }

  // opens the add/edit transaction screen
  void _addTx({Transaction? tx}) async {
    // navigate to add screen and wait for result
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => AddScreen(tx: tx)),
    );
    
    // if transaction was saved, show success message
    if (result == true && mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tx == null ? 'Hinzugefügt' : 'Aktualisiert'),
        backgroundColor: AppColors.primary,
      ));
    }
  }

  // confirm delete
  Future<bool> _confirmDeleteTx(Transaction t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Löschen?'),
        content: Text('${t.category}: ${t.amountText}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Nein')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ja', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    
    // if user confirmed, delete from database and offer an undo
    if (confirmed == true) {
      await DB.deleteTx(t.id);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${t.category} gelöscht'),
          action: SnackBarAction(
            label: 'Rückgängig',
            textColor: AppColors.primary,
            // re-add the exact same transaction (same id) to restore it
            onPressed: () => DB.addTx(t),
          ),
        ));
      }
    }
    return false;
  }
  // shows popup with badge details when user taps a badge
  void _showBadgeDialog(badge_model.Badge b) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        // title with emoji and name
        title: Row(
          children: [
            Text(b.emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(child: Text(b.name)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // badge description
            Text(b.description),
            const SizedBox(height: 12),
            // unlock status
            Text(
              b.isUnlocked
                  ? 'Freigeschaltet am ${b.unlockedDate?.day}.${b.unlockedDate?.month}.${b.unlockedDate?.year}'
                  : 'Noch nicht freigeschaltet',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }
}

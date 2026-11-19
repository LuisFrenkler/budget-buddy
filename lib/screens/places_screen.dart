// Everything the app has, on one page: the answer to "Wo finde ich …?" without
// having to ask. The agent opens the same places; this list is the way by hand.
import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../services/app_nav.dart';
import '../services/buddy_app_guide.dart';
import '../utils/theme.dart';
import '../widgets/settings_list.dart';
import 'account_screen.dart';
import 'home_screen.dart';

class PlacesScreen extends StatelessWidget {
  const PlacesScreen({super.key});

  // every place of AppNav that is not already a row in the profile
  static const groups = <(String, List<(String, IconData)>)>[
    ('Geld', [
      ('konto', Icons.account_balance_wallet_outlined),
      ('budgets', Icons.pie_chart_outline_rounded),
      ('analyse', Icons.bar_chart_rounded),
      ('vertraege', Icons.receipt_long_outlined),
      ('dauerauftraege', Icons.repeat_rounded),
      ('ziele', Icons.flag_outlined),
      ('gruppen', Icons.group_outlined),
    ]),
    ('Vermögen', [
      ('ueberblick', Icons.insights_rounded),
      ('depot', Icons.show_chart_rounded),
      ('vermoegen', Icons.savings_outlined),
      ('vorsorge', Icons.elderly_outlined),
    ]),
    ('Steuern', [
      ('steuer', Icons.description_outlined),
      ('steuer_check', Icons.fact_check_outlined),
    ]),
    ('Ahead', [
      ('gedaechtnis', Icons.bookmark_outline_rounded),
      ('protokoll', Icons.history_rounded),
      ('wochenbericht', Icons.calendar_view_week_rounded),
      ('einladen', Icons.card_giftcard_rounded),
    ]),
  ];

  void _open(BuildContext context, String name) {
    final p = HomeScreen.place(name);
    if (p == null) return;
    if (p.screen != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => p.screen!));
      return;
    }
    // a place of the shell: back to it, then turn to the page
    Navigator.popUntil(context, (r) => r.isFirst);
    if (p.segment != null) {
      AccountScreen.pendingSegment.value = p.segment;
    } else {
      HomeScreen.goTab.value = p.tab;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tr('Alle Bereiche'))),
        body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 32), children: [
          for (final (title, places) in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
              child: Text(tr(title),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textDim)),
            ),
            SettingsGroup([
              for (final (name, icon) in places)
                SettingsRow(
                  key: Key('place-$name'),
                  icon: icon,
                  title: BuddyAppGuide.label(name),
                  onTap: () => _open(context, name),
                ),
            ]),
          ],
        ]),
      );

  // the list covers every place: one that is neither here nor a profile row would be unreachable by hand
  static Set<String> get listed => {for (final (_, places) in groups) for (final (name, _) in places) name};
  static const inProfile = {'agent', 'profil', 'bank', 'daten', 'benachrichtigungen', 'plus', 'garantie'};
  static bool get complete => AppNav.places.difference({...listed, ...inProfile}).isEmpty;
}

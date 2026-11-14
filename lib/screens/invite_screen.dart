// "Freunde einladen": three invites, each friend who joins adds free Buddy
// questions. Grown by word of mouth, not ad money.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../services/account_service.dart';
import '../services/invite_service.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    InviteService.refresh().whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _share(InviteInfo i) async {
    HapticFeedback.mediumImpact();
    final text = i.shareText(AccountService.current.value?.firstName);
    try {
      await Share.share(text);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Link kopiert'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<InviteInfo?>(
      valueListenable: InviteService.info,
      builder: (context, i, _) {
        return Scaffold(
          appBar: AppBar(title: Text(tr('Freunde einladen'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const BuddyOrb(size: 52),
              const SizedBox(height: 20),
              Text(tr('Zu dritt ist Geld weniger nervig.'),
                  style: const TextStyle(fontFamily: AppFonts.display, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1.15)),
              const SizedBox(height: 8),
              Text(
                tr('Lade bis zu drei Leute ein. Für jede Person, die mitmacht, bekommst du {n} Buddy-Fragen mehr im Monat.',
                    {'n': i?.bonusPerFriend ?? 5}),
                style: TextStyle(color: AppColors.textDim, height: 1.45, fontSize: 15.5),
              ),
              const SizedBox(height: 24),
              Row(children: [
                for (var k = 0; k < (i?.rewarded ?? 3); k++)
                  Expanded(
                    child: Container(
                      height: 92,
                      margin: EdgeInsets.only(right: k < (i?.rewarded ?? 3) - 1 ? 10 : 0),
                      decoration: BoxDecoration(
                        color: k < (i?.friends ?? 0) ? AppColors.brand.withValues(alpha: 0.16) : AppColors.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: k < (i?.friends ?? 0) ? AppColors.brand : AppColors.border,
                            width: k < (i?.friends ?? 0) ? 1.5 : 1),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(k < (i?.friends ?? 0) ? Icons.person_rounded : Icons.person_add_alt_rounded,
                            color: k < (i?.friends ?? 0) ? AppColors.brand : AppColors.textDim),
                        const SizedBox(height: 6),
                        Text(k < (i?.friends ?? 0) ? tr('Dabei') : tr('Frei'),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: k < (i?.friends ?? 0) ? AppColors.text : AppColors.textDim)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              if (i != null && i.bonusQuestions > 0)
                Text(tr('Schon {n} Fragen extra im Monat.', {'n': i.bonusQuestions}),
                    style: TextStyle(color: AppColors.positiveText, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              if (_loading && i == null)
                const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
              else if (i == null)
                Text(tr('Dein Einladungslink lädt gerade nicht. Prüf die Verbindung und versuch es gleich noch einmal.'),
                    style: TextStyle(color: AppColors.textDim))
              else ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(tr('Dein Code'), style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                        Text(i.code,
                            style: const TextStyle(fontFamily: AppFonts.display, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4)),
                      ]),
                    ),
                    IconButton(
                      tooltip: tr('Link kopieren'),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: i.link));
                        HapticFeedback.selectionClick();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Link kopiert'))));
                        }
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: () => _share(i),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(i.open > 0 ? tr('Einladung senden') : tr('Weiter einladen')),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                tr('Wer über deinen Link kommt, sieht deinen Vornamen nicht und bekommt keine Daten von dir. Wir zählen nur, dass jemand mitgemacht hat.'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.45),
              ),
            ],
          ),
        );
      },
    );
  }
}

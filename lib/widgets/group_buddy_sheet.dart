// Buddy in a shared group (WG, couple, trip): who owes whom, the fewest
// transfers to settle up, and a message for the group chat that does the
// awkward part. The message carries the group code, so the others can join.
//
// Everything here is worked out on the device from the group alone; nothing
// from the person's own finances is used or shared.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import '../models/split.dart';
import '../services/split_service.dart';
import '../utils/money.dart';
import '../utils/theme.dart';
import 'buddy_orb.dart';

class GroupBuddy {
  // the group chat message: friendly, with the fewest transfers
  static String message(SplitGroup g) {
    final transfers = SplitMath.settleUp(g);
    String who(int i) => i == g.me ? tr('ich') : g.members[i];
    String whoCap(int i) => i == g.me ? tr('Ich') : g.members[i];
    final total = g.expenses.fold<int>(0, (s, e) => s + e.cents);
    final lines = <String>[
      tr('Kurzer Stand für „{name}“ von Buddy:', {'name': g.name}),
      if (total > 0) tr('Zusammen ausgegeben: {x}', {'x': Money.raw(total)}),
      '',
      if (transfers.isEmpty)
        tr('Alle sind quitt. Nichts zu tun.')
      else ...[
        tr('So sind wir mit {n} {x} quitt:',
            {'n': transfers.length, 'x': transfers.length == 1 ? tr('Überweisung') : tr('Überweisungen')}),
        for (final t in transfers) '- ${whoCap(t.from)} → ${who(t.to)}: ${Money.raw(t.cents)}',
      ],
    ];
    final link = g.code == null ? null : SplitService.inviteLink(g.code!);
    if (g.code != null) {
      lines.addAll([
        '',
        link != null
            ? tr('Live mitrechnen in Ahead: {link}', {'link': link})
            : tr('Live mitrechnen in Ahead, Gruppencode {code}', {'code': g.code}),
      ]);
    }
    return lines.join('\n');
  }
}

Future<void> showGroupBuddy(BuildContext context, SplitGroup g, {required void Function(String question) onAsk}) {
  HapticFeedback.selectionClick();
  final transfers = SplitMath.settleUp(g);
  final balances = SplitMath.balances(g);
  String who(int i) => i == g.me ? tr('Du') : g.members[i];
  final mine = g.me < balances.length ? balances[g.me] : 0;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Row(children: [
              const BuddyOrb(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr('Buddy für {name}', {'name': g.name}),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  Text(tr('Nur aus den Ausgaben dieser Gruppe'),
                      style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Text(
              mine == 0
                  ? tr('Du bist quitt.')
                  : mine > 0
                      ? tr('Du bekommst noch {x}.', {'x': Money.raw(mine)})
                      : tr('Du schuldest noch {x}.', {'x': Money.raw(-mine)}),
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.6),
            ),
            const SizedBox(height: 16),
            if (transfers.isEmpty)
              Text(tr('Alle sind quitt.'), style: TextStyle(color: AppColors.textDim))
            else ...[
              Text(
                  tr('Mit {n} {x} seid ihr quitt:',
                      {'n': transfers.length, 'x': transfers.length == 1 ? tr('Überweisung') : tr('Überweisungen')}),
                  style: TextStyle(color: AppColors.textDim)),
              const SizedBox(height: 8),
              for (final t in transfers)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Expanded(
                      child: Text('${who(t.from)} → ${who(t.to)}',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: t.from == g.me || t.to == g.me ? AppColors.text : AppColors.textDim)),
                    ),
                    Text(Money.raw(t.cents), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ]),
                ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final text = GroupBuddy.message(g);
                try {
                  await Share.share(text);
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (sheet.mounted) {
                    ScaffoldMessenger.of(sheet).showSnackBar(SnackBar(content: Text(tr('Nachricht kopiert'))));
                  }
                }
              },
              icon: const Icon(Icons.ios_share_rounded),
              label: Text(tr('Stand an die Gruppe schicken')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () {
                Navigator.pop(sheet);
                onAsk(tr('Wie teilen wir die Kosten in „{name}“ am fairsten auf?', {'name': g.name}));
              },
              icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
              label: Text(tr('Buddy fragen, was fair ist')),
            ),
            const SizedBox(height: 12),
            Text(
              tr('Die Nachricht enthält nur die Beträge dieser Gruppe und den Gruppencode, nichts aus deinen eigenen Finanzen.'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    ),
  );
}

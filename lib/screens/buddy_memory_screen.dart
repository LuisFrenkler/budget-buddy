// "Was Buddy über dich weiß": every fact Buddy may use, each one deletable,
// all of them with one tap. Nothing gets here without the person's "Merken".
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../services/buddy_memory.dart';
import '../services/life_stages.dart';
import '../utils/dates.dart';
import '../utils/theme.dart';
import '../widgets/buddy_orb.dart';
import '../services/buddy_journal.dart';
import '../services/payslip_history.dart';
import '../widgets/buddy_chart.dart';

class BuddyMemoryScreen extends StatelessWidget {
  const BuddyMemoryScreen({super.key});

  Future<void> _clear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Alles vergessen?')),
        content: Text(tr('Ahead vergisst alles Gemerkte. Buchungen und Ziele bleiben.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr('Abbrechen'))),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(tr('Alles vergessen'))),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.mediumImpact();
      await BuddyMemory.clear();
      await BuddyJournal.clear();
      await PayslipHistory.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: BuddyMemory.changed,
      builder: (context, _, __) {
        final facts = BuddyMemory.all().reversed.toList();
        final talks = BuddyJournal.forAgent();
        final stage = LifeStages.current;
        final payChart = PayslipHistory.chart();
        return Scaffold(
          appBar: AppBar(title: Text(tr('Was Ahead weiß'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const BuddyOrb(size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    tr('Ich merke mir nur, was du bestätigst, dann muss ich nicht neu fragen. Alles hier kannst du löschen.'),
                    style: TextStyle(color: AppColors.textDim, height: 1.45),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              if (payChart != null) ...[
                BuddyChartCard(payChart),
                const SizedBox(height: 8),
              ],
              if (stage != null) ...[
                _label(tr('Lebenslage')),
                _tile(
                  icon: stage.icon,
                  title: stage.name,
                  subtitle: tr('{done} von {all} Schritten erledigt',
                      {'done': LifeStages.progress(stage), 'all': stage.steps.length}),
                  onDelete: () async {
                    await LifeStages.choose(null);
                    BuddyMemory.changed.value++;
                  },
                ),
                const SizedBox(height: 20),
              ],
              _label(tr('Gemerkt')),
              if (facts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
                  child: Text(
                    tr('Noch nichts. Sag Ahead z. B. „Merk dir: im Oktober fängt mein erster Job an“.'),
                    style: TextStyle(color: AppColors.textDim, height: 1.45),
                  ),
                )
              else
                // sorted by what it is about: money and dates, goals, life, likes
                for (final kind in MemoryKind.values)
                  for (final (i, f) in facts.where((f) => BuddyMemory.kindOf(f.text) == kind).indexed) ...[
                    if (i == 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6, left: 2),
                        child: Text(tr(kind.label),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textDim)),
                      ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _tile(
                      icon: switch (kind) {
                        MemoryKind.money => Icons.event_note_outlined,
                        MemoryKind.goal => Icons.flag_outlined,
                        MemoryKind.life => Icons.home_outlined,
                        MemoryKind.preference => Icons.favorite_border_rounded,
                        MemoryKind.other => Icons.bookmark_outline_rounded,
                      },
                      title: f.text,
                      subtitle: tr('Gemerkt am {date}', {'date': Dates.dayMonth(f.at)}),
                      onDelete: () {
                        HapticFeedback.selectionClick();
                        BuddyMemory.remove(f.id);
                      },
                    ),
                  ),
                  ],
              if (talks.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(tr('Worüber ihr gesprochen habt'),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 4),
                Text(tr('Damit Ahead später anknüpfen kann. Nur Frage und nächster Schritt, 60 Tage.'),
                    style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.4)),
                const SizedBox(height: 8),
                for (final t in talks.take(6))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Text('${Dates.dayMonth(DateTime.parse('${t['am']}'))} · ${t['frage']}',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5)),
                  ),
              ],
              const SizedBox(height: 24),
              if (facts.isNotEmpty || talks.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: AppColors.errorText,
                    side: BorderSide(color: AppColors.errorText.withValues(alpha: 0.4)),
                  ),
                  onPressed: () => _clear(context),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: Text(tr('Alles vergessen')),
                ),
              const SizedBox(height: 16),
              Text(
                tr('Ist „Ahead mit KI“ an, gehen diese Punkte mit deiner Finanz-Zusammenfassung an die KI, nur wenn du fragst.'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12.5, height: 1.45),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: TextStyle(
                fontFamily: AppFonts.display, fontSize: 18, letterSpacing: -0.4, fontWeight: FontWeight.w700, color: AppColors.text)),
      );

  Widget _tile({required IconData icon, required String title, required String subtitle, required VoidCallback onDelete}) =>
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Icon(icon, color: AppColors.brand, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
            ]),
          ),
          IconButton(
            tooltip: tr('Löschen'),
            onPressed: onDelete,
            icon: Icon(Icons.close_rounded, color: AppColors.textDim, size: 20),
          ),
        ]),
      );
}

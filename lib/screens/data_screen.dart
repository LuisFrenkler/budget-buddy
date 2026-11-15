// "Wo deine Daten liegen": every kind of data, where it lives, who can read
// it and how to end it, with what is switched on for you right now. Built
// from DataMap, the same list Buddy answers from.
import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../legal/data_map.dart';
import '../legal/legal_texts.dart';
import '../services/account_service.dart';
import '../services/backend_service.dart';
import '../services/buddy_memory.dart';
import '../services/buddy_service.dart';
import '../services/data_export.dart';
import '../services/file_saver.dart';
import '../services/db.dart';
import '../services/plus_service.dart';
import '../services/settings_service.dart';
import '../utils/theme.dart';
import 'about_screen.dart';

class DataScreen extends StatelessWidget {
  final DataStatus? status;
  const DataScreen({super.key, this.status});

  // what is on right now, read from the app
  static DataStatus current() {
    bool safe(bool Function() f) {
      try {
        return f();
      } catch (_) {
        return false;
      }
    }

    return DataStatus(
      signedIn: AccountService.current.value != null,
      bankLinked: safe(() => Settings.bankState.isNotEmpty || Settings.extraBanks.isNotEmpty),
      depotLinked: safe(() => Settings.depotState.isNotEmpty || Settings.extraDepots.isNotEmpty),
      aiConsent: safe(() => BuddyService.hasConsent),
      aiProvider: BuddyService.provider,
      plus: PlusService.active.value,
      holdings: safe(() => DB.getHoldings().isNotEmpty),
      memories: (() {
        try {
          return BuddyMemory.all().length;
        } catch (_) {
          return 0;
        }
      })(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flows = DataMap.flows(status ?? current());
    final on = flows.where((f) => f.active).toList();
    final off = flows.where((f) => !f.active).toList();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Wo deine Daten liegen'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(
            tr('Für jede Art von Daten: wo sie liegen, wer sie lesen kann und wie du sie stoppst. Was gerade an ist, steht oben.'),
            style: TextStyle(color: AppColors.textDim, height: 1.4),
          ),
          const SizedBox(height: 14),
          _legend(),
          const SizedBox(height: 18),
          _label(tr('Gerade aktiv')),
          for (final f in on) _card(f),
          const SizedBox(height: 18),
          _label(tr('Nur wenn du es nutzt')),
          for (final f in off) _card(f),
          const SizedBox(height: 18),
          Text(tr('Wir zeigen keine Werbung, nutzen kein Tracking und verkaufen keine Daten.'),
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('export-all'),
            onPressed: () async {
              // with an account, the server's part comes too (when it is reachable)
              Map<String, dynamic>? server;
              if (AccountService.current.value != null) {
                try {
                  server = await BackendService.exportAccount().timeout(const Duration(seconds: 6));
                } catch (_) {}
              }
              final json = DataExport.build(status: status ?? current(), server: server);
              await saveTextFile('ahead_alle_meine_daten.json', json, text: tr('Alle meine Daten'));
            },
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(tr('Alle meine Daten herunterladen')),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => LegalDocScreen(doc: LegalTexts.privacy))),
              child: Text(tr('Datenschutzerklärung')),
            ),
          ),
        ],
      ),
    );
  }

  static (IconData, String) _place(DataPlace p) => switch (p) {
        DataPlace.device => (Icons.phone_iphone_rounded, tr('Auf deinem Gerät')),
        DataPlace.ourServer => (Icons.dns_outlined, tr('Bei uns')),
        DataPlace.provider => (Icons.hub_outlined, tr('Bei einem Partner')),
      };

  Widget _legend() => Wrap(spacing: 14, runSpacing: 6, children: [
        for (final p in DataPlace.values)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_place(p).$1, size: 16, color: AppColors.textDim),
            const SizedBox(width: 4),
            Text(_place(p).$2, style: TextStyle(color: AppColors.textDim, fontSize: 12.5)),
          ]),
      ]);

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );

  Widget _card(DataFlow f) {
    final (icon, place) = _place(f.place);
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 74, child: Text(k, style: TextStyle(color: AppColors.textDim, fontSize: 12.5))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 13.5, height: 1.35))),
          ]),
        );
    return Semantics(
      container: true,
      child: Container(
        key: Key('flow-${f.id}'),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: f.active ? Border.all(color: AppColors.border) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: f.active ? AppColors.text : AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(child: Text(f.what, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.3))),
          ]),
          row(tr('Wo'), '$place: ${f.where}'),
          row(tr('Wer liest'), f.who),
          row(tr('Stoppen'), f.end),
        ]),
      ),
    );
  }
}

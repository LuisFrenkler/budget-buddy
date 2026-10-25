import 'package:flutter/material.dart';
import '../utils/money.dart';
import 'instrument_avatar.dart';
import '../utils/instruments.dart';
import '../utils/theme.dart';

// Bottom sheet to search and pick a real instrument. Returns the chosen
// Instrument via Navigator.pop, or a custom one built from the query.
class InstrumentSearchSheet extends StatefulWidget {
  const InstrumentSearchSheet({super.key});

  @override
  State<InstrumentSearchSheet> createState() => _InstrumentSearchSheetState();
}

class _InstrumentSearchSheetState extends State<InstrumentSearchSheet> {
  String _q = '';


  @override
  Widget build(BuildContext context) {
    final results = Instruments.search(_q);
    final exact = results.any((i) =>
        i.name.toLowerCase() == _q.trim().toLowerCase() ||
        i.symbol.toLowerCase() == _q.trim().toLowerCase());

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(
                color: AppColors.border, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(
                  hintText: 'Aktie, ETF oder Krypto suchen...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  // let the user keep a custom name that isn't in the list
                  if (_q.trim().isNotEmpty && !exact)
                    ListTile(
                      leading: const Icon(Icons.add, color: AppColors.primary),
                      title: Text('„${_q.trim()}" verwenden'),
                      subtitle: const Text('Eigenes Wertpapier'),
                      onTap: () => Navigator.pop(
                          context, Instrument(_q.trim(), '', 'Aktie', 0)),
                    ),
                  for (final i in results)
                    ListTile(
                      leading: InstrumentAvatar(i.name),
                      title: Text(i.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${i.symbol} · ${i.type}', style: TextStyle(color: AppColors.textDim)),
                      // reference price, upgraded to a live quote after picking
                      trailing: i.refCents > 0
                          ? Text(Money.format(i.refCents), style: const TextStyle(fontWeight: FontWeight.w600))
                          : null,
                      onTap: () => Navigator.pop(context, i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

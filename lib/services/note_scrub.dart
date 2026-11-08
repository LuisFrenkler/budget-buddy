// One-shot cleanup of SEPA junk titles already stored on bookings
// (Mandats-/Mandantenreferenz, Gläubiger-ID, …).
import 'package:hive/hive.dart';
import '../models/transaction.dart';
import '../utils/merchant.dart';
import 'db.dart';

class NoteScrub {
  static const _flag = 'notesScrubbedSepaV2';

  static Future<int> runOnce() async {
    if (!Hive.isBoxOpen('settings') || !Hive.isBoxOpen('transactions')) return 0;
    if (Hive.box('settings').get(_flag) == true) return 0;
    final n = await run();
    await Hive.box('settings').put(_flag, true);
    return n;
  }

  static Future<int> run() async {
    var n = 0;
    for (final t in DB.getTx()) {
      final raw = t.note?.trim() ?? '';
      if (raw.isEmpty || !Merchant.isSepaJunk(raw)) continue;
      final next = Merchant.present(raw, fallback: t.category);
      if (next == raw) continue;
      await DB.addTx(Transaction(
        id: t.id,
        amountCents: t.amountCents,
        category: t.category,
        date: t.date,
        isIncome: t.isIncome,
        note: next == t.category ? null : next,
        accountId: t.accountId,
      ));
      n++;
    }
    return n;
  }
}

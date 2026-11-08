// While Hive rewrites opening + bookings (cloud vault, bank sync), the live
// sum jumps through wrong intermediate values. Capture cash once at enter and
// keep the UI on that figure until every nested batch has left.
import 'package:flutter/foundation.dart';
import 'db.dart';
import 'money_accounts.dart';

class LedgerBusy {
  static final on = ValueNotifier(false);
  static int _depth = 0;
  static int? _cash;

  static int? get frozenCash => _cash;

  static void enter() {
    if (_depth == 0) {
      _cash = DB.balanceOf(DB.getTx()) + MoneyAccounts.openingTotal;
      on.value = true;
    }
    _depth++;
  }

  static void leave() {
    if (_depth == 0) return;
    _depth--;
    if (_depth == 0) {
      on.value = false;
      _cash = null;
    }
  }

  static int cashOr(int live) => on.value ? (_cash ?? live) : live;
}

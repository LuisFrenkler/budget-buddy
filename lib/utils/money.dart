// Money handling for BudgetBuddy.
//
// All amounts in the app are stored and calculated as integer cents (int),
// never as double. Floating point math is not exact (0.1 + 0.2 != 0.3), which
// is unacceptable for a finance app. We only convert to a human readable
// string at the very edge, using German (de_DE) currency formatting.
import 'package:intl/intl.dart';

class Money {
  // German currency format, e.g. 123450 cents -> "1.234,50 €"
  static final NumberFormat _fmt =
      NumberFormat.currency(locale: 'de_DE', symbol: '€', decimalDigits: 2);

  // formats cents as German currency. handles its own minus sign.
  static String format(int cents) => _fmt.format(cents / 100);

  // formats with an explicit leading + for positive values (used for balances)
  static String signed(int cents) => (cents >= 0 ? '+' : '') + format(cents);

  // formats a positive amount with a + or - depending on income/expense
  static String withSign(int cents, bool isIncome) =>
      (isIncome ? '+' : '-') + format(cents.abs());

  // parses user or CSV input into cents. accepts both German (12,99) and
  // English (12.99) decimal separators as well as thousands separators.
  // returns null if the input cannot be parsed into a valid amount.
  static int? parseToCents(String input) {
    var s = input.trim().replaceAll('€', '').replaceAll(' ', '');
    if (s.isEmpty) return null;

    // remember and strip a leading minus
    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);

    // the LAST '.' or ',' is treated as the decimal separator,
    // everything before it that is '.' or ',' is a thousands separator
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    final decPos = lastComma > lastDot ? lastComma : lastDot;

    String intPart;
    String fracPart;
    if (decPos == -1) {
      intPart = s;
      fracPart = '';
    } else {
      intPart = s.substring(0, decPos);
      fracPart = s.substring(decPos + 1);
    }

    // drop thousands separators from the integer part
    intPart = intPart.replaceAll('.', '').replaceAll(',', '');
    if (intPart.isEmpty) intPart = '0';

    // both parts must be plain digits
    if (!RegExp(r'^\d+$').hasMatch(intPart)) return null;
    if (fracPart.isNotEmpty && !RegExp(r'^\d+$').hasMatch(fracPart)) return null;

    // pad/truncate the fraction to exactly 2 digits
    fracPart = '${fracPart}00'.substring(0, 2);

    final cents = int.parse(intPart) * 100 + int.parse(fracPart);
    return negative ? -cents : cents;
  }
}

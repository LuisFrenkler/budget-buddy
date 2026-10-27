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

  // typographic minus (U+2212) used for display instead of the hyphen
  static const minus = '\u2212';

  // what an amount shows in privacy mode
  static const hidden = '•••••• €';

  // privacy mode ("Beträge verbergen"): every amount on screen goes through
  // format(), so one switch covers all of them, including new screens
  static bool masked = false;

  // formats cents as German currency. handles its own minus sign.
  static String format(int cents) => masked ? hidden : raw(cents);

  // the real amount even in privacy mode: prices, messages sent to others
  static String raw(int cents) => _fmt.format(cents / 100).replaceFirst('-', minus);

  // formats with an explicit leading + for positive values (used for balances)
  static String signed(int cents) => masked ? hidden : (cents >= 0 ? '+' : '') + format(cents);

  // formats a positive amount with a + or - depending on income/expense
  static String withSign(int cents, bool isIncome) =>
      masked ? hidden : (isIncome ? '+' : minus) + format(cents.abs());

  // parses user or CSV input into cents. accepts both German (12,99) and
  // English (12.99) decimal separators as well as thousands separators.
  // returns null if the input cannot be parsed into a valid amount.
  static int? parseToCents(String input) {
    var s = input.trim().replaceAll('€', '').replaceAll(' ', '').replaceAll(minus, '-');
    if (s.isEmpty) return null;

    // remember and strip a leading minus
    final negative = s.startsWith('-');
    if (negative) s = s.substring(1);

    // the LAST '.' or ',' is treated as the decimal separator,
    // everything before it that is '.' or ',' is a thousands separator
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    var decPos = lastComma > lastDot ? lastComma : lastDot;
    // "1.250" or "12.500.000" without a comma: German thousands, not decimals
    if (lastComma == -1 && lastDot != -1 && RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) decPos = -1;

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

  // formats a percentage German style, e.g. 35.24 -> "+35,24 %"
  // a price per unit: coins under a euro keep their decimals ("0,0543 €")
  static String unit(int cents, {double? euros}) {
    if (masked) return hidden;
    if (euros != null && euros < 1) {
      return '${NumberFormat.decimalPatternDigits(locale: 'de_DE', decimalDigits: 4).format(euros)} €';
    }
    return raw(cents);
  }

  static String percent(double value, {int digits = 1, bool signed = true}) {
    final s = NumberFormat.decimalPatternDigits(locale: 'de_DE', decimalDigits: digits).format(value);
    return '${signed && value >= 0 ? '+' : ''}${s.replaceFirst('-', minus)} %';
  }
}

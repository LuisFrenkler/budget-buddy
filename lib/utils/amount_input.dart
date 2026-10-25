// Pure logic behind the on-screen number pad: the typed amount is kept as a
// plain string like "1250,5" and every key press returns the new string.
class AmountInput {
  static const maxIntDigits = 7; // up to 9.999.999 €

  // applies one key ('0'-'9', ',' or 'del') to the current input
  static String press(String current, String key) {
    final comma = current.indexOf(',');
    if (key == 'del') {
      return current.isEmpty ? current : current.substring(0, current.length - 1);
    }
    if (key == ',') {
      if (comma != -1) return current;
      return current.isEmpty ? '0,' : '$current,';
    }
    if (!RegExp(r'^\d$').hasMatch(key)) return current;
    if (comma != -1) {
      // at most two decimals
      return current.length - comma - 1 >= 2 ? current : current + key;
    }
    // no leading zeros, limited length
    if (current == '0') return key;
    if (current.length >= maxIntDigits) return current;
    return current + key;
  }

  // formats the input for display with thousands separators, e.g. "1.250,5"
  static String display(String input) {
    if (input.isEmpty) return '0';
    final comma = input.indexOf(',');
    final intPart = comma == -1 ? input : input.substring(0, comma);
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
      buf.write(intPart[i]);
    }
    return comma == -1 ? buf.toString() : '$buf${input.substring(comma)}';
  }

  // the input in cents, e.g. "12,5" -> 1250
  static int cents(String input) {
    if (input.isEmpty) return 0;
    final comma = input.indexOf(',');
    final intPart = comma == -1 ? input : input.substring(0, comma);
    final frac = comma == -1 ? '' : input.substring(comma + 1);
    return int.parse(intPart.isEmpty ? '0' : intPart) * 100 + int.parse('${frac}00'.substring(0, 2));
  }

  // cents back to an editable input, e.g. 1250 -> "12,5", 1200 -> "12"
  static String fromCents(int cents) {
    final euros = cents ~/ 100;
    final rest = cents % 100;
    if (rest == 0) return '$euros';
    final frac = rest.toString().padLeft(2, '0');
    return '$euros,${frac.endsWith('0') ? frac[0] : frac}';
  }
}

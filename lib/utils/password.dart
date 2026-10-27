// How strong a new password is, the same on sign-up and when changing it.
// 0..4 and a word for it; length counts most, then variety
(int, String) passwordStrength(String p) {
  if (p.isEmpty) return (0, '');
  var score = 0;
  if (p.length >= 8) score++;
  if (p.length >= 12) score++;
  final kinds = [RegExp(r'[a-z]'), RegExp(r'[A-Z]'), RegExp(r'\d'), RegExp(r'[^A-Za-z0-9]')]
      .where((r) => r.hasMatch(p))
      .length;
  if (kinds >= 3) score++;
  if (p.length >= 16 || (p.length >= 12 && kinds == 4)) score++;
  if (p.length < 8) score = 0;
  return (score, const ['Zu kurz', 'Schwach', 'Okay', 'Gut', 'Stark'][score]);
}

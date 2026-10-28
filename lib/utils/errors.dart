// User-facing error text: never dump raw exceptions into snackbars.
String friendlyError(Object e, {String fallback = 'Das hat gerade nicht geklappt. Versuch es gleich noch einmal.'}) {
  final s = '$e'.trim();
  if (s.isEmpty) return fallback;
  // already German product copy from services
  if (s.contains(' ') && !s.contains('Exception') && !s.contains('Error:') && !s.startsWith('Http')) {
    if (s.length <= 180) return s;
  }
  if (s.toLowerCase().contains('socket') ||
      s.toLowerCase().contains('failed host lookup') ||
      s.toLowerCase().contains('network') ||
      s.toLowerCase().contains('connection')) {
    return 'Keine Verbindung. Prüfe dein Internet und versuch es noch einmal.';
  }
  if (s.toLowerCase().contains('timeout')) {
    return 'Das dauert zu lange. Versuch es gleich noch einmal.';
  }
  return fallback;
}

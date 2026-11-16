// User-facing error text: never dump raw exceptions into snackbars.

import '../l10n/l10n.dart';
String friendlyError(Object e, {String? fallback}) {
  final fb = fallback ?? tr('Das hat gerade nicht geklappt. Versuch es gleich noch einmal.');
  final s = '$e'.trim();
  if (s.isEmpty) return fb;
  // already German product copy from services
  // product copy (often German from the server) goes through tr, so English UI stays English
  if (s.contains(' ') && !s.contains('Exception') && !s.contains('Error:') && !s.startsWith('Http')) {
    if (s.length <= 180) return tr(s);
  }
  if (s.toLowerCase().contains('socket') ||
      s.toLowerCase().contains('failed host lookup') ||
      s.toLowerCase().contains('network') ||
      s.toLowerCase().contains('connection')) {
    return tr('Keine Verbindung. Prüfe dein Internet und versuch es noch einmal.');
  }
  if (s.toLowerCase().contains('timeout')) {
    return tr('Das dauert zu lange. Versuch es gleich noch einmal.');
  }
  return fb;
}

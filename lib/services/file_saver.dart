// Cross-platform "save/share a text file" entry point.
//
// On mobile/desktop it writes a temp file and opens the share sheet; on web it
// triggers a browser download. The right implementation is chosen at compile
// time via the conditional export below, so neither dart:io nor dart:html ever
// leaks onto a platform that can't handle it.
export 'file_saver_io.dart' if (dart.library.html) 'file_saver_web.dart';

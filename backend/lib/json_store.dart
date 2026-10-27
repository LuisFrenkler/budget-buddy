// Writes a JSON file so a crash mid-write never leaves it half written:
// the text goes to a temp file first, which then replaces the old one.
// Writes to the same file run in call order, so the newest data wins.
import 'dart:convert';
import 'dart:io';

final _pending = <String, Future<void>>{};

Future<void> writeJsonAtomic(File file, Object data) {
  final text = jsonEncode(data); // the state at call time, not when the write runs
  final next = (_pending[file.path] ?? Future.value()).catchError((_) {}).then((_) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(file.path);
  });
  _pending[file.path] = next;
  return next;
}

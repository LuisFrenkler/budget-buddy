// Buddy's answers can end with two small machine lines the chat turns into UI:
//
//   [merken: Luis hat im Oktober seinen ersten Job angefangen]
//   [weiter: Wie viel Notgroschen? | Lohnt sich die Betriebsrente?]
//
// "merken" becomes a card the person confirms (nothing is remembered without
// that tap), "weiter" becomes two follow-up questions under the answer. The
// text the person reads never shows the brackets, also while the answer is
// still streaming in.
class BuddyMarkers {
  final String text; // what the person reads
  final String? remember; // a fact Buddy suggests to remember
  final List<String> followUps;

  const BuddyMarkers(this.text, {this.remember, this.followUps = const []});

  static final _line = RegExp(r'^\s*\[(merken|weiter)\s*:\s*(.*?)\]?\s*$', caseSensitive: false);

  // splits a (possibly unfinished) answer into readable text and markers
  static BuddyMarkers parse(String raw) {
    final lines = raw.split('\n');
    final keep = <String>[];
    String? remember;
    var follow = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final m = _line.firstMatch(line);
      if (m != null) {
        final kind = m.group(1)!.toLowerCase();
        final body = m.group(2)!.trim();
        final complete = line.trimRight().endsWith(']');
        if (kind == 'merken' && complete && body.isNotEmpty) remember = body;
        if (kind == 'weiter' && complete) {
          follow = [
            for (final q in body.split('|'))
              if (q.trim().isNotEmpty && q.trim().length <= 60) q.trim()
          ].take(3).toList();
        }
        continue;
      }
      // the start of a marker that is still arriving: hide it until it is whole
      final last = i == lines.length - 1;
      if (last && RegExp(r'^\s*\[[a-zA-Z]{0,7}$').hasMatch(line)) continue;
      keep.add(line);
    }
    while (keep.isNotEmpty && keep.last.trim().isEmpty) {
      keep.removeLast();
    }
    return BuddyMarkers(keep.join('\n'), remember: remember, followUps: follow);
  }
}

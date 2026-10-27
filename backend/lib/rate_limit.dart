// Counts attempts per key (an IP address) in a sliding time window.
class RateLimit {
  final int max;
  final Duration window;
  final _hits = <String, List<DateTime>>{};

  RateLimit(this.max, this.window);

  // the key has used up its attempts for now
  bool blocked(String key, {DateTime? now}) => _recent(key, now ?? DateTime.now()).length >= max;

  void hit(String key, {DateTime? now}) {
    final t = now ?? DateTime.now();
    _recent(key, t).add(t);
    // keys that went quiet are forgotten, so the map stays small
    if (_hits.length > 10000) _hits.removeWhere((_, list) => list.every((h) => t.difference(h) >= window));
  }

  List<DateTime> _recent(String key, DateTime now) =>
      (_hits[key] ??= [])..removeWhere((h) => now.difference(h) >= window);
}

// Shared spending: a group (flat share, couple, trip), who paid what and
// who owes whom. Kept on this device; the others get their balance as a
// message.
class SplitExpense {
  final String id;
  final String title;
  final int cents;
  final int paidBy; // index into the group's members
  final Map<int, int> shares; // member index -> cents of this expense
  final DateTime date;
  final String? txId; // the booking it came from, if any

  const SplitExpense({
    required this.id,
    required this.title,
    required this.cents,
    required this.paidBy,
    required this.shares,
    required this.date,
    this.txId,
  });

  // even split; the first members get the leftover cents
  static Map<int, int> even(int cents, List<int> members) {
    final base = cents ~/ members.length;
    var rest = cents - base * members.length;
    return {for (final m in members) m: base + (rest-- > 0 ? 1 : 0)};
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'cents': cents,
        'paidBy': paidBy,
        'shares': {for (final e in shares.entries) '${e.key}': e.value},
        'date': date.millisecondsSinceEpoch,
        'txId': txId,
      };

  factory SplitExpense.fromMap(Map m) => SplitExpense(
        id: m['id'] as String,
        title: m['title'] as String,
        cents: (m['cents'] as num).toInt(),
        paidBy: (m['paidBy'] as num).toInt(),
        shares: {for (final e in (m['shares'] as Map).entries) int.parse('${e.key}'): (e.value as num).toInt()},
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
        txId: m['txId'] as String?,
      );
}

// money that changed hands to settle up
class Settlement {
  final int from;
  final int to;
  final int cents;
  final DateTime date;
  const Settlement(this.from, this.to, this.cents, this.date);

  Map<String, dynamic> toMap() => {'from': from, 'to': to, 'cents': cents, 'date': date.millisecondsSinceEpoch};

  factory Settlement.fromMap(Map m) => Settlement((m['from'] as num).toInt(), (m['to'] as num).toInt(),
      (m['cents'] as num).toInt(), DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()));
}

class SplitGroup {
  final String id;
  final String name;
  final String emoji;
  final List<String> members; // members[0] is the user ("Ich")
  final List<SplitExpense> expenses;
  final List<Settlement> settlements;
  // on this device: which member the user is, and the invite code once the
  // group is shared through the server (null = only on this device)
  int me;
  String? code;
  int version;

  SplitGroup({
    required this.id,
    required this.name,
    required this.emoji,
    required this.members,
    List<SplitExpense>? expenses,
    List<Settlement>? settlements,
    this.me = 0,
    this.code,
    this.version = 0,
  })  : expenses = expenses ?? [],
        settlements = settlements ?? [];

  bool get shared => code != null;

  // what the server stores: the same for everyone, without the local fields
  Map<String, dynamic> toShared() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'members': members,
        'expenses': [for (final e in expenses) e.toMap()],
        'settlements': [for (final s in settlements) s.toMap()],
      };

  Map<String, dynamic> toMap() => {...toShared(), 'me': me, 'code': code, 'version': version};

  factory SplitGroup.fromMap(Map m) => SplitGroup(
        me: (m['me'] as num? ?? 0).toInt(),
        code: m['code'] as String?,
        version: (m['version'] as num? ?? 0).toInt(),
        id: m['id'] as String,
        name: m['name'] as String,
        emoji: m['emoji'] as String? ?? '👥',
        members: (m['members'] as List).cast<String>().toList(),
        expenses: [for (final e in (m['expenses'] as List? ?? const [])) SplitExpense.fromMap(e as Map)],
        settlements: [for (final s in (m['settlements'] as List? ?? const [])) Settlement.fromMap(s as Map)],
      );
}

// one transfer that settles (part of) the group
class Transfer {
  final int from;
  final int to;
  final int cents;
  const Transfer(this.from, this.to, this.cents);
}

class SplitMath {
  // per member: positive = gets money back, negative = owes
  static List<int> balances(SplitGroup g) {
    final b = List<int>.filled(g.members.length, 0);
    for (final e in g.expenses) {
      b[e.paidBy] += e.cents;
      for (final s in e.shares.entries) {
        b[s.key] -= s.value;
      }
    }
    for (final s in g.settlements) {
      b[s.from] += s.cents;
      b[s.to] -= s.cents;
    }
    return b;
  }

  // the fewest transfers that settle everything: the biggest debtor pays
  // the biggest creditor until one of them is even, repeat
  static List<Transfer> settleUp(SplitGroup g) {
    final b = balances(g);
    final out = <Transfer>[];
    while (true) {
      var maxI = 0, minI = 0;
      for (var i = 1; i < b.length; i++) {
        if (b[i] > b[maxI]) maxI = i;
        if (b[i] < b[minI]) minI = i;
      }
      if (b[maxI] <= 0 || b[minI] >= 0) break;
      final amount = b[maxI] < -b[minI] ? b[maxI] : -b[minI];
      out.add(Transfer(minI, maxI, amount));
      b[maxI] -= amount;
      b[minI] += amount;
    }
    return out;
  }
}

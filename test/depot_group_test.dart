import 'package:flutter_test/flutter_test.dart';
import 'package:budget_buddy/models/holding.dart';
import 'package:budget_buddy/screens/depot_screen.dart';

Holding h(String name, String type, int cents, {String? depot}) => Holding(
      id: name,
      name: name,
      symbol: name,
      type: type,
      shares: 1,
      buyPriceCents: cents,
      currentPriceCents: cents,
      depot: depot,
    );

void main() {
  test('groups by type, then by broker, largest first', () {
    final sections = groupDepotHoldings([
      h('Bitcoin', 'Krypto', 500, depot: 'Trade Republic'),
      h('Apple', 'Aktie', 300, depot: 'Scalable'),
      h('SAP', 'Aktie', 800, depot: 'Trade Republic'),
      h('Siemens', 'Aktie', 100, depot: 'Trade Republic'),
      h('MSCI World', 'ETF', 400),
      h('Gold', 'Sonstiges', 50, depot: 'comdirect'),
      h('Haus', '', 20),
    ]);

    expect(sections.map((s) => s.label).toList(), ['Aktien', 'ETFs', 'Krypto', 'Sonstiges']);

    final aktien = sections[0].groups;
    expect(showDepotBrokers(aktien), isTrue);
    expect(aktien.map((g) => g.depot).toList(), ['Trade Republic', 'Scalable']);
    expect(aktien[0].items.map((i) => i.name).toList(), ['SAP', 'Siemens']);

    final etfs = sections[1].groups;
    expect(etfs.single.depot, isNull);
    expect(showDepotBrokers(etfs), isFalse);

    expect(sections[2].groups.single.depot, 'Trade Republic');
    expect(showDepotBrokers(sections[2].groups), isTrue);

    // empty type shares the Sonstiges bucket; unnamed depot stays last
    expect(sections[3].groups.map((g) => g.depot).toList(), ['comdirect', null]);
    expect(sections[3].groups[1].items.single.name, 'Haus');
  });

  test('an unknown type keeps its name and follows the known ones', () {
    final sections = groupDepotHoldings([
      h('Anleihe', 'Anleihe', 10),
      h('Apple', 'Aktie', 20),
    ]);
    expect(sections.map((s) => s.label).toList(), ['Aktien', 'Anleihe']);
  });
}

import 'package:test/test.dart';

import '../lib/mcp.dart';

void main() {
  final today = DateTime(2026, 11, 17);
  Map<String, dynamic> call(Map<String, dynamic> args) => Mcp.handle({
        'jsonrpc': '2.0',
        'id': 3,
        'method': 'tools/call',
        'params': {'name': 'rueckhol_check', 'arguments': args},
      }, now: today)!;

  test('handshake and the tool list', () {
    final init = Mcp.handle({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize', 'params': {}})!;
    expect(init['result']['capabilities'], contains('tools'));
    expect(Mcp.handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}), isNull);
    final list = Mcp.handle({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list'})!;
    expect((list['result']['tools'] as List).single['name'], 'rueckhol_check');
    expect(Mcp.handle({'jsonrpc': '2.0', 'id': 9, 'method': 'nope'})!['error']['code'], -32601);
  });

  test('refund check: open years from the start, deadline for 2022, the running year marked', () {
    final r = call({'startJahr': 2022, 'startMonat': 9, 'bruttoMonat': 3000})['result'];
    final years = (r['structuredContent']['jahre'] as List).cast<Map>();
    expect(years.map((y) => y['jahr']), [2022, 2023, 2024, 2025, 2026]);
    expect(years.first['abgabeBis'], '2026-12-31');
    expect(years.first['monate'], 4);
    expect(years.first['bis'] as num, greaterThan(800));
    expect(years.last['abgabeBis'], isNull);
    expect((r['content'] as List).single['text'], contains('keine Steuerberatung'));
  });

  test('bad input explains itself', () {
    final r = call({'startJahr': 2022, 'bruttoMonat': -5})['result'];
    expect(r['isError'], isTrue);
  });
}

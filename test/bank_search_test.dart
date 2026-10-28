import 'package:budget_buddy/services/backend_service.dart';
import 'package:budget_buddy/services/bank_search.dart';
import 'package:flutter_test/flutter_test.dart';

Bank b(String name, {String? group}) => Bank(name, name, group: group);

void main() {
  final banks = [
    b('Sparkasse Recklinghausen', group: 'Sparkasse'),
    b('Stadtsparkasse München', group: 'Sparkasse'),
    b('Sparkasse KölnBonn', group: 'Sparkasse'),
    b('ING'),
    b('ING-DiBa AG'),
    b('Deutsche Kreditbank AG'),
    b('Deutsche Bank'),
    b('Commerzbank AG'),
    b('Volksbank Ratingen'),
    b('Trade Republic'),
  ];

  test('ING is not Recklinghausen or Ratingen', () {
    final hit = BankSearch.filter(banks, 'ING').map((e) => e.name).toList();
    expect(hit, isNot(contains('Sparkasse Recklinghausen')));
    expect(hit, isNot(contains('Volksbank Ratingen')));
    expect(hit.first, anyOf('ING', 'ING-DiBa AG'));
  });

  test('DKB finds Deutsche Kreditbank', () {
    final hit = BankSearch.filter(banks, 'DKB');
    expect(hit.map((e) => e.name), contains('Deutsche Kreditbank AG'));
    expect(hit.first.name, 'Deutsche Kreditbank AG');
  });

  test('Sparkasse Köln ranks the matching branch first', () {
    final hit = BankSearch.filter(banks, 'Sparkasse Köln');
    expect(hit, isNotEmpty);
    expect(hit.first.name, 'Sparkasse KölnBonn');
  });

  test('empty query puts major retail banks before random Sparkassen', () {
    final hit = BankSearch.filter(banks, '');
    expect(hit.take(4).map((e) => e.name).toList(),
        containsAll(['ING', 'ING-DiBa AG', 'Deutsche Kreditbank AG']));
    expect(hit.indexOf(banks.firstWhere((x) => x.name == 'ING')),
        lessThan(hit.indexOf(banks.firstWhere((x) => x.name.startsWith('Sparkasse Reckling')))));
  });
}

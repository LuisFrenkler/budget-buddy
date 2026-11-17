import 'package:test/test.dart';

import '../lib/ai.dart';

void main() {
  test('tax document schema: strict, every field required, nothing about the person', () {
    final s = Ai.taxDocSchema();
    final props = (s['properties'] as Map).keys.toSet();
    expect(s['additionalProperties'], isFalse);
    expect((s['required'] as List).toSet(), props);
    for (final banned in ['name', 'steuerId', 'steuernummer', 'iban', 'adresse']) {
      expect(props, isNot(contains(banned)));
    }
  });
}

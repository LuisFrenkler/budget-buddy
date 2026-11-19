// "Alle Bereiche": every place the agent can open is also reachable by hand,
// either in this list or as a row in the profile.
import 'package:budget_buddy/screens/places_screen.dart';
import 'package:budget_buddy/services/app_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no place is reachable only by asking', () {
    expect(PlacesScreen.complete, isTrue,
        reason: 'missing: ${AppNav.places.difference({...PlacesScreen.listed, ...PlacesScreen.inProfile})}');
    // and nothing is listed that does not exist
    expect(PlacesScreen.listed.difference(AppNav.places), isEmpty);
  });

  testWidgets('the list shows every group and its rows', (tester) async {
    tester.view.physicalSize = const Size(750, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PlacesScreen()));
    for (final name in PlacesScreen.listed) {
      expect(find.byKey(Key('place-$name')), findsOneWidget, reason: name);
    }
  });
}

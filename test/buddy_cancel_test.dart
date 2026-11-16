import 'package:budget_buddy/services/buddy_service.dart';
import 'package:budget_buddy/services/guest_buddy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cancelAsk clears tool activity and is safe to call twice', () {
    BuddyService.activity.value = 'Konten';
    BuddyService.cancelAsk();
    expect(BuddyService.activity.value, isNull);
    BuddyService.cancelAsk();
    GuestBuddy.cancelAsk();
    GuestBuddy.cancelAsk();
  });
}

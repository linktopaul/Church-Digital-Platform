import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/models/celebration_models.dart';

void main() {
  group('Celebration Models & Enum Serialization', () {
    test('CelebrationTypeX parses int, string, and maps to JSON correctly', () {
      expect(CelebrationTypeX.fromJson(0), CelebrationType.birthday);
      expect(CelebrationTypeX.fromJson(1), CelebrationType.anniversary);
      expect(CelebrationTypeX.fromJson('Birthday'), CelebrationType.birthday);
      expect(CelebrationTypeX.fromJson('Anniversary'), CelebrationType.anniversary);
      expect(CelebrationTypeX.fromJson('unknown'), CelebrationType.birthday);

      expect(CelebrationType.birthday.toJson(), 0);
      expect(CelebrationType.anniversary.toJson(), 1);
      expect(CelebrationType.birthday.displayName, 'Birthday');
      expect(CelebrationType.anniversary.displayName, 'Anniversary');
    });

    test('CelebrationEvent parses JSON and calculates milestone labels correctly', () {
      final json = {
        'memberId': 'm-123',
        'memberName': 'Grace Hopper',
        'avatarUrl': 'https://example.com/avatar.jpg',
        'type': 0,
        'date': '2026-11-03T00:00:00.000Z',
        'years': 41,
        'phoneNumber': '+15551234567',
        'whatsAppUrl': 'https://wa.me/15551234567?text=blessing',
        'canMessageDirectly': true,
      };

      final event = CelebrationEvent.fromJson(json);

      expect(event.memberId, 'm-123');
      expect(event.memberName, 'Grace Hopper');
      expect(event.avatarUrl, 'https://example.com/avatar.jpg');
      expect(event.type, CelebrationType.birthday);
      expect(event.years, 41);
      expect(event.phoneNumber, '+15551234567');
      expect(event.whatsAppUrl, 'https://wa.me/15551234567?text=blessing');
      expect(event.canMessageDirectly, isTrue);
      expect(event.milestoneLabel, '41st Birthday');

      final serialized = event.toJson();
      expect(serialized['memberId'], 'm-123');
      expect(serialized['type'], 0);
      expect(serialized['canMessageDirectly'], isTrue);
    });

    test('CelebrationEvent formats anniversary milestones correctly', () {
      final event1 = CelebrationEvent(
        memberId: '1',
        memberName: 'David',
        type: CelebrationType.anniversary,
        date: DateTime.utc(2026, 11, 3),
        years: 1,
      );
      expect(event1.milestoneLabel, '1st Anniversary');

      final event2 = CelebrationEvent(
        memberId: '2',
        memberName: 'John',
        type: CelebrationType.anniversary,
        date: DateTime.utc(2026, 11, 3),
        years: 2,
      );
      expect(event2.milestoneLabel, '2nd Anniversary');

      final event3 = CelebrationEvent(
        memberId: '3',
        memberName: 'Paul',
        type: CelebrationType.anniversary,
        date: DateTime.utc(2026, 11, 3),
        years: 3,
      );
      expect(event3.milestoneLabel, '3rd Anniversary');

      final eventNoYears = CelebrationEvent(
        memberId: '4',
        memberName: 'Sarah',
        type: CelebrationType.birthday,
        date: DateTime.utc(2026, 11, 3),
      );
      expect(eventNoYears.milestoneLabel, 'Birthday');
    });

    test('BlessingTemplate parses JSON and formats greetings with member name', () {
      final json = {
        'type': 0,
        'title': 'Birthday Blessing',
        'template': 'Dear {name}, happy birthday from your church family!',
        'defaultScripture': 'Numbers 6:24-25',
      };

      final template = BlessingTemplate.fromJson(json);

      expect(template.type, CelebrationType.birthday);
      expect(template.title, 'Birthday Blessing');
      expect(template.formatGreeting('Grace'), 'Dear Grace, happy birthday from your church family!');
      expect(template.defaultScripture, 'Numbers 6:24-25');

      final serialized = template.toJson();
      expect(serialized['type'], 0);
      expect(serialized['title'], 'Birthday Blessing');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:dclix_app/utils/training_schedule.dart';

void main() {
  group('slotLabel', () {
    test('uses the server text when present', () {
      expect(slotLabel({'id': 1, 'text': '18:00 To 19:00 (Monday) - Normal training'}),
          '18:00 To 19:00 (Monday) - Normal training');
    });

    test('builds a label from split fields when there is no text', () {
      expect(slotLabel({'dayOfWeek': 'Tuesday', 'tTimeFrom': '8:00 PM', 'tTimeTo': '9:30 PM'}),
          '8:00 PM - 9:30 PM (Tuesday)');
    });
  });

  group('slotWeekday', () {
    test('reads a full or short day name from the label, Monday = 1', () {
      expect(slotWeekday({'text': '18:00 To 19:00 (Monday)'}), 1);
      expect(slotWeekday({'text': 'Sun 9:00 AM'}), 7);
      expect(slotWeekday({'text': 'THURS 7pm'}), 4);
      expect(slotWeekday({'dayOfWeek': 'saturday'}), 6);
    });

    test('0 when no weekday is named', () {
      expect(slotWeekday({'text': 'Adult class'}), 0);
      expect(slotWeekday({'text': 'Monitor session'}), 0, reason: '"Mon" inside a word is not Monday');
    });
  });

  group('slotStartMinutes', () {
    test('24-hour and 12-hour times', () {
      expect(slotStartMinutes('18:00 To 19:00 (Monday)'), 18 * 60);
      expect(slotStartMinutes('8:30 PM - 9:30 PM'), 20 * 60 + 30);
      expect(slotStartMinutes('12:15 AM'), 15);
      expect(slotStartMinutes('no time'), -1);
    });
  });

  group('buildSchedule', () {
    test('merges centres and sorts by weekday, start time, then centre; unknown days last', () {
      final slots = buildSchedule([
        (
          centre: {'id': 2, 'text': 'Centre B'},
          rows: [
            {'id': 20, 'text': '18:00 To 19:00 (Monday)'},
            {'id': 21, 'text': 'Special class'},
          ]
        ),
        (
          centre: {'id': 1, 'text': 'Centre A'},
          rows: [
            {'id': 10, 'text': '20:00 To 21:00 (Monday)'},
            {'id': 11, 'text': '09:00 To 10:00 (Sunday)'},
            {'id': 12, 'text': '18:00 To 19:30 (Monday)'},
          ]
        ),
      ]);
      expect(slots.map((s) => s.id), [12, 20, 10, 11, 21]);
      expect(slots.first.centre, 'Centre A');
      expect(slots.first.centreId, 1);
      expect(slots.last.weekday, 0);
    });
  });
}

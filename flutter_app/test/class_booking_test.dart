// Class-booking rules. The server validates almost none of this, so these tests are the
// only thing standing between a student and a double booking on the wrong day.
import 'package:flutter_test/flutter_test.dart';
import 'package:dclix_app/services/class_booking.dart';

void main() {
  group('isoDate', () {
    test('formats local time, zero-padded', () {
      expect(isoDate(DateTime(2026, 9, 7)), '2026-09-07');
      expect(isoDate(DateTime(2026, 12, 25)), '2026-12-25');
    });

    test('does NOT shift the day for an evening class in a UTC+8 timezone', () {
      // toIso8601String() converts to UTC first, which rolls a 21:00 Malaysian class back
      // to the previous day and books it for the wrong date.
      final evening = DateTime(2026, 9, 7, 21, 30);
      expect(isoDate(evening), '2026-09-07');
    });
  });

  group('startTimeOf', () {
    test('pulls the start time out of a slot label', () {
      expect(startTimeOf('18:00 To 19:00 (Monday) - Normal training'), '18:00');
      expect(startTimeOf('8:00 To 9:30 (Sunday) - Normal training'), '8:00');
    });
    test('returns empty when the label has no time', () {
      expect(startTimeOf('Normal training'), '');
      expect(startTimeOf(null), '');
    });
  });

  group('weekdayIndexOf', () {
    test('maps names to Sunday=0', () {
      expect(weekdayIndexOf('Sunday'), 0);
      expect(weekdayIndexOf('monday'), 1);
      expect(weekdayIndexOf('  Saturday '), 6);
    });
    test('rejects anything that is not a weekday', () {
      expect(weekdayIndexOf('Someday'), -1);
      expect(weekdayIndexOf(null), -1);
    });
  });

  group('datesForDayOfWeek', () {
    test('lists every matching weekday from today onwards', () {
      // September 2026: the 7th is a Monday.
      final from = DateTime(2026, 9, 1);
      final mondays = datesForDayOfWeek('Monday', 9, 2026, from: from);
      expect(mondays.map(isoDate).toList(),
          ['2026-09-07', '2026-09-14', '2026-09-21', '2026-09-28']);
    });

    test('never offers a date in the past', () {
      final from = DateTime(2026, 9, 15);
      final mondays = datesForDayOfWeek('Monday', 9, 2026, from: from);
      expect(mondays.map(isoDate).toList(), ['2026-09-21', '2026-09-28']);
    });

    test('includes today when today is the slot weekday', () {
      final from = DateTime(2026, 9, 7, 6, 0);
      expect(datesForDayOfWeek('Monday', 9, 2026, from: from).map(isoDate).first,
          '2026-09-07');
    });

    test('stays inside the requested month', () {
      final dates = datesForDayOfWeek('Monday', 9, 2026, from: DateTime(2026, 1, 1));
      expect(dates.every((d) => d.month == 9 && d.year == 2026), isTrue);
    });

    test('an unknown weekday yields nothing rather than a wrong date', () {
      expect(datesForDayOfWeek('Noneday', 9, 2026, from: DateTime(2026, 9, 1)), isEmpty);
      expect(datesForDayOfWeek('Monday', 13, 2026, from: DateTime(2026, 9, 1)), isEmpty);
    });
  });

  group('duplicate protection', () {
    final bookings = [
      {'timeId': 55, 'trainingDate': '2026-09-07T18:00:00'},
      {'timeId': 55, 'trainingDate': '2026-09-14T18:00:00'},
      {'timeId': 99, 'trainingDate': '2026-09-21T18:00:00'},
    ];

    test('spots an existing booking for the same slot and date', () {
      expect(isAlreadyBooked(bookings, 55, '2026-09-07'), isTrue);
    });
    test('a different date or a different slot is not a duplicate', () {
      expect(isAlreadyBooked(bookings, 55, '2026-09-21'), isFalse);
      expect(isAlreadyBooked(bookings, 99, '2026-09-07'), isFalse);
    });
    test('survives malformed rows', () {
      expect(isAlreadyBooked([null, 'x', {}, {'timeId': null}], 55, '2026-09-07'), isFalse);
    });

    test('takenDates collects only that slot\'s dates', () {
      expect(takenDates(bookings, 55), {'2026-09-07', '2026-09-14'});
    });
  });

  group('preferredDate', () {
    final opts = [DateTime(2026, 9, 7), DateTime(2026, 9, 14), DateTime(2026, 9, 21)];

    test('skips dates already booked so the default is actionable', () {
      expect(preferredDate(opts, {'2026-09-07'}), '2026-09-14');
      expect(preferredDate(opts, {'2026-09-07', '2026-09-14'}), '2026-09-21');
    });
    test('falls back to the first option when everything is taken', () {
      expect(preferredDate(opts, {'2026-09-07', '2026-09-14', '2026-09-21'}), '2026-09-07');
    });
    test('no options -> null', () {
      expect(preferredDate([], {}), isNull);
    });
  });

  group('bookNowBody', () {
    test('builds the slot the server expects', () {
      final body = bookNowBody(
        tCenterId: 1945,
        instructorId: 12,
        studentId: 35842,
        timeId: 55,
        date: '2026-09-07',
        slotName: '18:00 To 19:00 (Monday) - Normal training',
        packageType: 'Monthly',
        centerName: 'SMK KK2',
      );

      expect(body['tCenterId'], 1945);
      expect(body['studentId'], 35842);
      expect(body['packageType'], 'Monthly');
      final slots = body['timeSlots'] as List;
      // An empty timeSlots is the one thing BookNow refuses.
      expect(slots, hasLength(1));
      expect(slots.first['timeId'], 55);
      expect(slots.first['trainingDate'], '2026-09-07T18:00:00');
      expect(slots.first['centerName'], 'SMK KK2');
    });

    test('a label with no time still produces a valid timestamp', () {
      final body = bookNowBody(
        tCenterId: 1, instructorId: 1, studentId: 1, timeId: 1,
        date: '2026-09-07', slotName: 'Normal training',
      );
      expect((body['timeSlots'] as List).first['trainingDate'], '2026-09-07T00:00:00');
    });
  });

  group('sortBookings', () {
    test('upcoming soonest-first, then past most-recent-first', () {
      final now = DateTime(2026, 9, 10);
      final sorted = sortBookings([
        {'timeId': 1, 'trainingDate': '2026-09-21T18:00:00'},
        {'timeId': 2, 'trainingDate': '2026-09-01T18:00:00'},
        {'timeId': 3, 'trainingDate': '2026-09-14T18:00:00'},
        {'timeId': 4, 'trainingDate': '2026-08-20T18:00:00'},
      ], now: now);

      expect(sorted.map((b) => b['timeId']).toList(), [3, 1, 2, 4]);
    });

    test('ignores rows with an unparseable date rather than throwing', () {
      final sorted = sortBookings([
        {'timeId': 1, 'trainingDate': 'not-a-date'},
        {'timeId': 2, 'trainingDate': '2026-09-14T18:00:00'},
      ], now: DateTime(2026, 9, 10));
      expect(sorted, hasLength(2));
    });
  });

  group('minutesOf', () {
    test('reads the timetable 12-hour and the slot-label 24-hour forms alike', () {
      expect(minutesOf('20:00'), 20 * 60);
      expect(minutesOf('8:00 PM'), 20 * 60);
      expect(minutesOf('8 PM'), 20 * 60);
      expect(minutesOf('9:30 am'), 9 * 60 + 30);
    });

    test('noon is 12:00 and midnight is 0:00', () {
      expect(minutesOf('12:00 PM'), 12 * 60);
      expect(minutesOf('12:30 AM'), 30);
    });

    test('no time at all is null, not midnight', () {
      expect(minutesOf(''), isNull);
      expect(minutesOf(null), isNull);
    });
  });

  group('today\'s classes', () {
    test('Thursday excludes Wednesday and includes its approved booking in time order', () {
      final thursday = DateTime(2026, 10, 1);
      final classes = scheduledClassesOn([
        {
          'dayOfWeek': 'Wednesday',
          'tTimeFrom': '10:00',
          'tTimeTo': '11:00',
          'tCenterName': 'Masjid Tengku Kelana Jaya',
        },
        {
          'dayOfWeek': 'Thursday',
          'tTimeFrom': '15:00',
          'tTimeTo': '16:00',
          'tCenterName': 'Kelab Golf Negara Subang',
        },
      ], [
        {
          'status': 'Confirmed',
          'trainingDate': '2026-10-01T17:00:00',
          'title': '17:00 To 18:00 (Thursday) - Booking class 1',
          'centerName': 'Booking class 1',
        },
      ], thursday);

      expect(classes.map((row) => row['tCenterName']).toList(),
          ['Kelab Golf Negara Subang', 'Booking class 1']);
      expect(classes.map((row) => row['tTimeFrom']).toList(), ['15:00', '17:00']);
    });

    test('Home features the next Thursday class instead of a stale weekday', () {
      final classes = scheduledClassesOn([
        {
          'dayOfWeek': 'Wednesday',
          'tTimeFrom': '10:00',
          'tTimeTo': '11:00',
          'tCenterName': 'Masjid Tengku Kelana Jaya',
        },
        {
          'dayOfWeek': 'Thursday',
          'tTimeFrom': '15:00',
          'tTimeTo': '16:00',
          'tCenterName': 'Kelab Golf Negara Subang',
        },
        {
          'dayOfWeek': 'Thursday',
          'tTimeFrom': '17:00',
          'tTimeTo': '18:00',
          'tCenterName': 'Booking class 1',
        },
      ], const [], DateTime(2026, 10, 1));

      final featured = featuredClassToday(classes, now: DateTime(2026, 10, 1, 13, 7));
      expect(featured?['tCenterName'], 'Kelab Golf Negara Subang');
      expect(featured?['tTimeFrom'], '15:00');
    });
  });
}

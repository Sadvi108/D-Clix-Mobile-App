// Shared cases from docs/specs/2026-09-15-progress-belt-grading.md.
import 'package:flutter_test/flutter_test.dart';

import 'package:dclix_app/utils/progress_stats.dart';

Map<String, dynamic> _row(String iso, {String type = 'Present', String? name, String? ic}) => {
      'recordedTime': iso,
      'attendanceType': type,
      if (name != null) 'studentName': name,
      if (ic != null) 'icNo': ic,
    };

void main() {
  const self = StudentIdentity(name: 'Alex Tan', ic: '900101-01-1234');

  group('scopeStudentRows', () {
    test('anonymous rows belong to the member whose token ran the report', () {
      final r = scopeStudentRows([_row('2026-09-01'), _row('2026-09-02')], self: self);
      expect(r.rows, hasLength(2));
      expect(r.unavailable, isFalse);
    });

    test('a row naming one other person is rejected for self', () {
      final r = scopeStudentRows([_row('2026-09-01', name: 'Ben Lee'), _row('2026-09-02')], self: self);
      expect(r.rows, hasLength(1));
      expect(r.rows.single['studentName'], isNull);
    });

    test('name match ignores case and spacing', () {
      final r = scopeStudentRows([_row('2026-09-01', name: '  alex   TAN ')], self: self);
      expect(r.rows, hasLength(1));
    });

    test('icNo matches even when the name differs', () {
      final r = scopeStudentRows([_row('2026-09-01', name: 'A. Tan', ic: '900101-01-1234')], self: self);
      expect(r.rows, hasLength(1));
    });

    test('a selected sibling needs a positive match and never sees anonymous rows', () {
      final r = scopeStudentRows(
        [_row('2026-09-01'), _row('2026-09-02', name: 'Alex Tan')],
        self: self,
        selected: const StudentIdentity(name: 'Mia Tan'),
      );
      expect(r.rows, isEmpty);
      expect(r.unavailable, isTrue);
    });

    test('a selected sibling keeps only their own named rows', () {
      final r = scopeStudentRows(
        [_row('2026-09-01', name: 'Mia Tan'), _row('2026-09-02', name: 'Alex Tan'), _row('2026-09-03')],
        self: self,
        selected: const StudentIdentity(name: 'mia tan'),
      );
      expect(r.rows, hasLength(1));
      expect(r.unavailable, isFalse);
    });

    test("selecting the token's own student is treated as self", () {
      final r = scopeStudentRows([_row('2026-09-01')], self: self, selected: const StudentIdentity(name: 'ALEX TAN'));
      expect(r.rows, hasLength(1));
      expect(r.unavailable, isFalse);
    });

    test('an empty list is empty, not unavailable', () {
      final r = scopeStudentRows(const [], self: self, selected: const StudentIdentity(name: 'Mia Tan'));
      expect(r.unavailable, isFalse);
    });
  });

  group('attendanceStatus', () {
    test('matches exact statuses only', () {
      expect(attendanceStatus(' Present '), AttendanceStatus.present);
      expect(attendanceStatus('ABSENT'), AttendanceStatus.absent);
      expect(attendanceStatus('Not present'), AttendanceStatus.other);
      expect(attendanceStatus('Leave'), AttendanceStatus.other);
      expect(attendanceStatus(null), AttendanceStatus.other);
    });
  });

  group('countPeriod', () {
    final today = DateTime(2026, 9, 16);

    test('counts inclusive days and excludes future and invalid dates', () {
      final c = countPeriod([
        _row('2026-09-16T21:00:00'),
        _row('2026-09-10T10:00:00', type: 'Absent'),
        _row('2026-08-18T00:00:00'), // first day of a 30-day period
        _row('2026-08-17T23:59:00'), // outside
        _row('2026-09-17T09:00:00'), // future
        _row('bad'),
        _row('2026-09-01T10:00:00', type: 'Leave'),
      ], from: DateTime(2026, 8, 18), today: today);
      expect(c.present, 2);
      expect(c.absent, 1);
      expect(c.other, 1);
      expect(c.rate, 67);
    });

    test('rate is null when there is no Present or Absent entry', () {
      final c = countPeriod([_row('2026-09-01T10:00:00', type: 'Leave')], from: DateTime(2026, 8, 1), today: today);
      expect(c.rate, isNull);
    });

    test('invalidDateCount counts unparsable dates only', () {
      expect(
          invalidDateCount([
            _row('bad'),
            {'attendanceType': 'Present'},
            _row('2026-09-01')
          ]),
          2);
    });
  });

  group('progressFetchStart', () {
    test('covers the whole inclusive 365-day period', () {
      final start = progressFetchStart(DateTime(2026, 9, 16));
      expect(start.isAfter(DateTime(2025, 9, 17)), isFalse);
    });
  });

  group('summarizeRecent', () {
    final now = DateTime(2026, 9, 16, 12); // a Wednesday
    final fetchStart = DateTime(2025, 9, 16);

    test('months are oldest first, cross the year and exclude future rows', () {
      final s = summarizeRecent([
        _row('2026-09-02T10:00:00'),
        _row('2026-09-09T10:00:00', type: 'Absent'),
        _row('2026-09-30T10:00:00'), // future
        _row('2026-04-01T10:00:00'),
        _row('2026-03-31T10:00:00'), // outside the window
      ], now, fetchStart: fetchStart);
      expect(s.months.map((m) => m.month.month), [4, 5, 6, 7, 8, 9]);
      expect(s.months.map((m) => m.present), [1, 0, 0, 0, 0, 1]);
      expect(s.months.last.absent, 1);
      expect(s.thisMonthPresent, 1);
      expect(s.lastMonthPresent, 0);

      final jan = summarizeRecent([_row('2025-12-05T10:00:00')], DateTime(2026, 1, 10), fetchStart: fetchStart);
      expect(jan.months.map((m) => '${m.month.year}-${m.month.month}'),
          ['2025-8', '2025-9', '2025-10', '2025-11', '2025-12', '2026-1']);
      expect(jan.lastMonthPresent, 1);
    });

    test('streak counts back from this week and an unfinished week does not break it', () {
      final s = summarizeRecent([
        _row('2026-09-08T10:00:00'),
        _row('2026-09-03T10:00:00'),
        _row('2026-08-20T10:00:00'), // gap before this
      ], now, fetchStart: fetchStart);
      expect(s.weekStreak, 2);
      expect(s.streakAtBoundary, isFalse);
    });

    test('an absence does not extend a streak', () {
      final s = summarizeRecent([
        _row('2026-09-14T10:00:00'),
        _row('2026-09-08T10:00:00', type: 'Absent'),
        _row('2026-09-01T10:00:00'),
      ], now, fetchStart: fetchStart);
      expect(s.weekStreak, 1);
    });

    test('a streak reaching the fetch boundary is flagged as "at least"', () {
      final s = summarizeRecent([
        _row('2026-09-14T10:00:00'),
        _row('2026-09-08T10:00:00'),
      ], now, fetchStart: DateTime(2026, 9, 9)); // mid-week: the week of 7 Sep is only partly fetched
      expect(s.weekStreak, 2);
      expect(s.streakAtBoundary, isTrue);
    });

    test('last present ignores absences and future rows', () {
      final s = summarizeRecent([
        _row('2026-09-15T10:00:00', type: 'Absent'),
        _row('2026-09-12T18:30:00'),
        _row('2026-09-20T10:00:00'),
      ], now, fetchStart: fetchStart);
      expect(s.lastPresent, DateTime(2026, 9, 12, 18, 30));
    });
  });

  group('beltAccent', () {
    test('one colour word gives an accent, sub-ranks included', () {
      expect(beltAccent('Grade 5 (Green 2)')?.name, 'Green');
      expect(beltAccent('Black Belt 2nd Dan')?.name, 'Black');
    });

    test('no colour or more than one colour gives no accent', () {
      expect(beltAccent('Grade 10'), isNull);
      expect(beltAccent('Blue / Brown tip'), isNull);
      expect(beltAccent(''), isNull);
    });
  });
}

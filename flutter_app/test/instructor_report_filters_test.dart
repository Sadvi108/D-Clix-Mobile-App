import 'package:dclix_app/utils/instructor_report_filters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('receipt payment mode', () {
    test('maps the Online UI label to the FPX server value', () {
      expect(receiptServerReportType('online'), 'FPX');
      expect(receiptServerReportType('Cash'), 'Cash');
      expect(receiptServerReportType('bank-in'), isNull);
    });

    test('recognises online and bank-in row labels client-side', () {
      expect(
          receiptMatchesMode({'paymentMethod': 'FPX - Monthly fee'}, 'online'),
          isTrue);
      expect(
          receiptMatchesMode(
              {'paymentMethod': 'Boost - Monthly fee'}, 'online'),
          isTrue);
      expect(
          receiptMatchesMode({'paymentMethod': 'Cash - Monthly fee'}, 'online'),
          isFalse);
      expect(
          receiptMatchesMode({'paymentMethod': 'Ibg - Monthly fee'}, 'bank-in'),
          isTrue);
    });
  });

  group('attendance training-time filter', () {
    const evening = '18:00 To 19:30 (Monday) - Normal training';

    test('prefers an explicit training-time id', () {
      expect(
          attendanceMatchesTrainingTime(
              {'tTimeId': 77, 'recordedTime': '2026-09-01T08:30:00'},
              selectedId: 77, selectedLabel: evening),
          isTrue);
      expect(
          attendanceMatchesTrainingTime(
              {'tTimeId': 12, 'recordedTime': '2026-09-01T18:30:00'},
              selectedId: 77, selectedLabel: evening),
          isFalse);
    });

    // 2026-08-31 is a Monday, the evening class's day.
    bool legacy(String recordedTime) => attendanceMatchesTrainingTime({'recordedTime': recordedTime},
        selectedId: 77, selectedLabel: evening);

    test('falls back to the recorded clock time for legacy rows', () {
      expect(legacy('2026-08-31T18:30:00'), isTrue);
      expect(legacy('2026-08-31T08:30:00'), isFalse);
    });

    test('counts a check-in up to 15 minutes either side of the class', () {
      expect(legacy('2026-08-31T17:50:00'), isTrue); // scanned in before the start
      expect(legacy('2026-08-31T19:40:00'), isTrue);
      expect(legacy('2026-08-31T17:40:00'), isFalse);
      expect(legacy('2026-08-31T19:50:00'), isFalse);
    });

    test('a Monday class does not take the same clock time on another day', () {
      expect(legacy('2026-09-01T18:30:00'), isFalse); // Tuesday
    });

    test('a timestamp with a zone is compared in local time', () {
      final local = DateTime(2026, 8, 31, 18, 30);
      expect(legacy(local.toUtc().toIso8601String()), isTrue);
    });

    test('does not treat a date-only midnight value as a midnight class', () {
      expect(
          attendanceMatchesTrainingTime({'recordedTime': '2026-09-01T00:00:00'},
              selectedId: 77, selectedLabel: '00:00 To 01:00'),
          isFalse);
    });
  });

  test('date-only attendance values do not display a false 12:00 AM', () {
    expect(formatAttendanceRecordedTime('2026-09-01T00:00:00'), '01 Sep 2026');
    expect(formatAttendanceRecordedTime('2026-09-01T18:30:00'),
        '01 Sep 2026 18:30');
  });

  test('builds SK Jerantut student options from its attendance rows', () {
    final options = attendanceStudentOptions([
      {
        'studentId': 2,
        'name': 'Zara',
        'icNo': 'Z2',
        'trainingCenter': 'SK Jerantut'
      },
      {
        'studentId': 1,
        'name': 'Aisyah',
        'icNo': 'A1',
        'trainingCenter': 'SK Jerantut'
      },
      {
        'studentId': 1,
        'name': 'Aisyah',
        'icNo': 'A1',
        'trainingCenter': 'SK Jerantut'
      },
      {'studentId': 3, 'name': 'Other', 'trainingCenter': 'KCP'},
    ], '  sk jerantut ');

    expect(options, [
      {'id': 1, 'text': 'Aisyah', 'value': 'A1'},
      {'id': 2, 'text': 'Zara', 'value': 'Z2'},
    ]);
  });
}

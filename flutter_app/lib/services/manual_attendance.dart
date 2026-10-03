import 'api_service.dart';
import 'response_utils.dart';

/// One person on a class list: `AttendancePersonViewModel`.
typedef AttendancePerson = ({int id, String name, bool alreadyMarked});

/// Instructor manual attendance — the portal's Mark Attendance.
///
/// A student who missed their own class and trained with another section is marked present
/// afterwards: the instructor picks students or instructors, the date, the training centre and
/// the class time, then ticks people. These routes are deployed on UAT only, so
/// [ApiService.isBoostPath] sends them there.
class ManualAttendance {
  /// `type` for People and ManualAdd: the portal's Attendance Type radio.
  static const student = 'Student';
  static const instructor = 'Instructor';

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';

  static List<Map<String, dynamic>> _rows(dynamic resp) => [
        for (final r in findRecordList(resp))
          if (r is Map) Map<String, dynamic>.from(r)
      ];

  /// Centres this instructor may mark: `{id, value, text}`.
  static Future<List<Map<String, dynamic>>> centres() async => _rows(await ApiService.get('/Attendance/Centres'));

  /// Classes held at [centreId] on [date]: `{id, value, text}`.
  static Future<List<Map<String, dynamic>>> trainingTimes(int centreId, DateTime date) async {
    final q = Uri(queryParameters: {'centreId': '$centreId', 'date': _day(date)}).query;
    return _rows(await ApiService.get('/Attendance/TrainingTimes?$q'));
  }

  /// The class list, with who already has attendance for that class on [date].
  static Future<List<AttendancePerson>> people({
    required String type,
    required int centreId,
    required int timeId,
    required DateTime date,
  }) async {
    final q =
        Uri(queryParameters: {'type': type, 'centreId': '$centreId', 'timeId': '$timeId', 'date': _day(date)}).query;
    return [
      for (final r in _rows(await ApiService.get('/Attendance/People?$q')))
        if (int.tryParse('${r['id'] ?? ''}') case final id?)
          (id: id, name: '${r['name'] ?? ''}'.trim(), alreadyMarked: r['alreadyMarked'] == true),
    ];
  }

  /// Marks [personIds] present for the class. The server skips anyone already marked and
  /// lists them in `alreadyMarkedIds`.
  static Future<({int added, List<int> alreadyMarkedIds})> add({
    required String type,
    required int centreId,
    required int timeId,
    required DateTime date,
    required List<int> personIds,
  }) async {
    final data = unwrapData(await ApiService.post('/Attendance/ManualAdd', {
      'type': type,
      'centreId': centreId,
      'timeId': timeId,
      'date': _day(date),
      'personIds': personIds,
    }));
    final m = data is Map ? data : const {};
    return (
      added: int.tryParse('${m['added'] ?? ''}') ?? 0,
      alreadyMarkedIds: [
        for (final v in m['alreadyMarkedIds'] is List ? m['alreadyMarkedIds'] as List : const [])
          if (int.tryParse('$v') case final id?) id,
      ],
    );
  }
}

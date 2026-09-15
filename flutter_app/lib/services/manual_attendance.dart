import 'package:flutter/foundation.dart' show visibleForTesting;

import 'api_service.dart';
import 'response_utils.dart';

/// One student's outcome from a manual marking request.
class MarkResult {
  final bool ok;
  final String message;
  const MarkResult(this.ok, this.message);
}

/// Instructor register marking.
///
/// The deployed Club.Api cannot do this: `/Attendance/Add` only records the token holder
/// (live probe 2026-08-12). This is the PROPOSED contract from
/// docs/specs/2026-09-15-manual-attendance.md. The screen checks the server's route table and
/// switches the register on only once the route is deployed, so no app update is needed then.
class ManualAttendance {
  static const route = '/Attendance/MarkByInstructor';

  /// Present, as `attendanceTypeId` on `/Reports/Attendance` rows. Confirm with the backend
  /// when the route ships.
  static const presentTypeId = 1;

  static bool? _available;

  @visibleForTesting
  static void resetCache() => _available = null;

  /// Whether the marking route is in the server's Swagger route table. Cached once known;
  /// a failed check throws and is retried next time.
  static Future<bool> isAvailable() async {
    final known = _available;
    if (known != null) return known;
    final doc = await ApiService.get('/swagger/v1/swagger.json');
    final paths = doc is Map ? doc['paths'] : null;
    return _available = paths is Map && paths.containsKey(route);
  }

  /// Marks [studentIds] present for one class. Returns a result for every requested student;
  /// one the server does not report on is unconfirmed, never assumed marked.
  static Future<Map<int, MarkResult>> markPresent({
    required int tCenterId,
    required int tTimeId,
    required DateTime date,
    required List<int> studentIds,
  }) async {
    final day = '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final response = await ApiService.post(route, {
      'tCenterId': tCenterId,
      'tTimeId': tTimeId,
      'attendanceDate': day,
      'entries': [
        for (final id in studentIds) {'studentId': id, 'attendanceTypeId': presentTypeId},
      ],
    });
    final reported = <int, MarkResult>{};
    for (final row in findRecordList(response).whereType<Map>()) {
      final id = int.tryParse('${row['studentId'] ?? ''}');
      if (id == null) continue;
      final ok = '${row['status']}' == '0';
      final message = '${row['message'] ?? ''}'.trim();
      reported[id] = MarkResult(ok, message.isNotEmpty ? message : (ok ? 'Marked present' : 'Not marked'));
    }
    return {
      for (final id in studentIds)
        id: reported[id] ?? const MarkResult(false, 'Result not confirmed by the server. Check before marking again.'),
    };
  }
}

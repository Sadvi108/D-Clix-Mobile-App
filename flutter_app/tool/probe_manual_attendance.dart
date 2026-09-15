// Live probe: can an INSTRUCTOR token record attendance for a student, and is there a
// roster per training time?
//
// Lives in tool/, not test/, so `flutter test` never runs it. Nothing is committed with
// credentials; they come from --dart-define at run time.
//
// READ-ONLY by default (login + roster + class times). Prints field NAMES and code SHAPES.
// The only names printed are centre names and students named "test", to pick PROBE_TC and
// PROBE_STUDENT.
//
//   flutter test tool/probe_manual_attendance.dart \
//     --dart-define=LIVE_USER=<instructor login> --dart-define=LIVE_PASS=<password> \
//     --dart-define=PROBE_TC=<training centre id> --dart-define=PROBE_STUDENT=<TEST student id>
//
// Add --dart-define=PROBE_WRITE=true to try the untested /Attendance/Add combinations.
// A successful attempt creates a REAL attendance record for PROBE_STUDENT and there is no
// undo route, so use a test student only. The probe stops at the first success.
//
// Background: docs/ARCHITECTURE.md (probe of 2026-08-12) already ruled out, under an
// instructor token with attendanceType 2: ST- code with no class time, bare id with a class
// time, registration code with a class time.
import 'package:flutter_test/flutter_test.dart';

import 'package:dclix_app/services/api.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/attendance_outcome.dart';
import 'package:dclix_app/services/rn_api.dart';
import 'package:dclix_app/utils/qr_content.dart';

const _user = String.fromEnvironment('LIVE_USER');
const _pass = String.fromEnvironment('LIVE_PASS');
const _tc = int.fromEnvironment('PROBE_TC');
const _student = int.fromEnvironment('PROBE_STUDENT');
const _write = bool.fromEnvironment('PROBE_WRITE');

/// "RTT/KCP/2025/00212" -> "AAA/AAA/9999/99999": the format without the value.
String _shape(Object? v) => '${v ?? ''}'.replaceAll(RegExp(r'[A-Za-z]'), 'A').replaceAll(RegExp(r'\d'), '9');

void _say(String s) => print('[probe] $s'); // ignore: avoid_print

void main() {
  final configured = _user.isNotEmpty && _pass.isNotEmpty;

  test('instructor manual attendance probe', () async {
    final auth = await ApiService.post('/Account/Authenticate', {
      'userType': 2,
      'username': _user,
      'password': _pass,
      'accessMethod': 0,
      'branchId': 0,
    });
    final data = auth is Map ? auth['data'] : null;
    final token = data is Map ? data['accessToken'] : null;
    expect(token, isA<String>(), reason: 'instructor login failed');
    ApiService.setToken(token as String);
    _say('login ok; auth fields: ${(data as Map).keys.toList()..sort()}');
    for (final k in const ['userType', 'isAllowAttendance']) {
      if (data.containsKey(k)) _say('$k = ${data[k]}');
    }

    if (_tc <= 0) {
      final centres = await RnApi.dropdownListByType(3);
      _say('no PROBE_TC given. Your centres:');
      for (final c in centres) {
        _say('  PROBE_TC=${c['id']}  ${c['text']}');
      }
      return;
    }

    final roster = await RnApi.studentListByTcId(_tc);
    if (_student <= 0) {
      final tests = roster.where((r) => '${r['text']}'.toLowerCase().contains('test')).toList();
      _say('no PROBE_STUDENT given. Roster rows: ${roster.length}. Students named "test" (use one of these only):');
      for (final r in tests) {
        _say('  PROBE_STUDENT=${r['id']}  ${r['text']}');
      }
      if (tests.isEmpty) _say('  none; ask the club to add a TEST student to this centre first.');
      return;
    }
    _say('roster rows: ${roster.length}; fields: ${roster.isEmpty ? [] : (roster.first.keys.toList()..sort())}');
    final row = roster.where((r) => '${r['id']}' == '$_student').firstOrNull;
    _say('PROBE_STUDENT in roster: ${row != null}');
    if (row != null) _say('roster value shape: ${_shape(row['value'])}');

    final times = await RnApi.trainingTimeByTcId(_tc);
    _say('class times: ${times.length}');
    final tTimeId = times.isEmpty ? null : RnApi.number(times.first['id']).toInt();

    // Read-only: is there a roster per training time? /Reports/StudentDetails accepts
    // tCenterId and tTimeId; check whether an instructor token gets rows and whether the
    // filters change them. Counts and field names only.
    Future<List<Map<String, dynamic>>> details(Map<String, dynamic> body) async {
      try {
        return await RnApi.studentDetails(body);
      } catch (e) {
        _say('  StudentDetails $body failed: $e');
        return const [];
      }
    }

    final unfiltered = await details({});
    final byCentre = await details({'tCenterId': _tc});
    final byTime = tTimeId == null ? const <Map<String, dynamic>>[] : await details({'tCenterId': _tc, 'tTimeId': tTimeId});
    _say('StudentDetails rows: no filter ${unfiltered.length}, centre ${byCentre.length}, centre+time ${byTime.length}');
    final sample = [...byTime, ...byCentre, ...unfiltered].firstOrNull;
    if (sample != null) _say('StudentDetails fields: ${sample.keys.toList()..sort()}');

    if (!_write) {
      _say('read-only run finished. Re-run with PROBE_WRITE=true to try the write combinations.');
      return;
    }
    expect(row, isNotNull, reason: 'PROBE_STUDENT must be in the centre roster before writing');

    final st = QrContent.student(_student);
    final attempts = <(String, Map<String, dynamic>)>[
      ('ST code + class time, type 2', {'qrCode': st, 'attendanceType': 2, 'tTimeId': tTimeId}),
      ('ST code + class time, type 1', {'qrCode': st, 'attendanceType': 1, 'tTimeId': tTimeId}),
      ('ST code + class time, type 3', {'qrCode': st, 'attendanceType': 3, 'tTimeId': tTimeId}),
      ('ST code + class time, type 0', {'qrCode': st, 'attendanceType': 0, 'tTimeId': tTimeId}),
      ('roster value + class time, type 2', {'qrCode': '${row!['value']}', 'attendanceType': 2, 'tTimeId': tTimeId}),
    ];
    for (final (label, body) in attempts) {
      final outcome = AttendanceOutcome.parse(await Api.attendanceAdd(body));
      _say('$label -> status ${outcome.status} "${outcome.message ?? ''}"'
          '${outcome.sessions.isEmpty ? '' : ' (${outcome.sessions.length} class times offered)'}');
      if (outcome.success) {
        _say('SUCCESS with: $label. Stopping. A real record now exists for PROBE_STUDENT.');
        return;
      }
    }
    _say('no combination recorded attendance.');
  }, skip: configured ? null : 'needs LIVE_USER and LIVE_PASS (instructor login)', timeout: const Timeout(Duration(minutes: 2)));
}

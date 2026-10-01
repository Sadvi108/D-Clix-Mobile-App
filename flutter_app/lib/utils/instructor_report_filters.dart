// Normalisation and client-side fallbacks for instructor reports whose
// server-side filters are inconsistent across Club.Api deployments.

import '../services/class_booking.dart';

String _norm(Object? value) =>
    '${value ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// `/Reports/Receipts` calls online gateway payments `FPX` in `reportType`,
/// even though the UI and receipt rows commonly call them Online or Boost.
String? receiptServerReportType(String mode) => switch (_norm(mode)) {
      'cash' => 'Cash',
      'online' || 'fpx' => 'FPX',
      _ => null,
    };

/// Defensive client-side mode matching. This keeps the filter useful when a
/// deployment ignores `reportType`, and supports the row labels used by older
/// records (`Ibg` for direct bank-in and `Boost` for online payments).
bool receiptMatchesMode(Map row, String mode) {
  final wanted = _norm(mode);
  if (wanted.isEmpty) return true;
  final method = _norm(row['paymentMethod'] ??
      row['paymentMode'] ??
      row['mode'] ??
      row['reportType']);
  if (wanted == 'cash') return method.startsWith('cash');
  if (wanted == 'online' || wanted == 'fpx') {
    return const ['online', 'fpx', 'boost', 'card', 'e-wallet', 'ewallet']
        .any(method.contains);
  }
  if (wanted == 'bank-in' || wanted == 'bank in' || wanted == 'ibg') {
    return const ['bank-in', 'bank in', 'direct bank', 'ibg']
        .any(method.contains);
  }
  return method == wanted || method.startsWith('$wanted -');
}

/// Show a date-only value when the API has supplied a date at midnight. A
/// midnight timestamp is the backend's "no time recorded" sentinel and should
/// not be presented as an actual 12:00 AM attendance time.
String formatAttendanceRecordedTime(Object? value) {
  final raw = '${value ?? ''}'.trim();
  if (raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final day = date.day.toString().padLeft(2, '0');
  final formattedDate = '$day ${months[date.month - 1]} ${date.year}';
  if (date.hour == 0 && date.minute == 0 && date.second == 0) {
    return formattedDate;
  }
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$formattedDate $hour:$minute';
}

int? _clockMinutes(String value) {
  final match =
      RegExp(r'(\d{1,2}):(\d{2})\s*([ap]\.?m\.?)?', caseSensitive: false)
          .firstMatch(value);
  if (match == null) return null;
  var hour = int.tryParse(match.group(1)!) ?? -1;
  final minute = int.tryParse(match.group(2)!) ?? -1;
  if (hour < 0 || minute < 0 || minute > 59) return null;
  final meridiem = match.group(3)?.toLowerCase();
  if (meridiem != null) {
    if (hour == 12) hour = 0;
    if (meridiem.startsWith('p')) hour += 12;
  }
  if (hour > 23) return null;
  return hour * 60 + minute;
}

({int start, int end})? _timeWindow(String label) {
  final matches =
      RegExp(r'\d{1,2}:\d{2}\s*(?:[ap]\.?m\.?)?', caseSensitive: false)
          .allMatches(label)
          .toList();
  if (matches.isEmpty) return null;
  final start = _clockMinutes(matches.first.group(0)!);
  final end = matches.length > 1 ? _clockMinutes(matches[1].group(0)!) : start;
  if (start == null || end == null) return null;
  return (start: start, end: end);
}

/// Members scan in before a class starts and sometimes after it ends; minutes either side.
const _checkInGrace = 15;

/// 0 = Sunday … 6 = Saturday from a label like `18:00 To 19:30 (Monday)`, or -1 if none.
int _labelWeekday(String label) {
  final m = RegExp(r'\b(sun|mon|tues|wednes|thurs|fri|satur)day\b', caseSensitive: false).firstMatch(label);
  return m == null ? -1 : weekdayIndexOf(m.group(0));
}

/// Match an attendance row to a selected training time. Prefer an explicit
/// time id/name when a newer API includes one; older rows expose only
/// `recordedTime`, so fall back to the selected class's clock interval.
bool attendanceMatchesTrainingTime(
  Map row, {
  required Object? selectedId,
  required String selectedLabel,
}) {
  if (selectedId == null || '$selectedId'.trim().isEmpty) return true;

  for (final key in const ['tTimeId', 'trainingTimeId', 'timeId']) {
    final actual = row[key];
    if (actual != null && '$actual'.trim().isNotEmpty) {
      return '$actual'.trim() == '$selectedId'.trim();
    }
  }

  for (final key in const [
    'trainingTime',
    'trainingTimeName',
    'tTime',
    'sessionTime',
    'timeName'
  ]) {
    final actual = _norm(row[key]);
    if (actual.isNotEmpty) {
      final wanted = _norm(selectedLabel);
      return actual == wanted ||
          actual.contains(wanted) ||
          wanted.contains(actual);
    }
  }

  final parsed = DateTime.tryParse('${row['recordedTime'] ?? ''}');
  final window = _timeWindow(selectedLabel);
  if (parsed == null || window == null) return false;
  // Midnight is "date only" in this API, not evidence of a midnight class.
  if (parsed.hour == 0 && parsed.minute == 0 && parsed.second == 0) {
    return false;
  }
  // A zoned value (`Z`/offset) is read in the phone's time; a naive one is taken as already local.
  // ponytail: whether the backend's naive times are UTC is unconfirmed; if they are, convert here.
  final recorded = parsed.toLocal();
  final day = _labelWeekday(selectedLabel);
  if (day >= 0 && recorded.weekday % 7 != day) return false;
  final minute = recorded.hour * 60 + recorded.minute;
  final start = (window.start - _checkInGrace) % 1440;
  final end = (window.end + _checkInGrace) % 1440;
  if (start <= end) {
    return minute >= start && minute <= end;
  }
  // A session such as 23:30–00:30 crosses midnight.
  return minute >= start || minute <= end;
}

bool attendanceMatchesCentre(Map row, String centreName) {
  final wanted = _norm(centreName);
  if (wanted.isEmpty) return true;
  for (final key in const [
    'trainingCenter',
    'tCenterName',
    'tcName',
    'centerName',
    'centername'
  ]) {
    final actual = _norm(row[key]);
    if (actual.isNotEmpty &&
        (actual == wanted || actual.contains(wanted) || wanted.contains(actual))) {
      return true;
    }
  }
  return false;
}

bool attendanceMatchesStudent(Map row, Map? selectedStudent) {
  if (selectedStudent == null) return true;
  final wantedId = _norm(selectedStudent['id']);
  // `id` on an attendance row is the attendance record id, not the student.
  for (final key in const ['studentId', 'sourceKeyId']) {
    final actual = _norm(row[key]);
    if (wantedId.isNotEmpty && actual.isNotEmpty && actual == wantedId) {
      return true;
    }
  }
  final wantedIc = _norm(selectedStudent['value'] ?? selectedStudent['icNo']);
  final actualIc = _norm(row['icNo'] ?? row['registrationNo']);
  if (wantedIc.isNotEmpty && actualIc.isNotEmpty && actualIc == wantedIc) {
    return true;
  }
  final wantedName = _norm(selectedStudent['text'] ?? selectedStudent['name']);
  final actualName = _norm(row['name'] ?? row['studentName']);
  return wantedName.isNotEmpty && actualName == wantedName;
}

/// Build student-picker rows from attendance records when the centre roster
/// endpoint returns no rows for a centre (observed for SK Jerantut).
List<Map<String, dynamic>> attendanceStudentOptions(
    Iterable<Map<String, dynamic>> rows, String centreName) {
  final found = <String, Map<String, dynamic>>{};
  for (final row in rows) {
    if (!attendanceMatchesCentre(row, centreName)) continue;
    final id = row['studentId'] ?? row['sourceKeyId'];
    final name = '${row['name'] ?? row['studentName'] ?? ''}'.trim();
    final ic = '${row['icNo'] ?? row['registrationNo'] ?? ''}'.trim();
    if (name.isEmpty && ic.isEmpty) continue;
    final key = id != null && '$id'.trim().isNotEmpty
        ? 'id:$id'
        : ic.isNotEmpty
            ? 'ic:${_norm(ic)}'
            : 'name:${_norm(name)}';
    found.putIfAbsent(
        key,
        () => <String, dynamic>{
              'id': id ?? key,
              'text': name.isEmpty ? ic : name,
              'value': ic,
            });
  }
  final result = found.values.toList()
    ..sort((a, b) => _norm(a['text']).compareTo(_norm(b['text'])));
  return result;
}

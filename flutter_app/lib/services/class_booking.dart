// Class-booking rules.
//
// Contract probed live on UAT (see docs/ARCHITECTURE.md). The server validates almost
// nothing here, so the rules below are the app's responsibility, not the backend's:
//
//  - `TrainingTimeWithDateAndInstructor/{month}/{year}/...` returns a WEEKLY timetable. The
//    month and year in the path change nothing — July, August and September return the
//    identical rows. The calendar date is the app's job.
//  - `classLimit` is the class's configured capacity, NOT seats remaining and not an
//    availability flag. A slot with `classLimit: 0` books fine and the value never moves,
//    so it must never be used to disable a slot.
//  - `BookNow` accepts a duplicate of an existing booking, and accepts a trainingDate whose
//    weekday does not match the slot (a Friday slot booked on a Tuesday returned 200). Only
//    an empty `timeSlots` is refused. So the duplicate check lives here.

const _dayNames = [
  'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
];

String _pad(int n) => n < 10 ? '0$n' : '$n';

/// `yyyy-MM-dd` in LOCAL time.
///
/// Deliberately not `toIso8601String().substring(0,10)`: that converts to UTC first, which
/// rolls the date back a day for anyone east of GMT — Malaysia is UTC+8, so an evening class
/// would be booked for the day before.
String isoDate(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

/// The start time inside a slot label like `"18:00 To 19:00 (Monday) - Normal training"`.
/// Empty when the label carries no time.
String startTimeOf(String? slotName) {
  final m = RegExp(r'(\d{1,2}:\d{2})').firstMatch(slotName ?? '');
  return m?.group(1) ?? '';
}

/// 0 = Sunday … 6 = Saturday, or -1 when the name is not a weekday.
int weekdayIndexOf(String? dayName) => _dayNames
    .indexWhere((d) => d.toLowerCase() == (dayName ?? '').trim().toLowerCase());

/// Every date in the given month that falls on the slot's weekday, from [from] onwards.
///
/// The student picks one of these rather than having a date computed behind their back.
List<DateTime> datesForDayOfWeek(
  String? dayName,
  int month,
  int year, {
  DateTime? from,
}) {
  final target = weekdayIndexOf(dayName);
  if (target < 0 || month < 1 || month > 12) return const [];

  final now = from ?? DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final out = <DateTime>[];
  var d = DateTime(year, month, 1);
  while (d.month == month && d.year == year) {
    // Dart: Monday = 1 … Sunday = 7. The slot names use Sunday = 0.
    final dow = d.weekday == DateTime.sunday ? 0 : d.weekday;
    if (dow == target && !d.isBefore(today)) out.add(d);
    d = DateTime(year, month, d.day + 1);
  }
  return out;
}

/// Has this student already booked [timeId] on [date] (`yyyy-MM-dd`)?
///
/// BookNow will happily create a second identical booking, so this is the only thing
/// stopping a double booking.
bool isAlreadyBooked(List<dynamic> bookings, int timeId, String date) {
  for (final b in bookings) {
    if (b is! Map) continue;
    final id = b['timeId'];
    final tid = id is int ? id : int.tryParse('$id');
    if (tid != timeId) continue;
    final raw = (b['trainingDate'] ?? '').toString();
    if (raw.length >= 10 && raw.substring(0, 10) == date) return true;
  }
  return false;
}

/// The dates in [options] this student has already booked for [timeId].
Set<String> takenDates(List<dynamic> bookings, int timeId) {
  final taken = <String>{};
  for (final b in bookings) {
    if (b is! Map) continue;
    final id = b['timeId'];
    final tid = id is int ? id : int.tryParse('$id');
    if (tid != timeId) continue;
    final raw = (b['trainingDate'] ?? '').toString();
    if (raw.length >= 10) taken.add(raw.substring(0, 10));
  }
  return taken;
}

/// First date the student has NOT already booked, so the default choice is actionable
/// rather than immediately warning about a duplicate. Falls back to the first option.
String? preferredDate(List<DateTime> options, Set<String> taken) {
  if (options.isEmpty) return null;
  for (final d in options) {
    final iso = isoDate(d);
    if (!taken.contains(iso)) return iso;
  }
  return isoDate(options.first);
}

/// The old app mapped `PackageInfo.packageType` to an id: "Package" → 1,
/// "Session" → 2, anything else (Monthly and friends) → 3. Only 1 and 2 carry a
/// class quota (`BookClassPageViewModel.cs:155,488`).
int packageTypeId(String? packageType) {
  final n = (packageType ?? '').trim().toLowerCase();
  if (n == 'package') return 1;
  if (n == 'session') return 2;
  return 3;
}

/// The class quota on a PackageInfo reply, or null when it carries no quota
/// field at all.
///
/// Absent is not zero. Zero means unlimited (the old UI showed "NA"), so
/// reading a missing field as 0 turns a paid, quota-limited package into an
/// unlimited one. Parity review round 4.
int? packageQuota(Map<String, dynamic>? pkg) {
  if (pkg == null) return null;
  for (final k in const ['noOfCLasses', 'noOfClasses', 'noOfClass']) {
    final v = pkg[k];
    if (v == null) continue;
    final n = v is num ? v.toInt() : int.tryParse(v.toString().trim());
    if (n != null) return n;
  }
  return null;
}

/// Whether a PackageInfo reply is complete enough to judge an entitlement.
///
/// An empty object — or one the server answered without a `packageType` — is
/// NOT proof of an unlimited membership. Neither is a quota-limited package
/// that never states its quota. Treating either as "Monthly, unlimited" lets a
/// student book past their package, so an unusable reply fails closed instead.
/// Parity review round 4.
bool isUsablePackage(Map<String, dynamic>? pkg) {
  if (pkg == null) return false;
  final type = (pkg['packageType'] ?? '').toString().trim();
  if (type.isEmpty) return false;
  final id = packageTypeId(type);
  return (id != 1 && id != 2) || packageQuota(pkg) != null;
}

/// Whether this member may book another class this month.
///
/// Mirrors the old entitlement rules:
///  - only package types 1 and 2 are quota-limited;
///  - `noOfClasses == 0` means unlimited (the old UI showed "NA");
///  - a quota-limited member with no assigned package (`sessionId == 0`) cannot
///    book at all (`BookClassPageViewModel.cs:659`);
///  - otherwise remaining = quota − already booked, and 0 blocks booking.
({bool blocked, int? remaining, String? reason}) bookingAllowance({
  required int typeId,
  required int sessionId,
  required int noOfClasses,
  required int alreadyBooked,
}) {
  if (typeId != 1 && typeId != 2) return (blocked: false, remaining: null, reason: null);
  if (sessionId == 0) {
    return (
      blocked: true,
      remaining: null,
      reason: 'No package is assigned to this student yet. Your academy can set one up.',
    );
  }
  if (noOfClasses <= 0) return (blocked: false, remaining: null, reason: null);
  final left = noOfClasses - alreadyBooked;
  if (left <= 0) {
    return (
      blocked: true,
      remaining: 0,
      reason: 'All $noOfClasses classes in this package are booked for this month.',
    );
  }
  return (blocked: false, remaining: left, reason: null);
}

/// Body for `POST /ClassBooking/BookNow` — a `BookClassViewModel`.
Map<String, dynamic> bookNowBody({
  required int tCenterId,
  required int instructorId,
  required int studentId,
  required int timeId,
  required String date, // yyyy-MM-dd
  required String slotName,
  String? packageType,
  int sessionId = 0,
  String centerName = '',
  String instructorName = '',
  String remarks = 'Booked via app',
}) {
  final start = startTimeOf(slotName);
  return {
    'id': 0,
    'tCenterId': tCenterId,
    'instructorId': instructorId,
    'studentId': studentId,
    'packageType': packageType,
    'sessionId': sessionId,
    'remarks': remarks,
    // An empty timeSlots is the ONE thing the server rejects ("Invalid Request").
    'timeSlots': [
      {
        'bookingId': 0,
        'timeId': timeId,
        'trainingDate': '${date}T${start.isEmpty ? '00:00' : start}:00',
        'status': '',
        'title': '',
        'name': slotName,
        'centerName': centerName,
        'instructorName': instructorName,
      }
    ],
  };
}

/// A booking the club has confirmed. Book a Class shows these green; anything else is still
/// pending or was refused.
bool isApprovedBooking(Map b) => RegExp('confirm|approv', caseSensitive: false).hasMatch('${b['status'] ?? ''}');

/// Minutes past midnight for "20:00", "8:00 PM" or "8 PM" — the timetable speaks 12-hour,
/// slot labels 24-hour. Null when there's no time in it.
int? minutesOf(String? time) {
  final m = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*([AaPp][Mm])?').firstMatch(time ?? '');
  if (m == null) return null;
  var hour = int.parse(m[1]!);
  final meridiem = m[3]?.toLowerCase();
  if (meridiem != null) hour = hour % 12 + (meridiem == 'pm' ? 12 : 0);
  return hour * 60 + int.parse(m[2] ?? '0');
}

/// Approved bookings on [day], shaped like the Schedule's timetable rows. The times come from
/// the slot label in `title` ("12:00 To 16:00 (Monday) - Normal training").
///
/// Book a Class defaults to the member's own instructor, so booking your regular class is the
/// common case — one already in [timetable] at the same centre and start time is left out.
List<Map<String, dynamic>> bookedClassesOn(List<dynamic> bookings, DateTime day, {List<Map> timetable = const []}) {
  final date = isoDate(day);
  bool listed(int? start, Object? centre) =>
      start != null &&
      timetable.any((r) =>
          minutesOf('${r['tTimeFrom'] ?? ''}') == start &&
          '${r['tCenterName'] ?? ''}'.trim().toLowerCase() == '${centre ?? ''}'.trim().toLowerCase());

  final out = <Map<String, dynamic>>[];
  for (final b in bookings.whereType<Map>()) {
    if (!isApprovedBooking(b) || !'${b['trainingDate'] ?? ''}'.startsWith(date)) continue;
    final times = RegExp(r'\d{1,2}:\d{2}').allMatches('${b['title'] ?? ''}').map((m) => m[0]!).toList();
    if (listed(minutesOf(times.firstOrNull), b['centerName'])) continue;
    out.add({
      'tTimeFrom': times.isNotEmpty ? times[0] : '',
      'tTimeTo': times.length > 1 ? times[1] : '',
      'tCenterName': b['centerName'],
      'instructorName': b['instructorName'],
    });
  }
  return out;
}

/// Bookings ordered for display: upcoming soonest-first, then past most-recent-first.
List<Map<String, dynamic>> sortBookings(List<dynamic> bookings, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);

  DateTime? parse(dynamic v) => DateTime.tryParse((v ?? '').toString());

  final rows = bookings.whereType<Map>().map((b) {
    final t = parse(b['trainingDate']);
    return {
      'row': Map<String, dynamic>.from(b),
      'time': t,
      'past': t != null && t.isBefore(today),
    };
  }).toList();

  rows.sort((a, z) {
    final ap = a['past'] as bool, zp = z['past'] as bool;
    if (ap != zp) return ap ? 1 : -1;
    final at = a['time'] as DateTime?, zt = z['time'] as DateTime?;
    if (at == null || zt == null) return 0;
    return ap ? zt.compareTo(at) : at.compareTo(zt);
  });

  return rows.map((r) => r['row'] as Map<String, dynamic>).toList();
}

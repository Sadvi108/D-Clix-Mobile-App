// Calculations for Progress Report and Belt / Rank.
// Spec: docs/specs/2026-09-15-progress-belt-grading.md (shared with the Codex-built repo).
import 'dart:ui' show Color;

typedef Belt = ({String name, Color color});

/// Colours used only to tint the Belt / Rank screen. Not a progression: the API has no grade
/// list, and clubs use sub-ranks ("Green 2") and their own orders.
const List<Belt> kBeltColours = [
  (name: 'White', color: Color(0xFFE5E7EB)),
  (name: 'Yellow', color: Color(0xFFFDE68A)),
  (name: 'Orange', color: Color(0xFFFED7AA)),
  (name: 'Green', color: Color(0xFF86EFAC)),
  (name: 'Blue', color: Color(0xFF93C5FD)),
  (name: 'Purple', color: Color(0xFFC4B5FD)),
  (name: 'Brown', color: Color(0xFFD6D3D1)),
  (name: 'Red', color: Color(0xFFFCA5A5)),
  (name: 'Black', color: Color(0xFF1F2937)),
];

/// The belt colour named in [grade], only when exactly one colour word appears.
Belt? beltAccent(String grade) {
  final hits = kBeltColours.where((b) => RegExp('\\b${b.name}\\b', caseSensitive: false).hasMatch(grade)).toList();
  return hits.length == 1 ? hits.single : null;
}

// ── identity ────────────────────────────────────────────────────────────────────────────────

String normIdentity(dynamic value) => '${value ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();

class StudentIdentity {
  final String name;
  final String ic;
  const StudentIdentity({this.name = '', this.ic = ''});

  bool get isEmpty => normIdentity(name).isEmpty && normIdentity(ic).isEmpty;

  bool sameAs(StudentIdentity other) {
    final ic1 = normIdentity(ic), name1 = normIdentity(name);
    return (ic1.isNotEmpty && ic1 == normIdentity(other.ic)) || (name1.isNotEmpty && name1 == normIdentity(other.name));
  }

  /// Identity carried by a report row; empty when the row names nobody.
  static StudentIdentity ofRow(Map row) =>
      StudentIdentity(name: '${row['studentName'] ?? row['name'] ?? ''}', ic: '${row['icNo'] ?? ''}');
}

class ScopedRows {
  final List<Map> rows;

  /// A sibling is selected and the report holds rows, but none can be attributed to them.
  final bool unavailable;
  const ScopedRows(this.rows, {this.unavailable = false});
}

/// Rows that belong to the student on screen.
///
/// Self: rows with no identity (the report ran with the member's own token) plus rows that
/// match self; a row naming anyone else is dropped. A selected sibling: positive matches only,
/// because the guardian's token returns every child's rows and an anonymous row could be any
/// of them.
ScopedRows scopeStudentRows(List<Map> rows, {required StudentIdentity self, StudentIdentity? selected}) {
  final isSelf = selected == null || selected.isEmpty || selected.sameAs(self);
  if (isSelf) {
    return ScopedRows([
      for (final r in rows)
        if (StudentIdentity.ofRow(r).isEmpty || StudentIdentity.ofRow(r).sameAs(self)) r,
    ]);
  }
  final mine = [
    for (final r in rows)
      if (StudentIdentity.ofRow(r).sameAs(selected)) r,
  ];
  return ScopedRows(mine, unavailable: mine.isEmpty && rows.isNotEmpty);
}

// ── attendance ──────────────────────────────────────────────────────────────────────────────

enum AttendanceStatus { present, absent, other }

AttendanceStatus attendanceStatus(dynamic type) => switch ('${type ?? ''}'.trim().toLowerCase()) {
      'present' => AttendanceStatus.present,
      'absent' => AttendanceStatus.absent,
      _ => AttendanceStatus.other,
    };

DateTime? recordedAt(Map row) => DateTime.tryParse('${row['recordedTime'] ?? ''}')?.toLocal();
DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _weekOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Start of the attendance fetch: the earlier of 12 calendar months ago and 364 days ago, so
/// the inclusive 365-day period is fully covered.
DateTime progressFetchStart(DateTime today) {
  final months = DateTime(today.year, today.month - 12, today.day);
  final days = DateTime(today.year, today.month, today.day - 364);
  return months.isBefore(days) ? months : days;
}

int invalidDateCount(List<Map> rows) => rows.where((r) => recordedAt(r) == null).length;

class PeriodCounts {
  final int present;
  final int absent;
  final int other;

  /// Present / (Present + Absent), rounded; null when neither was recorded.
  final int? rate;
  const PeriodCounts(this.present, this.absent, this.other, this.rate);
}

/// Counts for rows dated from [from] through the end of [today]. Future and invalid dates are
/// not counted.
PeriodCounts countPeriod(List<Map> rows, {required DateTime from, required DateTime today}) {
  final start = _dayOf(from);
  final end = DateTime(today.year, today.month, today.day + 1);
  var present = 0, absent = 0, other = 0;
  for (final r in rows) {
    final at = recordedAt(r);
    if (at == null || at.isBefore(start) || !at.isBefore(end)) continue;
    switch (attendanceStatus(r['attendanceType'])) {
      case AttendanceStatus.present:
        present++;
      case AttendanceStatus.absent:
        absent++;
      case AttendanceStatus.other:
        other++;
    }
  }
  final marked = present + absent;
  return PeriodCounts(present, absent, other, marked == 0 ? null : (present * 100 / marked).round());
}

class MonthAttendance {
  /// First day of the month.
  final DateTime month;
  final int present;
  final int absent;
  const MonthAttendance(this.month, this.present, this.absent);
}

class RecentActivity {
  /// The last six months, oldest first, ending with the current (partial) month.
  final List<MonthAttendance> months;

  /// Consecutive Monday-start weeks with a Present session. The current week only extends it.
  final int weekStreak;

  /// The streak runs into a week that was not fully fetched, so it may be longer.
  final bool streakAtBoundary;

  final DateTime? lastPresent;

  const RecentActivity(this.months, this.weekStreak, this.streakAtBoundary, this.lastPresent);

  int get thisMonthPresent => months.last.present;
  int get lastMonthPresent => months[months.length - 2].present;
}

/// Period-independent activity as of [now]. [fetchStart] is where the fetched history begins.
RecentActivity summarizeRecent(List<Map> rows, DateTime now, {required DateTime fetchStart}) {
  int monthKey(DateTime d) => d.year * 12 + d.month;
  final end = DateTime(now.year, now.month, now.day + 1);
  final monthStarts = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1)];
  final present = <int, int>{};
  final absent = <int, int>{};
  final presentWeeks = <DateTime>{};
  DateTime? lastPresent;

  for (final r in rows) {
    final at = recordedAt(r);
    if (at == null || !at.isBefore(end)) continue;
    final key = monthKey(at);
    switch (attendanceStatus(r['attendanceType'])) {
      case AttendanceStatus.present:
        present[key] = (present[key] ?? 0) + 1;
        presentWeeks.add(_weekOf(_dayOf(at)));
        if (lastPresent == null || at.isAfter(lastPresent)) lastPresent = at;
      case AttendanceStatus.absent:
        absent[key] = (absent[key] ?? 0) + 1;
      case AttendanceStatus.other:
        break;
    }
  }

  var week = _weekOf(_dayOf(now));
  if (!presentWeeks.contains(week)) week = DateTime(week.year, week.month, week.day - 7);
  var streak = 0;
  while (presentWeeks.contains(week)) {
    streak++;
    week = DateTime(week.year, week.month, week.day - 7);
  }
  // `week` is the week that ended the streak; if it starts before the fetched history, its
  // sessions were never loaded.
  final atBoundary = streak > 0 && week.isBefore(_dayOf(fetchStart));

  return RecentActivity(
    [for (final m in monthStarts) MonthAttendance(m, present[monthKey(m)] ?? 0, absent[monthKey(m)] ?? 0)],
    streak,
    atBoundary,
    lastPresent,
  );
}

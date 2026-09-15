// Training times across every centre an instructor can see.
//
// `/Listing/TrainingTimeByTcId/{tcid}` answers one centre at a time with `{id, text}` rows
// whose text reads like "18:00 To 19:00 (Monday) - Normal training". There is no all-centres
// route and no roster per training time, so the app merges centres itself.

const _days = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];

class ScheduleSlot {
  final Object centreId;
  final String centre;
  final Object id;
  final String label;

  /// 1 = Monday … 7 = Sunday, 0 when the label names no day.
  final int weekday;

  /// Minutes after midnight of the first time in the label, -1 when there is none.
  final int startMinutes;

  const ScheduleSlot({
    required this.centreId,
    required this.centre,
    required this.id,
    required this.label,
    required this.weekday,
    required this.startMinutes,
  });
}

String _s(dynamic v) => '${v ?? ''}'.trim();

/// The slot's display text: the server's `text`, or one built from split day/time fields.
String slotLabel(Map row) {
  final text = _s(row['text'] ?? row['name']);
  if (text.isNotEmpty) return text;
  final from = _s(row['tTimeFrom']), to = _s(row['tTimeTo']), day = _s(row['dayOfWeek']);
  final time = [from, to].where((x) => x.isNotEmpty).join(' - ');
  return [time, if (day.isNotEmpty) '($day)'].where((x) => x.isNotEmpty).join(' ');
}

/// Weekday named by `dayOfWeek` or anywhere in the label as a whole word ("Monday", "Mon",
/// "Thurs"). 1 = Monday … 7 = Sunday; 0 when none.
int slotWeekday(Map row) {
  final text = '${_s(row['dayOfWeek'])} ${slotLabel(row)}'.toLowerCase();
  for (var i = 0; i < _days.length; i++) {
    final day = _days[i];
    // Full name or any prefix of 3+ letters as a whole word: mon, tues, thurs, sat.
    if (RegExp('\\b${day.substring(0, 3)}(${day.substring(3).split('').join('?')}?)?\\b').hasMatch(text)) {
      return i + 1;
    }
  }
  return 0;
}

/// Minutes after midnight for the first "H:MM" in [label], honouring a following AM/PM.
int slotStartMinutes(String label) {
  final m = RegExp(r'(\d{1,2}):(\d{2})\s*([ap]\.?m\.?)?', caseSensitive: false).firstMatch(label);
  if (m == null) return -1;
  var hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  final meridiem = m.group(3)?.toLowerCase();
  if (meridiem != null) {
    if (meridiem.startsWith('p') && hour < 12) hour += 12;
    if (meridiem.startsWith('a') && hour == 12) hour = 0;
  }
  return hour * 60 + minute;
}

/// Every centre's slots in one list, ordered Monday → Sunday, then start time, then centre.
/// Slots whose label names no day come last.
List<ScheduleSlot> buildSchedule(List<({Map centre, List<Map> rows})> perCentre) {
  final slots = [
    for (final c in perCentre)
      for (final r in c.rows)
        ScheduleSlot(
          centreId: c.centre['id'] ?? '',
          centre: _s(c.centre['text']),
          id: r['id'] ?? '',
          label: slotLabel(r),
          weekday: slotWeekday(r),
          startMinutes: slotStartMinutes(slotLabel(r)),
        ),
  ];
  int dayRank(int d) => d == 0 ? 8 : d;
  slots.sort((a, b) {
    final byDay = dayRank(a.weekday).compareTo(dayRank(b.weekday));
    if (byDay != 0) return byDay;
    final byTime = a.startMinutes.compareTo(b.startMinutes);
    if (byTime != 0) return byTime;
    return a.centre.compareTo(b.centre);
  });
  return slots;
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/class_booking.dart';
import '../services/live_refresh.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/anim.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

const _dowShort = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
const _dowFull = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const _sessionColors = [
  Color(0xFF4F46E5),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFFEF4444),
  Color(0xFF9333EA),
  Color(0xFF0EA5E9),
  Color(0xFFDB2777),
];

/// The calendar reaches this month plus the next 11.
const _monthsAhead = 12;

String _dowFullOf(DateTime d) => _dowFull[d.weekday % 7];

/// Port of `frontend/app/(tabs)/schedule.tsx` (Expo v2.11.1), except the RN 10-day strip is now
/// a month calendar that expands to 12 months: members book further ahead than ten days and
/// could not see those dates (manual QA 2026-10-01).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with UseApi<ScheduleScreen>, LiveRefreshMixin<ScheduleScreen> {
  final _range = RnApi.defaultRange();
  late final _details = useApi(() {
    final session = UserSession.instance;
    return RnApi.studentDetails({
      'sourceKeyId': session.currentStudentId,
      'studentName': session.activeStudentName,
      'fromDate': _range.fromDate,
      'toDate': _range.toDate,
    });
  });
  // One-off approved bookings, on top of the weekly timetable above.
  late final _bookings = useApi(() => RnApi.getBookings(studentId: UserSession.instance.currentStudentId));
  late DateTime _selected = DateUtils.dateOnly(DateTime.now());
  int _page = 0; // months after this one, in the single-month view
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _details;
    _bookings;
  }

  @override
  Future<void> refreshLiveData() => reloadAll(silent: true);

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final top = MediaQuery.paddingOf(context).top;
    final tabBarHeight = tabBarClearance(context);

    final today = DateUtils.dateOnly(DateTime.now());
    DateTime monthAt(int i) => DateTime(today.year, today.month + i);
    final selected = _selected;
    final selectedDow = _dowFullOf(selected);

    // Report routes can return the whole branch for a student token — keep own rows only.
    final rows = session.scopedRows(_details.data).whereType<Map>().toList();
    // Not scopedRows: GetBookings is already the member's own, and a booking's `name` is its
    // slot label — scopeToSelf would read several labels as several people and hide them all.
    final bookings = _bookings.data ?? const <Map<String, dynamic>>[];
    final weekly = rows.where((r) => '${r['dayOfWeek'] ?? ''}'.toLowerCase() == selectedDow.toLowerCase()).toList();
    final classes = [...weekly, ...bookedClassesOn(bookings, selected, timetable: weekly)];
    final trainingDows = rows.map((r) => '${r['dayOfWeek'] ?? ''}'.toLowerCase()).toSet();
    final bookedDates = approvedBookingDates(bookings);
    // The orange dot: a future day with a weekly class or an approved booking.
    bool hasClass(DateTime d) =>
        !d.isBefore(today) &&
        (trainingDows.contains(_dowFullOf(d).toLowerCase()) || bookedDates.contains(isoDate(d)));
    _MonthGrid grid(int page) => _MonthGrid(
          month: monthAt(page),
          today: today,
          selected: selected,
          hasClass: hasClass,
          onPick: (d) => setState(() {
            _selected = d;
            _page = page;
            _expanded = false;
          }),
        );

    BoxDecoration cardDeco() => BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: Shadows.soft(c),
          border: c.isDark ? Border.all(color: c.border) : null,
        );

    final body = <Widget>[];
    if (_details.loading) {
      body.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
            child: SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary))),
      ));
    }
    if (!_details.loading && _details.error != null) {
      body.add(ErrorState(message: _details.error, onRetry: _details.reload));
    }
    if (!_details.loading && _details.error == null && classes.isEmpty) {
      body.addAll([
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Rest Day',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.textPrimary)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 70),
          child: Column(children: [
            Icon(Ion.bedOutline, size: 44, color: c.textMuted),
            const SizedBox(height: 16),
            Text('No classes scheduled',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.textPrimary)),
            const SizedBox(height: 6),
            Text('Recovery is part of the journey', style: TextStyle(fontSize: 14, color: c.textSecondary)),
          ]),
        ),
      ]);
    }
    if (!_details.loading && classes.isNotEmpty) {
      body.add(Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 14),
        child: Text(
            '${classes.length} session${classes.length > 1 ? 's' : ''} · ${DateFormat('EEEE, d MMM').format(selected)}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textSecondary)),
      ));
      for (var i = 0; i < classes.length; i++) {
        final r = classes[i];
        final grade = '${r['currentGrade'] ?? ''}';
        body.add(Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: cardDeco(),
          child: IntrinsicHeight(
            child: Row(children: [
              SizedBox(
                width: 64,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_str(r['tTimeFrom']),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary)),
                  const SizedBox(height: 2),
                  Text('to ${_str(r['tTimeTo'])}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 10, color: c.textSecondary, fontWeight: FontWeight.w700)),
                ]),
              ),
              Container(
                width: 4,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                    color: _sessionColors[i % _sessionColors.length], borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_str(r['tCenterName'], 'Training'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    const SizedBox(height: 6),
                    Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
                      Icon(Ion.personOutline, size: 12, color: c.textSecondary),
                      Text(_str(r['instructorName'], 'Instructor'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w500)),
                      if (grade.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Icon(Ion.ribbonOutline, size: 12, color: c.textSecondary),
                        Text(grade,
                            style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ]),
                  ],
                ),
              ),
            ]),
          ),
        ));
      }
    }

    final monthTitle = TextStyle(fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: c.textPrimary);
    // clearance = tab bar + floating Book button zone
    final listPadding = EdgeInsets.fromLTRB(Gaps.xl, 4, Gaps.xl, tabBarHeight + 92);

    // A 44pt touch target around a 34pt chip; dimmed, not hidden, at either end of the 12 months.
    Widget pager(IconData icon, String label, VoidCallback? onPress) => Semantics(
          button: true,
          enabled: onPress != null,
          label: label,
          excludeSemantics: true,
          child: Touchable(
            onPress: onPress,
            child: SizedBox.square(
              dimension: 44,
              child: Center(
                child: Opacity(
                  opacity: onPress == null ? 0.35 : 1,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                    child: Icon(icon, size: 17, color: c.textPrimary),
                  ),
                ),
              ),
            ),
          ),
        );

    // One month, with the selected day's classes below it.
    final monthView = ListView(
      key: const ValueKey('month'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: listPadding,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.xs, Gaps.md, 0),
          decoration: cardDeco(),
          child: Column(children: [
            Row(children: [
              const SizedBox(width: Gaps.xs),
              Expanded(
                child: Text(DateFormat('MMMM y').format(monthAt(_page)),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: monthTitle),
              ),
              pager(Ion.chevronBack, 'Previous month', _page > 0 ? () => setState(() => _page--) : null),
              pager(Ion.chevronForward, 'Next month',
                  _page < _monthsAhead - 1 ? () => setState(() => _page++) : null),
            ]),
            grid(_page),
            Divider(height: 1, thickness: 1, color: c.border),
            Semantics(
              button: true,
              child: Touchable(
                onPress: () => setState(() => _expanded = true),
                activeOpacity: 0.6,
                child: SizedBox(
                  height: 48,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('View all 12 months',
                        style: TextStyle(color: c.primary, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Icon(Ion.chevronDown, size: 16, color: c.primary),
                  ]),
                ),
              ),
            ),
          ]),
        ),
        ...body,
      ],
    );

    // All 12 months. Picking a day collapses back to its month (see grid()).
    final yearView = Column(
      key: const ValueKey('year'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pinned above the list, so collapsing never needs a scroll back up.
        Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, Gaps.xs),
          child: Row(children: [
            Expanded(
              child: Text('Tap a date to see its classes', style: TextStyle(fontSize: 13, color: c.textSecondary)),
            ),
            Semantics(
              button: true,
              child: Touchable(
                onPress: () => setState(() => _expanded = false),
                activeOpacity: 0.6,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Collapse', style: TextStyle(color: c.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      Icon(Ion.chevronUp, size: 15, color: c.primary),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: listPadding,
            itemCount: _monthsAhead,
            itemBuilder: (context, i) => Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.md, Gaps.md, Gaps.xs),
              decoration: cardDeco(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(left: Gaps.xs, bottom: Gaps.sm),
                  child: Text(DateFormat('MMMM y').format(monthAt(i)), style: monthTitle),
                ),
                grid(i),
              ]),
            ),
          ),
        ),
      ],
    );

    return ColoredBox(
      color: c.background,
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(Gaps.xl, top + 14, Gaps.xl, 14),
            child: Row(children: [
              const TabRootBackButton(),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Schedule',
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Next 12 months', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                ]),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(kLogoAssetPath, width: 40, height: 40),
              ),
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              color: c.primary,
              onRefresh: reloadAll,
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.base,
                switchInCurve: Motion.enter,
                child: _expanded ? yearView : monthView,
              ),
            ),
          ),
        ]),
        // Hidden when the club has switched class booking off for this account
        // (the screen behind it refuses anyway). Parity review F6.
        if (UserSession.instance.allowClassBooking)
        Positioned(
          right: Gaps.xl,
          bottom: tabBarHeight + Gaps.md,
          child: Touchable(
            onPress: () => context.push('/book-class'),
            activeOpacity: 0.9,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: c.gradient),
                borderRadius: BorderRadius.circular(999),
                boxShadow: Shadows.strong(c),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Ion.add, size: 20, color: Colors.white),
                SizedBox(width: 8),
                Text('Book a class', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// One month as a Sunday-first grid. Days outside the month stay blank, so no date shows twice
/// in the 12-month view; past days are muted and can't be picked.
class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final DateTime selected;
  final bool Function(DateTime) hasClass;
  final ValueChanged<DateTime> onPick;
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selected,
    required this.hasClass,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final lead = month.weekday % 7; // blanks before the 1st
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final cells = List<DateTime?>.generate(((lead + days) / 7).ceil() * 7,
        (i) => i < lead || i >= lead + days ? null : DateTime(month.year, month.month, i - lead + 1));
    return Column(children: [
      Row(children: [
        for (final d in _dowShort)
          Expanded(
            child: Text(d,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.textMuted)),
          ),
      ]),
      const SizedBox(height: Gaps.xs),
      for (var r = 0; r < cells.length; r += 7)
        Row(children: [
          for (final d in cells.sublist(r, r + 7))
            Expanded(child: d == null ? const SizedBox(height: 46) : _day(c, d)),
        ]),
    ]);
  }

  Widget _day(AppColors c, DateTime d) {
    final past = d.isBefore(today);
    final on = DateUtils.isSameDay(d, selected);
    final isToday = DateUtils.isSameDay(d, today);
    final dot = hasClass(d);
    return Semantics(
      button: true,
      selected: on,
      enabled: !past,
      label: '${DateFormat('EEEE, d MMMM y').format(d)}${dot ? ', classes scheduled' : ''}',
      excludeSemantics: true,
      child: Touchable(
        onPress: past ? null : () => onPick(d),
        activeOpacity: 0.6,
        child: SizedBox(
          height: 46,
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on ? c.primary : null,
                border: isToday && !on ? Border.all(color: c.primary, width: 1.5) : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${d.day}',
                    style: TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        fontWeight: on || isToday ? FontWeight.w800 : FontWeight.w600,
                        color: on
                            ? Colors.white
                            : past
                                ? c.textMuted
                                : isToday
                                    ? c.primary
                                    : c.textPrimary)),
                // The 10-day strip's 5×5 dot; dotless days keep its space so numbers stay level.
                if (dot)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(top: 3),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: on ? Colors.white : c.primary),
                  )
                else
                  const SizedBox(height: 8),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

String _str(dynamic v, [String fallback = '—']) {
  final s = '${v ?? ''}';
  return s.isEmpty ? fallback : s;
}

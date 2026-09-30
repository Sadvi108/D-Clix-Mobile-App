import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/class_booking.dart';
import '../services/response_utils.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/report_kit.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _wdShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _wdLong = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// `toLocaleDateString("en-GB", {weekday: "short", day: "2-digit", month: "short"})`.
String _wdDayMon(DateTime d) => '${_wdShort[d.weekday - 1]}, ${d.day.toString().padLeft(2, '0')} ${_monthsShort[d.month - 1]}';

int _intOf(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Port of `frontend/app/book-class.tsx` (Expo v2.11.1).
///
/// The timetable is weekly and BookNow accepts any date, so the app owns the date choice
/// and the duplicate check — see `class_booking.dart`.
class BookClassScreen extends StatefulWidget {
  const BookClassScreen({super.key});
  @override
  State<BookClassScreen> createState() => _BookClassScreenState();
}

class _BookClassScreenState extends State<BookClassScreen> with UseApi<BookClassScreen> {
  // Book for the child the guardian picked, not whoever holds the token. The
  // package, the entitlement count, the existing bookings behind the duplicate
  // check and the label on screen must all name this same student, or the app
  // can show one child while booking for another.
  late int _studentId = _subjectId();
  static int _subjectId() =>
      UserSession.instance.currentStudentId ?? _intOf(UserSession.instance.authData?['id']);

  /// Whose booking screen this is, for the header line.
  String get _subjectName => UserSession.instance.displayName;
  late final _centers = useApi(RnApi.trainingCenters);
  late final _instructors = useApi(RnApi.instructors);
  late final _info = useApi(RnApi.myInfo);
  // Scoped to the subject: a guardian's token would otherwise answer with the
  // account holder's bookings and the duplicate check would pass on a class the
  // selected child already has.
  late final _bookings = useApi(() async {
    // Read strictly, not through RnApi's lenient `_rows`: a `data` that is not
    // a list means the duplicate check is UNKNOWN, and an empty list would read
    // as "nothing booked yet" and wave a repeat booking through.
    // Parity review round 4.
    final raw = unwrapData(
        await Api.classBookingGetBookings(studentId: _studentId == 0 ? null : _studentId));
    if (raw is! List) throw StateError('bookings response was not a list');
    return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).where((r) {
      final id = _intOf(r['studentId'] ?? r['studentID']);
      return id == 0 || id == _studentId; // rows without an id are already token-scoped
    }).toList();
  });
  late final _pkg = useApi<Map<String, dynamic>?>(() async {
    if (_studentId == 0) return null;
    final d = unwrapData(await Api.classBookingPackageInfo(_studentId));
    return d is Map ? Map<String, dynamic>.from(d) : null;
  });
  late final _slots = useApi<List<Map<String, dynamic>>>(() async {
    if (_tCenterId == 0 || _instructorId == 0) return const [];
    final d = unwrapData(await Api.classBookingTrainingTimeWithDateAndInstructor(
        month: _month, year: _year, tCenterId: _tCenterId, instructorId: _instructorId));
    return d is List ? d.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
  }, autoRun: false);

  late final VoidCallback _watchSubject = () {
    final now = _subjectId();
    if (!mounted || now == _studentId) return;
    setState(() => _studentId = now);
    _pkg.reload();
    _bookings.reload();
  };

  int _tCenterId = 0;
  int _instructorId = 0;
  int _monthOffset = 0;
  int? _selectedSlot;
  String? _selectedDate;
  bool _booking = false;
  bool _defaultsApplied = false;

  DateTime get _target {
    final base = DateTime.now();
    return DateTime(base.year, base.month + _monthOffset, 1);
  }

  int get _month => _target.month;
  int get _year => _target.year;

  @override
  void initState() {
    super.initState();
    _centers;
    _instructors;
    _info;
    _bookings;
    _pkg;
    _slots;
    UserSession.instance.addListener(_watchSubject);
  }

  @override
  void dispose() {
    UserSession.instance.removeListener(_watchSubject);
    super.dispose();
  }

  /// Default the centre to the student's own, the instructor to their own — once MyInfo has
  /// resolved, so the match is known before a default is locked in.
  void _applyDefaults() {
    if (_defaultsApplied || _info.loading) return;
    final centers = _centers.data;
    final instructors = _instructors.data;
    if (centers == null || instructors == null || centers.isEmpty || instructors.isEmpty) return;
    final info = _info.data ?? const <String, dynamic>{};
    final mineC = centers.where((c) => c['text'] == info['tCenterName'] || c['value'] == info['tCenterName']).firstOrNull;
    final mineI = instructors
        .where((i) => _intOf(i['id']) == _intOf(info['instructorId']) || i['text'] == info['instructorName'])
        .firstOrNull;
    _defaultsApplied = true;
    _tCenterId = _intOf((mineC ?? centers.first)['id']);
    _instructorId = _intOf((mineI ?? instructors.first)['id']);
    WidgetsBinding.instance.addPostFrameCallback((_) => _slots.reload());
  }

  void _select(void Function() fn) {
    setState(() {
      fn();
      _selectedSlot = null;
      _selectedDate = null;
      _slots.data = null;
    });
    _slots.reload();
  }

  /// Why a booking cannot be judged right now, or null when it can.
  ///
  /// Both the package AND the existing bookings have to be known for the
  /// CURRENT subject first: a package still loading is not "no quota", a failed
  /// duplicate lookup is not "nothing booked yet", and an empty PackageInfo is
  /// not an unlimited membership. Each of those, read optimistically, books a
  /// class the student is not entitled to. Parity review round 4.
  String? get _notReadyReason {
    if (_pkg.loading || _bookings.loading) {
      return "Still loading this student's package and bookings. Try again in a moment.";
    }
    if (_pkg.error != null || !isUsablePackage(_pkg.data)) {
      return "Your package could not be loaded, so remaining classes can't be checked. Try again in a moment.";
    }
    if (_bookings.error != null || _bookings.data == null) {
      return "Your existing bookings could not be loaded, so a repeat booking can't be ruled out. Try again in a moment.";
    }
    return null;
  }

  Future<void> _confirm(Map<String, dynamic> chosen, bool alreadyBooked) async {
    if (_studentId == 0 || _booking) return;
    if (_selectedDate == null) {
      await notify(context, 'Pick a date', 'Choose which date you want to attend this class.');
      return;
    }
    if (alreadyBooked) {
      await notify(context, 'Already booked', "You've already booked this class on that date. Pick another date.");
      return;
    }
    if (!UserSession.instance.allowClassBooking) {
      await notify(context, 'Cannot book',
          'Your academy has switched class booking off for this account.');
      return;
    }
    final blocked = _notReadyReason;
    if (blocked != null) {
      await notify(context, 'Cannot book', blocked);
      return;
    }

    // Everything the booking is made of, read ONCE before the first await.
    // A guardian who switches child (or logs out, or switches branch) while the
    // quota call is in flight would otherwise have this screen's newer subject
    // posted against the older subject's quota. The snapshot keeps the request
    // internally consistent; `stale()` abandons it outright when the identity
    // behind it has moved. Parity review round 4.
    final session = UserSession.instance;
    final epoch = session.sessionEpoch;
    final studentId = _studentId;
    final date = _selectedDate!;
    final timeId = _intOf(chosen['id']);
    final tCenterId = _tCenterId;
    final instructorId = _instructorId;
    final month = _month;
    final year = _year;
    final pkg = _pkg.data;
    final packageType = pkg?['packageType']?.toString();
    final packageId = _intOf(pkg?['packageId']);
    final typeId = packageTypeId(packageType);
    final quota = packageQuota(pkg) ?? 0;

    /// True once this booking no longer describes who the app is acting for —
    /// the screen is gone, the session changed, or the subject changed.
    bool stale() => !mounted || session.sessionEpoch != epoch || _studentId != studentId;

    /// The club's booking switch is read again right before the mutation, not
    /// only when the screen was built: a session refresh can revoke it while a
    /// quota call is in flight. Parity review F6.
    bool denied() => !session.allowClassBooking;

    setState(() => _booking = true);
    try {
      // Quota-limited packages: ask the server what this student has already
      // booked this month before adding another (the old app disabled the
      // calendar instead; refusing at confirm time is the same guarantee).
      if (typeId == 1 || typeId == 2) {
        var booked = 0;
        if (packageId != 0) {
          try {
            final counted = await Api.classBookingBookingCountByPackageSession(
              packageTypeId: typeId,
              packageId: packageId,
              studentId: studentId,
              month: month,
              year: year,
            );
            final rows = unwrapData(counted);
            if (rows is! List) {
              // Not a list: the count is unknown, which is not the same as zero.
              throw StateError('quota response was not a list');
            }
            booked = rows.length;
          } catch (_) {
            // Fail closed: an unreachable quota is not proof of an unused one.
            if (!stale() && mounted) {
              await notify(context, 'Cannot book',
                  "Couldn't check how many classes are left on this package. Try again in a moment.");
            }
            return;
          }
        }
        // The count that just came back describes `studentId`. If the subject
        // moved while it was in flight, it says nothing about the new one.
        if (stale()) return;
        final allowance = bookingAllowance(
          typeId: typeId,
          sessionId: packageId,
          noOfClasses: quota,
          alreadyBooked: booked,
        );
        if (allowance.blocked) {
          if (mounted) await notify(context, 'Cannot book', allowance.reason!);
          return;
        }
      }
      // Last gate before the only mutation on this screen.
      if (stale()) return;
      if (denied()) {
        if (mounted) {
          await notify(context, 'Cannot book',
              'Your academy has switched class booking off for this account.');
        }
        return;
      }
      await Api.classBookingBookNow(bookNowBody(
        tCenterId: tCenterId,
        instructorId: instructorId,
        studentId: studentId,
        timeId: timeId,
        date: date,
        slotName: '${chosen['name'] ?? ''}',
        packageType: packageType,
        sessionId: packageId,
        centerName: '${chosen['centerName'] ?? ''}',
        instructorName: '${chosen['instructorName'] ?? ''}',
      ));
      final when = DateTime.parse('${date}T00:00:00');
      if (stale()) return;
      setState(() {
        _selectedSlot = null;
        _selectedDate = null;
      });
      // The booking just used a class: re-read both the duplicate list and the
      // package so the next attempt counts this one.
      _bookings.reload();
      _pkg.reload();
      if (!mounted) return;
      await notify(context, 'Class booked',
          '${chosen['name']}\n${_wdLong[when.weekday - 1]}, ${when.day.toString().padLeft(2, '0')} ${_monthsShort[when.month - 1]} · ${chosen['centerName'] ?? ''}');
    } catch (e) {
      if (mounted) await notify(context, 'Booking failed', friendlyError(e));
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // The club can switch class booking off per account (old
    // `HomePageViewModel.cs:370`). Blocked at the screen rather than at each
    // entry point, so a deep link or an older tile cannot walk around it.
    // Parity review F6.
    if (!UserSession.instance.allowClassBooking) {
      return Scaffold(
        backgroundColor: c.background,
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const RnHeader(title: 'Book a Class'),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Ion.calendarOutline, size: 44, color: c.textMuted),
                const SizedBox(height: 14),
                Text('Class booking is switched off',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                const SizedBox(height: 8),
                Text('Your academy has not enabled booking for this account. They can turn it on for you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, height: 19 / 13, color: c.textSecondary)),
              ]),
            ),
          ),
        ]),
      );
    }
    _applyDefaults();

    final centers = _centers.data ?? const <Map<String, dynamic>>[];
    final instructors = _instructors.data ?? const <Map<String, dynamic>>[];
    final slotList = _slots.data ?? const <Map<String, dynamic>>[];
    final bookings = _bookings.data ?? const <Map<String, dynamic>>[];
    final chosen = slotList.where((s) => _intOf(s['id']) == _selectedSlot).firstOrNull;
    final centerName = '${centers.where((x) => _intOf(x['id']) == _tCenterId).firstOrNull?['text'] ?? ''}';
    final instructorName = '${instructors.where((x) => _intOf(x['id']) == _instructorId).firstOrNull?['text'] ?? ''}';
    final monthLabel = '${_monthsLong[_month - 1]} $_year';

    final dateOptions = chosen == null ? const <DateTime>[] : datesForDayOfWeek('${chosen['dayOfWeek'] ?? ''}', _month, _year);
    final taken = chosen == null ? const <String>{} : takenDates(bookings, _intOf(chosen['id']));
    // Preselect the first date not already booked, once a slot is chosen.
    if (chosen != null && (_selectedDate == null || !dateOptions.any((d) => isoDate(d) == _selectedDate))) {
      _selectedDate = preferredDate(dateOptions, taken);
    }
    final alreadyBooked = chosen != null && _selectedDate != null && taken.contains(_selectedDate);
    final myBookings = sortBookings(bookings);
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: RkLabel(t),
        );
    Widget section(String t) => Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 12),
          child: Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
        );
    Widget chip(String text, bool on, VoidCallback onTap) => Touchable(
          onPress: onTap,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: on ? c.primary : c.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? c.primary : c.border),
            ),
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: on ? Colors.white : c.textPrimary)),
          ),
        );
    Widget chipRow(List<Widget> chips) => SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) => chips[i],
          ),
        );
    Widget emptySub(String t) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(t, style: TextStyle(fontSize: 13, color: c.textSecondary)),
        );

    // The package and the booking list gate the button too, not just the
    // handler: a Confirm that looks live while the entitlement is unknown
    // invites the tap it then has to refuse.
    final notReady = _notReadyReason;
    final canConfirm =
        chosen != null && _selectedDate != null && !alreadyBooked && !_booking && notReady == null;
    final confirmLabel = chosen == null
        ? 'Select a session'
        : alreadyBooked
            ? 'Already booked'
            : _selectedDate == null
                ? 'Pick a date'
                : notReady != null
                    ? (_pkg.loading || _bookings.loading ? 'Checking your package…' : 'Cannot book right now')
                    : 'Confirm · ${_wdDayMon(DateTime.parse('${_selectedDate!}T00:00:00'))}';

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'Book a Class'),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl - 18, Gaps.xl, 150 + bottom),
            children: [
              // Say whose classes these are: a guardian switching children must
              // never be left guessing who the booking is for.
              if (UserSession.instance.activeStudentName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Row(children: [
                    Icon(Ion.person, size: 14, color: c.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Booking for $_subjectName',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    ),
                  ]),
                ),
              label('Training Center'),
              if (_centers.loading)
                const RnSpinner(vertical: 12)
              else
                chipRow([
                  for (final x in centers)
                    chip('${x['text'] ?? x['value'] ?? ''}', _intOf(x['id']) == _tCenterId,
                        () => _select(() => _tCenterId = _intOf(x['id']))),
                ]),
              label('Instructor'),
              if (_instructors.loading)
                const RnSpinner(vertical: 12)
              else
                chipRow([
                  for (final x in instructors)
                    chip('${x['text'] ?? x['value'] ?? ''}', _intOf(x['id']) == _instructorId,
                        () => _select(() => _instructorId = _intOf(x['id']))),
                ]),
              label('Month'),
              Row(children: [
                for (final off in const [0, 1]) ...[
                  if (off > 0) const SizedBox(width: 10),
                  Expanded(
                    child: Touchable(
                      onPress: () => _select(() => _monthOffset = off),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: off == _monthOffset ? c.primary : c.surface,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: off == _monthOffset ? c.primary : c.border),
                        ),
                        child: Text(_monthsLong[DateTime(today.year, today.month + off, 1).month - 1],
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: off == _monthOffset ? Colors.white : c.textPrimary)),
                      ),
                    ),
                  ),
                ],
              ]),

              section('Available Sessions · $monthLabel'),
              if (_slots.loading) const RnSpinner(vertical: 20),
              if (_slots.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_slots.error!, style: TextStyle(color: c.danger, fontSize: 13)),
                ),
              if (!_slots.loading && slotList.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(children: [
                    Icon(Ion.calendarOutline, size: 40, color: c.textMuted),
                    const SizedBox(height: 12),
                    Text('No sessions here',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
                    emptySub(
                        "${instructorName.isNotEmpty ? "$instructorName doesn't teach at " : 'No timetable at '}${centerName.isEmpty ? 'this centre' : centerName}. Pick another instructor or centre above."),
                  ]),
                ),
              for (final s in slotList)
                Builder(builder: (context) {
                  final on = _intOf(s['id']) == _selectedSlot;
                  final limit = _intOf(s['classLimit']);
                  return Touchable(
                    activeOpacity: 0.85,
                    onPress: () => setState(() {
                      _selectedSlot = _intOf(s['id']);
                      _selectedDate = null;
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(Radii.lg),
                        boxShadow: Shadows.soft(c),
                        border: Border.all(color: on ? c.primary : c.border, width: on ? 2 : 1),
                      ),
                      child: Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: on ? c.primary : c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
                          child: Text('${s['dayOfWeek'] ?? ''}'.substring(0, ('${s['dayOfWeek'] ?? ''}'.length).clamp(0, 3)).toUpperCase(),
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: on ? Colors.white : c.primary)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${s['name'] ?? ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary)),
                            const SizedBox(height: 3),
                            Text('${s['centerName'] ?? ''} · ${s['instructorName'] ?? ''}${limit > 0 ? ' · max $limit' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: c.textSecondary)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Icon(on ? Ion.radioButtonOn : Ion.radioButtonOff, size: 22, color: on ? c.primary : c.textMuted),
                      ]),
                    ),
                  );
                }),

              if (chosen != null) ...[
                section('Pick a date'),
                if (dateOptions.isEmpty)
                  emptySub('No ${chosen['dayOfWeek']} left in $monthLabel. Choose next month above.')
                else
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: dateOptions.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final d = dateOptions[i];
                        final key = isoDate(d);
                        final on = key == _selectedDate;
                        final isTaken = taken.contains(key);
                        return Opacity(
                          opacity: isTaken ? 0.55 : 1,
                          child: Touchable(
                            onPress: () => setState(() => _selectedDate = key),
                            child: Container(
                              constraints: const BoxConstraints(minWidth: 62),
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: on ? c.primary : c.surface,
                                borderRadius: BorderRadius.circular(Radii.md),
                                border: Border.all(color: on ? c.primary : c.border),
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Text('${d.day}',
                                    style: TextStyle(
                                        fontSize: 17, fontWeight: FontWeight.w800, color: on ? Colors.white : c.textPrimary)),
                                const SizedBox(height: 2),
                                Text(isTaken ? 'booked' : _monthsShort[d.month - 1],
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: on ? Colors.white : c.textSecondary)),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (alreadyBooked)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('You already have this class booked on that date.',
                        style: TextStyle(fontSize: 12, color: c.warning, fontWeight: FontWeight.w600)),
                  ),
              ],

              section('My Bookings'),
              if (_bookings.loading) const RnSpinner(vertical: 16),
              if (!_bookings.loading && bookings.isEmpty) emptySub('No bookings yet.'),
              for (final b in myBookings)
                Builder(builder: (context) {
                  final t = DateTime.tryParse('${b['trainingDate'] ?? ''}');
                  final past = t != null && t.isBefore(todayDate);
                  final status = '${b['status'] ?? ''}';
                  final ok = isApprovedBooking(b);
                  return Opacity(
                    opacity: past ? 0.55 : 1,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 9),
                      padding: const EdgeInsets.all(13),
                      decoration: rnCard(c, radius: Radii.md),
                      child: Row(children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                          child: Icon(past ? Ion.timeOutline : Ion.checkmarkDone, size: 18, color: c.primary),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${b['title'] ?? ''}'.isEmpty ? 'Class' : '${b['title']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary)),
                            const SizedBox(height: 3),
                            Text('${t == null ? '' : _wdDayMon(t)} · ${b['centerName'] ?? ''}${past ? ' · past' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: c.textSecondary)),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Text(status.isEmpty ? 'Pending' : status,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: ok ? c.success : c.warning)),
                      ]),
                    ),
                  );
                }),
            ],
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, bottom + 12 > 28 ? bottom + 12 : 28),
          decoration: BoxDecoration(color: c.background, border: Border(top: BorderSide(color: c.border))),
          child: Opacity(
            opacity: canConfirm ? 1 : 0.5,
            child: Touchable(
              activeOpacity: 0.9,
              onPress: canConfirm ? () => _confirm(chosen, alreadyBooked) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: c.gradient),
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: Shadows.strong(c),
                ),
                child: _booking
                    ? const Center(
                        child: SizedBox(
                            width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)))
                    : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Ion.addCircle, size: 20, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(confirmLabel,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

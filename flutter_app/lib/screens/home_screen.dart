import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/class_booking.dart';
import '../services/live_refresh.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../utils/progress_stats.dart';
import '../utils/training_schedule.dart';
import '../widgets/member_avatar.dart';
import '../widgets/rn_kit.dart';
import '../widgets/student_switcher.dart';
import '../widgets/use_api.dart';

/// Student Quick Access grid — `quickCards` in `frontend/app/(tabs)/home.tsx`.
/// Menu configuration, not content; `more_screen.dart` shares these icons/colours.
typedef QuickTile = ({String id, String label, IconData icon, Color color, String route});

const List<QuickTile> kStudentQuickCards = [
  (id: 'attendance', label: 'Attendance', icon: Ion.checkmarkCircle, color: Color(0xFF10B981), route: '/attendance'),
  (id: 'classes', label: "Today's Classes", icon: Ion.flash, color: Color(0xFFF59E0B), route: '/schedule'),
  (id: 'trainer', label: 'My Trainer', icon: Ion.personCircle, color: Color(0xFF8B5CF6), route: '/training'),
  (id: 'timetable', label: 'Timetable', icon: Ion.calendar, color: Color(0xFF0EA5E9), route: '/schedule'),
  (id: 'fees', label: 'Fees Due', icon: Ion.wallet, color: Color(0xFFEF4444), route: '/payments'),
  (id: 'payments', label: 'Payment History', icon: Ion.receipt, color: Color(0xFF14B8A6), route: '/payments?tab=history'),
  (id: 'progress', label: 'Progress Report', icon: Ion.trendingUp, color: Color(0xFF6366F1), route: '/progress'),
  (id: 'belt', label: 'Belt / Rank', icon: Ion.ribbon, color: Color(0xFFEAB308), route: '/belt-rank'),
  (id: 'events', label: 'Events', icon: Ion.calendar, color: Color(0xFFF97316), route: '/events'),
  (id: 'tournament', label: 'Tournament', icon: Ion.trophy, color: Color(0xFFDB2777), route: '/tournament'),
  (id: 'purchase', label: 'Purchase Request', icon: Ion.bagHandle, color: Color(0xFFF59E0B), route: '/purchase-request'),
  (id: 'chat', label: 'Chat Academy', icon: Ion.chatbubbles, color: Color(0xFF22C55E), route: '/chat'),
  (id: 'more', label: 'More', icon: Ion.grid, color: Color(0xFF64748B), route: '/more'),
];

/// Quick Access and All Features are drill-downs, never tab switches — always push, so there's
/// a screen to pop back to. `go` replaces the stack and strands the caller with no back control
/// (manual QA 2026-09-24, bugs 1 and 2).
void openRoute(BuildContext context, String route) => context.push(route);

/// Port of `StudentHome` in `frontend/app/(tabs)/home.tsx` (Expo v2.11.1).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with UseApi<HomeScreen>, LiveRefreshMixin<HomeScreen> {
  late final _stats = useApi(RnApi.homePageStats, initial: UserSession.instance.homeStats);
  late final _info = useApi(RnApi.myInfo, initial: UserSession.instance.myInfo);
  final _range = RnApi.defaultRange();
  late final _schedule = useApi(() {
    final session = UserSession.instance;
    return RnApi.studentDetails({
      'sourceKeyId': session.currentStudentId,
      'studentName': session.activeStudentName,
      'fromDate': _range.fromDate,
      'toDate': _range.toDate,
    });
  });
  late final _bookings = useApi(
      () => RnApi.getBookings(studentId: UserSession.instance.currentStudentId));

  @override
  void initState() {
    super.initState();
    _stats;
    _info;
    _schedule;
    _bookings;
  }

  @override
  Future<void> refreshLiveData() => reloadAll(silent: true);

  Future<void> _pullRefresh() => Future.wait([reloadAll(), UserSession.instance.refresh(background: true)]);

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final top = MediaQuery.paddingOf(context).top;
    final tabBarHeight = tabBarClearance(context);

    final user = session.authData ?? const <String, dynamic>{};
    String userField(String k) => '${user[k] ?? ''}'.trim();
    final stats = _stats.data;
    final hasSelectedStudent = session.activeStudentName?.trim().isNotEmpty ?? false;
    final info = hasSelectedStudent ? session.activeStudentInfo : _info.data;
    final infoLoading = hasSelectedStudent ? session.activeStudentInfoLoading : _info.loading;

    final statsLoading = _stats.loading && stats == null;
    final statsFailed = _stats.error != null && stats == null;
    final gradeRaw = '${info?['currentGrade'] ?? ''}'.isNotEmpty
        ? '${info!['currentGrade']}'
        : (!hasSelectedStudent && userField('currentGrade').isNotEmpty ? userField('currentGrade') : '—');
    final grade = gradeRaw.replaceFirst(RegExp(r'Grade\s*', caseSensitive: false), '');
    final beltShort = grade.split(' ').first;
    final num dueAmount = RnApi.number(stats?['dueAmount']);
    final invoiceCount = RnApi.number(stats?['invoiceCount']).toInt();
    final unread = session.unreadNotifications;
    final status = userField('status');
    final isActive = status.toLowerCase() != 'inactive';
    // A guardian can narrow the app to one sibling; greet whoever is active.
    final activeName = session.activeStudentName?.trim() ?? '';
    final name = activeName.isNotEmpty ? activeName : (userField('name').isEmpty ? 'Member' : userField('name'));
    final clubName = userField('clubName');
    final scheduleRows = session.scopedRows(_schedule.data).whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row)).toList();
    final now = DateTime.now();
    final todayClasses = scheduledClassesOn(
        scheduleRows, _bookings.data ?? const <Map<String, dynamic>>[], now);
    final homeClass = featuredClassToday(todayClasses, now: now);
    final classLoading = (_schedule.loading && _schedule.data == null) ||
        (_bookings.loading && _bookings.data == null);
    final classTime = homeClass == null
        ? (classLoading ? 'Loading…' : 'No classes scheduled today')
        : slotLabel(homeClass);
    final classCenter = homeClass == null
        ? 'Rest day'
        : '${homeClass['tCenterName'] ?? homeClass['centerName'] ?? ''}'.trim();
    // Once the schedule has loaded, a class row is authoritative. Do not put
    // MyInfo's general/default trainer beside a different class.
    final instructorName = homeClass == null
        ? ''
        : '${homeClass['instructorName'] ?? homeClass['trainerName'] ?? homeClass['trainer'] ?? ''}'.trim();
    // MyInfo has no student code; the login's `code` is it — unless it only repeats the reg no.
    final loginCode = userField('code');
    final selectedCode = '${info?['studentCode'] ?? info?['value'] ?? ''}'.trim();
    final studentCode = hasSelectedStudent
        ? selectedCode
        : (loginCode == '${info?['registrationNo'] ?? ''}'.trim() ? '' : loginCode);

    const white85 = Color(0xD9FFFFFF);

    Widget statCell(String value, String label) => Expanded(
          child: Column(children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: white85, fontSize: 10, letterSpacing: 0.5)),
          ]),
        );
    Widget statSep() => Container(width: 1, height: 36, color: const Color(0x40FFFFFF));

    // One rounded block from the status bar down. A square orange backing behind the rounded
    // gradient used to fill the bottom corners back in, so they looked square.
    final header = Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: Shadows.soft(c),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, 30),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              Expanded(
                child: Row(children: [
                  // Club logo with a status ring (green = active, red = inactive).
                  GestureDetector(
                    onTap: () => showStudentSwitcher(context),
                    child: Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x1FFFFFFF),
                        border: Border.all(
                            color: isActive ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5), width: 2.5),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.fromBorderSide(BorderSide(color: Color(0x99FFFFFF), width: 2)),
                        ),
                        child: MemberAvatar(name: name, url: UserSession.resolvePhotoUrl(userField('clubPic')), size: 48, radius: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Hello,', style: TextStyle(color: white85, fontSize: 12)),
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: const Color(0x38FFFFFF), borderRadius: BorderRadius.circular(10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Ion.shieldCheckmark, size: 12, color: Color(0xFFFFF7ED)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(clubName.isEmpty ? 'Member' : clubName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Color(0xFFFFF7ED),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3)),
                          ),
                        ]),
                      ),
                      if (status.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isActive ? const Color(0x4022C55E) : const Color(0x4DEF4444),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive ? const Color(0xFF4ADE80) : const Color(0xFFFCA5A5),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(isActive ? 'Active' : 'Inactive',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.3)),
                          ]),
                        ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              // Student's own photo; falls back to initials.
              MemberAvatar(
                name: name,
                url: session.studentPhoto,
                localPhoto: session.localPhotoB64,
                size: 36,
                radius: 10,
              ),
              const SizedBox(width: 10),
              Touchable(
                onPress: () => context.push('/notifications'),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(color: Color(0x38FFFFFF), shape: BoxShape.circle),
                      child: const Icon(Ion.notificationsOutline, size: 20, color: Colors.white),
                    ),
                    if (unread > 0)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: c.primary, width: 1.5),
                          ),
                          child: Text(unread > 99 ? '99+' : '$unread',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                        ),
                      ),
                  ]),
                ),
              ),
            ]),
          ),
          Container(
            margin: const EdgeInsets.only(top: 22),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(Radii.lg)),
            child: statsLoading
                ? const SkeletonStatRow()
                : statsFailed
                    // Never print "RM 0 / 0 invoices" for a request that failed.
                    ? Touchable(
                        onPress: _stats.reload,
                        activeOpacity: 0.8,
                        child: const Column(children: [
                          Icon(Ion.cloudOfflineOutline, size: 20, color: Color(0xFFFFF7ED)),
                          SizedBox(height: 2),
                          Text("Couldn't load · tap to retry",
                              style: TextStyle(color: white85, fontSize: 10, letterSpacing: 0.5)),
                        ]),
                      )
                    : IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          statCell('$invoiceCount', 'Invoices'),
                          statSep(),
                          statCell(beltShort, 'Current Grade'),
                          statSep(),
                          statCell(jsNum(dueAmount), 'Due (RM)'),
                        ]),
                      ),
          ),
        ]),
      ),
    );

    const topQuick = [
      (id: 'train', label: 'Training', icon: Ion.barbellOutline, route: '/training'),
      (id: 'att', label: 'Attendance', icon: Ion.checkmarkDoneCircle, route: '/attendance'),
      (id: 'tt', label: 'Timetable', icon: Ion.calendarOutline, route: '/schedule'),
      (id: 'id', label: 'Virtual ID', icon: Ion.cardOutline, route: '/profile'),
      (id: 'prof', label: 'Profile', icon: Ion.personCircleOutline, route: '/profile'),
    ];

    Widget sectionHead(String title, {String? link, VoidCallback? onLink}) => Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.xl, 24, Gaps.xl, 12),
          child: Row(children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
            ),
            if (link != null)
              Touchable(
                onPress: onLink,
                child: Text(link, style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
          ]),
        );

    return ColoredBox(
      color: c.background,
      child: Column(children: [
        header,
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _pullRefresh,
            child: ListView(
              padding: EdgeInsets.only(bottom: tabBarHeight + 24),
              children: [
                if (session.hasNewerVersion)
                  MaterialBanner(
                    content: Text('New version available (${session.latestStoreVersion})'),
                    actions: [
                      TextButton(onPressed: session.dismissStoreVersionBanner, child: const Text('Dismiss')),
                    ],
                  ),
                // Shortcuts as individual rounded cards. They used to sit in one panel pulled 20pt up
                // under the header, where the list viewport clipped its top edge flat.
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, 0),
                  child: Row(children: [
                    for (final (i, q) in topQuick.indexed) ...[
                      if (i > 0) const SizedBox(width: Gaps.sm),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: q.label,
                          excludeSemantics: true,
                          child: Touchable(
                            onPress: () => openRoute(context, q.route),
                            activeOpacity: 0.7,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
                              decoration: BoxDecoration(
                                color: c.surface,
                                borderRadius: BorderRadius.circular(Radii.lg),
                                boxShadow: Shadows.soft(c),
                                border: Border.all(color: c.isDark ? c.border : c.borderLight),
                              ),
                              child: Column(children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: c.primary.hexA(c.isDark ? '2E' : '17'),
                                    borderRadius: BorderRadius.circular(Radii.md),
                                  ),
                                  child: Icon(q.icon, size: 21, color: c.primary),
                                ),
                                // Scale a long label ("Attendance") down to fit rather than cutting it off.
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(q.label,
                                      maxLines: 1,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 11, color: c.textPrimary, fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ]),
                ),

                Padding(
                    padding: const EdgeInsets.fromLTRB(Gaps.xl, 18, Gaps.xl, 0),
                    child: Touchable(
                      onPress: () => context.go('/payments'),
                      activeOpacity: 0.9,
                      // Deep slate "balance card": the orange Pay Now is the one bright element on it,
                      // instead of pale peach on a pale page.
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.xl),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                          ),
                          boxShadow: Shadows.card(c),
                          border: c.isDark ? Border.all(color: const Color(0xFF334155)) : null,
                        ),
                        child: Stack(children: [
                          // Soft brand glow, decoration only.
                          Positioned(
                            right: -40,
                            top: -50,
                            child: IgnorePointer(
                              child: Container(
                                width: 160,
                                height: 160,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(colors: [c.primary.hexA('55'), c.primary.hexA('00')]),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(children: [
                              Container(
                                width: 44,
                                height: 44,
                                margin: const EdgeInsets.only(right: 14),
                                decoration: BoxDecoration(
                                  color: c.primary.hexA('26'),
                                  borderRadius: BorderRadius.circular(Radii.md),
                                ),
                                child: Icon(Ion.wallet, size: 22, color: c.primary),
                              ),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  const Text('FEES DUE',
                                      style: TextStyle(
                                          color: Color(0xFFFDBA74),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8)),
                                  if (_stats.loading)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary)),
                                    )
                                  else
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(statsFailed ? 'Unavailable' : 'RM ${localeNum(dueAmount)}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 24,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.3)),
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                        statsFailed
                                            ? 'Open payments to retry'
                                            : '$invoiceCount invoice${invoiceCount == 1 ? '' : 's'} pending',
                                        style: const TextStyle(
                                            color: Color(0xFFCBD5E1), fontSize: 12, fontWeight: FontWeight.w500)),
                                  ),
                                ]),
                              ),
                              Container(
                                constraints: const BoxConstraints(minHeight: 44),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                decoration: BoxDecoration(
                                  color: c.primary,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [BoxShadow(color: c.primary.hexA('66'), blurRadius: 14, offset: const Offset(0, 4))],
                                ),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text('Pay Now',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                                  SizedBox(width: 6),
                                  Icon(Ion.arrowForward, size: 15, color: Colors.white),
                                ]),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, 18, Gaps.xl, 0),
                  child: YourInfoCard(
                    info: info,
                    studentCode: studentCode,
                    activeStudentName: activeName,
                    loading: infoLoading,
                  ),
                ),

                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    sectionHead("Today's Class", link: 'See all', onLink: () => context.go('/schedule')),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
                      padding: const EdgeInsets.all(14),
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(Radii.lg),
                        boxShadow: Shadows.soft(c),
                        border: c.isDark ? Border.all(color: c.border) : null,
                      ),
                      child: Row(children: [
                        Container(
                          width: 4,
                          height: 50,
                          decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(2)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(classTime,
                                key: const Key('today-class-time'),
                                style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(classCenter.isEmpty ? 'Training Center' : classCenter,
                                key: const Key('today-class-center'),
                                style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('with ${instructorName.isEmpty ? 'your instructor' : instructorName}',
                                style: TextStyle(color: c.textSecondary, fontSize: 11)),
                          ]),
                        ),
                        const SizedBox(width: 14),
                        if (homeClass != null)
                          Touchable(
                            onPress: () => context.push('/qr-scan'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration:
                                  BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.sm)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Ion.qrCode, size: 14, color: c.primary),
                                const SizedBox(width: 4),
                                Text('Check In',
                                    style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 11)),
                              ]),
                            ),
                          ),
                      ]),
                    ),

                    sectionHead('Quick Access'),
                    QuickGrid(items: kStudentQuickCards),
                  ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// The student's main details — registration, training, grading, next tournament — as the
/// production home showed them. The React Native port had dropped the card (restored 2026-09-29).
///
/// Everything comes from `/Profile/MyInfo` except [studentCode], the login's `code`. MyInfo is
/// always the signed-in student, so when a guardian has switched to another child the card says
/// so instead of showing one child's details under another's name.
class YourInfoCard extends StatelessWidget {
  final Map<String, dynamic>? info;
  final String studentCode;
  final String activeStudentName;
  final bool loading;
  const YourInfoCard(
      {super.key, required this.info, required this.studentCode, this.activeStudentName = '', this.loading = false});

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
  static const _tabular = [FontFeature.tabularFigures()];

  /// "Today", "Tomorrow" or "in N days" for a day still ahead; null once it has passed.
  static String? _countdown(DateTime day) {
    final now = DateTime.now();
    final days = (DateTime(day.year, day.month, day.day).difference(DateTime(now.year, now.month, now.day)).inHours / 24)
        .round();
    if (days < 0) return null;
    return switch (days) { 0 => 'Today', 1 => 'Tomorrow', _ => 'in $days days' };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    // Small accent text: brand orange alone is under 4.5:1 on the light tints, so it goes deeper
    // in light mode — the same pairing as the FEES DUE label.
    final accentText = c.isDark ? c.primaryLight : const Color(0xFF9A3412);
    final iconTint = c.isDark ? c.primaryLight : c.primaryDark;
    final data = info;
    String field(String key) => '${data?[key] ?? ''}'.replaceAll('\r', '').trim();

    TextStyle labelStyle() =>
        TextStyle(fontSize: 11.5, color: c.textSecondary, fontWeight: FontWeight.w600, letterSpacing: 0.2);
    Widget valueText(String value, {double size = 14.5, bool tabular = false}) => Text(value.isEmpty ? '—' : value,
        style: TextStyle(
            fontSize: size,
            color: value.isEmpty ? c.textMuted : c.textPrimary,
            fontWeight: FontWeight.w800,
            height: 1.3,
            fontFeatures: tabular ? _tabular : null));

    Widget note(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 18, color: c.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.4))),
          ]),
        );

    Widget panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(12)}) => Container(
          padding: padding,
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.lg)),
          child: child,
        );

    Widget idCell(String label, String value) => MergeSemantics(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: labelStyle()),
            const SizedBox(height: 3),
            valueText(value, size: 15, tabular: true),
          ]),
        );

    Widget detail(IconData icon, String label, String value) => MergeSemantics(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: c.primary.hexA(c.isDark ? '26' : '14'), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 17, color: iconTint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: labelStyle()),
                  const SizedBox(height: 2),
                  valueText(value),
                ]),
              ),
            ]),
          ),
        );

    Widget statTile(Widget leading, String label, String value) => panel(
          child: MergeSemantics(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                leading,
                const SizedBox(width: 7),
                Expanded(child: Text(label, style: labelStyle())),
              ]),
              const SizedBox(height: 6),
              valueText(value, tabular: true),
            ]),
          ),
        );

    Widget tournament() {
      final name = field('tournamentName');
      final status = field('tournamentStatus');
      final start = DateTime.tryParse(field('tournamentDate'));
      final from = fmtDateGB(data?['tournamentDate']);
      final to = fmtDateGB(data?['tournamentToDate']);
      final when = to.isEmpty || to == from ? from : '$from – $to';
      final countdown = start == null ? null : _countdown(start);

      final chip = Container(
        width: 50,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: Shadows.soft(c),
          border: c.isDark ? Border.all(color: c.border) : null,
        ),
        child: start == null
            ? SizedBox(height: 56, child: Icon(Ion.trophyOutline, size: 22, color: iconTint))
            : Column(children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(gradient: LinearGradient(colors: c.gradient)),
                  child: Text(_months[start.month - 1],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Text('${start.day}',
                      style: TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary, fontFeatures: _tabular)),
                ),
              ]),
      );

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: c.gradientSoft, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.primary.hexA(c.isDark ? '40' : '33')),
        ),
        child: MergeSemantics(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            chip,
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Next Tournament',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, color: accentText)),
                const SizedBox(height: 3),
                if (name.isEmpty)
                  Text('No tournament scheduled yet',
                      style: TextStyle(fontSize: 14, color: c.textSecondary, fontWeight: FontWeight.w600, height: 1.3))
                else ...[
                  Text(name,
                      style: TextStyle(fontSize: 15, color: c.textPrimary, fontWeight: FontWeight.w800, height: 1.3)),
                  if (status.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(status, style: TextStyle(fontSize: 12, color: accentText, fontWeight: FontWeight.w800)),
                  ],
                  if (when.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(when,
                          style: TextStyle(
                              fontSize: 12.5,
                              color: c.textSecondary,
                              fontWeight: FontWeight.w600,
                              fontFeatures: _tabular)),
                      if (countdown != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              gradient: LinearGradient(colors: c.gradient), borderRadius: BorderRadius.circular(999)),
                          child: Text(countdown,
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                        ),
                    ]),
                  ],
                ],
              ]),
            ),
          ]),
        ),
      );
    }

    final other = activeStudentName.trim();
    final self = field('name');
    final List<Widget> body;
    if (other.isNotEmpty && self.isNotEmpty && other.toLowerCase() != self.toLowerCase()) {
      body = [
        note(Ion.informationCircleOutline,
            "$other's details aren't available here — the club system only sends the signed-in student's."),
      ];
    } else if (data == null) {
      body = [
        loading
            ? note(Ion.timeOutline, 'Loading your details…')
            : note(Ion.alertCircleOutline, "Couldn't load your details. Pull down to refresh."),
      ];
    } else {
      final grade = field('currentGrade');
      final belt = beltAccent(grade);
      body = [
        const SizedBox(height: 16),
        panel(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: idCell('Registration No', field('registrationNo'))),
              VerticalDivider(width: 24, thickness: 1, color: c.border),
              Expanded(child: idCell('Student Code', studentCode.trim())),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        detail(Ion.locationOutline, 'Training Centre', field('tCenterName')),
        detail(Ion.timeOutline, 'Training Time', field('trainingTme')),
        detail(Ion.schoolOutline, 'Exam Center', field('eCenterName')),
        detail(Ion.personOutline, 'Instructor Name', field('instructorName')),
        const SizedBox(height: 10),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: statTile(
                belt == null
                    ? Icon(Ion.ribbonOutline, size: 15, color: iconTint)
                    : Container(
                        width: 20,
                        height: 8,
                        decoration: BoxDecoration(
                          color: belt.color,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: c.textPrimary.withValues(alpha: 0.12)),
                        ),
                      ),
                'Current Grade',
                grade,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: statTile(Icon(Ion.calendarOutline, size: 15, color: iconTint), 'Last Grading Date',
                  fmtDateGB(data['lastGradingDate'])),
            ),
          ]),
        ),
        if (field('gradingStatus').isNotEmpty || field('gradingPaymentStatus').isNotEmpty) ...[
          const SizedBox(height: 4),
          detail(Ion.checkmarkCircleOutline, 'Grading Status',
              field('gradingStatus').isNotEmpty ? field('gradingStatus') : field('gradingPaymentStatus')),
        ],
        const SizedBox(height: 10),
        tournament(),
      ];
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.xl),
        boxShadow: Shadows.card(c),
        border: Border.all(color: c.isDark ? c.border : c.primary.hexA('1F')),
      ),
      child: Stack(children: [
        // Soft brand glow behind the header, decoration only — the Fees card's signature.
        Positioned(
          right: -50,
          top: -60,
          child: IgnorePointer(
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [c.primary.hexA(c.isDark ? '33' : '24'), c.primary.hexA('00')]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: c.primary.hexA('55'), blurRadius: 12, offset: const Offset(0, 4))],
                ),
                child: const Icon(Ion.idCardOutline, size: 20, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(
                    header: true,
                    child: Text('Your info',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: c.textPrimary)),
                  ),
                  const SizedBox(height: 1),
                  Text('Your club record', style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ]),
              ),
            ]),
            ...body,
          ]),
        ),
      ]),
    );
  }
}

/// The 4-per-row tile grid (`grid` / `gridCard` styles, width 23%, space-between).
class QuickGrid extends StatelessWidget {
  final List<QuickTile> items;
  const QuickGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
      child: LayoutBuilder(builder: (context, box) {
        final cardW = box.maxWidth * .23;
        final gap = (box.maxWidth - cardW * 4) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: 14,
          children: [
            for (final t in items)
              SizedBox(
                width: cardW,
                child: Touchable(
                  onPress: () => openRoute(context, t.route),
                  activeOpacity: 0.8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(Radii.lg),
                      boxShadow: Shadows.soft(c),
                      border: c.isDark ? Border.all(color: c.border) : null,
                    ),
                    child: Column(children: [
                      Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: t.color.hexA(c.isDark ? '33' : '18'),
                        ),
                        child: Icon(t.icon, size: 22, color: t.color),
                      ),
                      SizedBox(
                        height: 26,
                        child: Text(t.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 10, color: c.textPrimary, fontWeight: FontWeight.w600, height: 1.3)),
                      ),
                    ]),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

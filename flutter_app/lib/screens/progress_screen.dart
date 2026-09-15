import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/live_refresh.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../utils/progress_stats.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

const _monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// The student the member's token belongs to (never a picked sibling).
StudentIdentity sessionSelf(UserSession s) => StudentIdentity(
      name: '${s.myInfo?['name'] ?? s.authData?['name'] ?? ''}',
      ic: '${s.authData?['icNo'] ?? s.myInfo?['icNo'] ?? ''}',
    );

/// The sibling picked in the student switcher, if any. Switching is a client-side filter; the
/// token stays the guardian's.
StudentIdentity? sessionSelected(UserSession s) {
  final name = s.activeStudentName ?? '';
  return name.trim().isEmpty ? null : StudentIdentity(name: name);
}

/// Progress Report: attendance over a chosen period plus fixed recent activity.
/// Spec: docs/specs/2026-09-15-progress-belt-grading.md.
///
/// No grading section: `/Reports/GradingSchedule` returned empty for the test student
/// accounts, and the student Grading tile was removed.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with UseApi<ProgressScreen>, LiveRefreshMixin<ProgressScreen> {
  int _days = 90;
  late DateTime _fetchStart;
  late final _att = useApi(() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _fetchStart = progressFetchStart(today);
    return RnApi.attendanceReport({
      'fromDate': _fetchStart.toIso8601String(),
      'toDate': DateTime(today.year, today.month, today.day, 23, 59, 59).toIso8601String(),
    });
  });

  @override
  void initState() {
    super.initState();
    _att;
  }

  @override
  Future<void> refreshLiveData() => reloadAll(silent: true);

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = DateTime(today.year, today.month, today.day - _days + 1);

    Widget section(String t, [String? sub]) => Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
            if (sub != null) ...[
              const SizedBox(height: 2),
              Text(sub, style: TextStyle(fontSize: 11, color: c.textSecondary)),
            ],
          ]),
        );

    final children = <Widget>[
      Text(session.displayName, style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Row(children: [
        for (final d in const [30, 90, 365]) ...[
          if (d != 30) const SizedBox(width: 8),
          _pill(c, '$d days', _days == d, () => setState(() => _days = d)),
        ],
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 14),
        child: Text('${fmtDateGB(from.toIso8601String())} – ${fmtDateGB(today.toIso8601String())}',
            style: TextStyle(fontSize: 12, color: c.textSecondary)),
      ),
    ];

    if (_att.data == null && _att.loading) {
      children.add(const RnSpinner(vertical: 40));
    } else if (_att.data == null) {
      children.add(ErrorState(message: _att.error ?? "Couldn't load attendance.", onRetry: _att.reload));
    } else {
      final scoped = scopeStudentRows(
        _att.data!.cast<Map>(),
        self: sessionSelf(session),
        selected: sessionSelected(session),
      );
      if (_att.error != null) {
        children.add(_notice(c, Ion.cloudOfflineOutline, "Couldn't refresh. Showing the last loaded attendance."));
      }
      if (scoped.unavailable) {
        children.add(_notice(c, Ion.informationCircleOutline,
            "Attendance isn't available for ${session.displayName}. The report doesn't say which student each record belongs to."));
      } else {
        final period = countPeriod(scoped.rows, from: from, today: today);
        final recent = summarizeRecent(scoped.rows, now, fetchStart: _fetchStart);
        final invalid = invalidDateCount(scoped.rows);
        children.addAll([
          _hero(c, period),
          if (scoped.rows.isEmpty)
            _notice(
                c, Ion.calendarOutline, 'No attendance was returned for this student. Check in to a class to start.'),
          section('Recent activity', 'Not affected by the period above'),
          Row(children: [
            _stat(c,
                value: '${recent.thisMonthPresent}',
                label: 'This month',
                detail: '${_monthNames[recent.months[4].month.month - 1]}: ${recent.lastMonthPresent}'),
            const SizedBox(width: 10),
            _stat(c,
                value: '${recent.weekStreak}${recent.streakAtBoundary ? '+' : ''}',
                label: 'Week streak',
                detail: recent.streakAtBoundary ? 'At least ${recent.weekStreak} weeks' : 'Weeks in a row'),
            const SizedBox(width: 10),
            _stat(c,
                value: recent.lastPresent == null ? '—' : _shortDate(recent.lastPresent!),
                label: 'Last present',
                detail: recent.lastPresent == null ? '' : _daysAgo(recent.lastPresent!, today)),
          ]),
          section('Last 6 months', 'Present and absent sessions per month'),
          _card(c, child: _monthChart(c, recent.months)),
          if (invalid > 0)
            _notice(c, Ion.informationCircleOutline,
                '$invalid ${invalid == 1 ? 'record has' : 'records have'} no valid date and ${invalid == 1 ? 'is' : 'are'} not counted.'),
        ]);
      }
      children.addAll([
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: _link(c, Ion.checkmarkDoneCircle, 'Attendance', () => context.push('/attendance'))),
          const SizedBox(width: 10),
          Expanded(child: _link(c, Ion.ribbon, 'Belt / Rank', () => context.push('/belt-rank'))),
        ]),
      ]);
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'Progress Report', horizontal: Gaps.lg),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _att.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, 120),
              children: children,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _pill(AppColors c, String label, bool active, VoidCallback onTap) => Touchable(
        activeOpacity: 0.8,
        onPress: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? c.primary : c.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.xl),
            border: Border.all(color: active ? c.primary : c.border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? Colors.white : c.textSecondary)),
        ),
      );

  Widget _hero(AppColors c, PeriodCounts p) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(Radii.xxl),
          boxShadow: Shadows.strong(c),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ATTENDANCE RATE',
                  style: TextStyle(
                      color: Color(0xFFFFF7ED), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 4),
              Text(p.rate == null ? '—' : '${p.rate}%',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800, letterSpacing: -1)),
              const SizedBox(height: 2),
              Text('${p.present} present · ${p.absent} absent · ${p.other} other',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12)),
            ]),
          ),
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(color: Color(0x2EFFFFFF), shape: BoxShape.circle),
            child: const Icon(Ion.trendingUp, size: 40, color: Color(0xE6FFFFFF)),
          ),
        ]),
      );

  Widget _card(AppColors c, {required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: rnCard(c, radius: Radii.xl),
        child: child,
      );

  Widget _notice(AppColors c, IconData icon, String text) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: rnCard(c),
        child: Row(children: [
          Icon(icon, size: 18, color: c.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.textPrimary, height: 18 / 13))),
        ]),
      );

  Widget _stat(AppColors c, {required String value, required String label, required String detail}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: rnCard(c, radius: Radii.lg),
          child: Column(children: [
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: c.primary, fontWeight: FontWeight.w700)),
          ]),
        ),
      );

  Widget _link(AppColors c, IconData icon, String label, VoidCallback onTap) => Touchable(
        activeOpacity: 0.8,
        onPress: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: rnCard(c, radius: Radii.lg),
          child: Row(children: [
            Icon(icon, size: 18, color: c.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
            ),
            Icon(Ion.chevronForward, size: 14, color: c.textMuted),
          ]),
        ),
      );

  Widget _monthChart(AppColors c, List<MonthAttendance> months) {
    const barHeight = 110.0;
    final maxMarked = months.fold<int>(0, (m, x) => x.present + x.absent > m ? x.present + x.absent : m);
    final absentColor = c.primary.hexA('30');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: barHeight + 20,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final m in months)
            Expanded(
              child: Semantics(
                label: '${_monthNames[m.month.month - 1]}: ${m.present} present, ${m.absent} absent',
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('${m.present}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textPrimary)),
                  const SizedBox(height: 4),
                  Container(
                    width: 22,
                    height: maxMarked == 0 ? 0 : (m.present + m.absent) / maxMarked * barHeight,
                    alignment: Alignment.bottomCenter,
                    decoration: BoxDecoration(color: absentColor, borderRadius: BorderRadius.circular(6)),
                    child: Container(
                      height: maxMarked == 0 ? 0 : m.present / maxMarked * barHeight,
                      decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        for (final m in months)
          Expanded(
            child: Text(_monthNames[m.month.month - 1],
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
          ),
      ]),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _legend(c, c.primary, 'Present'),
        const SizedBox(width: 16),
        _legend(c, absentColor, 'Absent'),
      ]),
    ]);
  }

  Widget _legend(AppColors c, Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: c.textSecondary)),
      ]);

  String _shortDate(DateTime d) => '${d.day} ${_monthNames[d.month - 1]}';

  String _daysAgo(DateTime d, DateTime today) {
    final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }
}

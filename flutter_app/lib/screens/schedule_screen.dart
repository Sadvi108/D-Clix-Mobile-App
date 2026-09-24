import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/live_refresh.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
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

String _dowFullOf(DateTime d) => _dowFull[d.weekday % 7];

/// Port of `frontend/app/(tabs)/schedule.tsx` (Expo v2.11.1).
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with UseApi<ScheduleScreen>, LiveRefreshMixin<ScheduleScreen> {
  final _range = RnApi.defaultRange();
  late final _details =
      useApi(() => RnApi.studentDetails({'fromDate': _range.fromDate, 'toDate': _range.toDate}));
  int _active = 0;

  // 10 days starting today
  late final List<DateTime> _days = () {
    final base = DateTime.now();
    return List.generate(10, (i) => DateTime(base.year, base.month, base.day + i));
  }();

  @override
  void initState() {
    super.initState();
    _details;
  }

  @override
  Future<void> refreshLiveData() => reloadAll(silent: true);

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final top = MediaQuery.paddingOf(context).top;
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;

    final selected = _days[_active];
    final selectedDow = _dowFullOf(selected);
    final monthLabel = DateFormat('MMM yyyy').format(_days[0]);

    // Report routes can return the whole branch for a student token — keep own rows only.
    final rows = session.scopedRows(_details.data).whereType<Map>().toList();
    final classes =
        rows.where((r) => '${r['dayOfWeek'] ?? ''}'.toLowerCase() == selectedDow.toLowerCase()).toList();
    final trainingDows = rows.map((r) => '${r['dayOfWeek'] ?? ''}'.toLowerCase()).toSet();

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
        child: Text('${classes.length} session${classes.length > 1 ? 's' : ''} · $selectedDow',
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
                  Text(monthLabel, style: TextStyle(color: c.textSecondary, fontSize: 13)),
                ]),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(kLogoAssetPath, width: 40, height: 40),
              ),
            ]),
          ),
          SizedBox(
            height: 108,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl, vertical: 12),
              clipBehavior: Clip.none,
              itemCount: _days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final d = _days[i];
                final on = i == _active;
                final hasTraining = trainingDows.contains(_dowFullOf(d).toLowerCase());
                return Semantics(
                  selected: on,
                  button: true,
                  child: Touchable(
                    onPress: () => setState(() => _active = i),
                    activeOpacity: 0.85,
                    child: Container(
                      width: 62,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: on ? c.primary : c.surface,
                        borderRadius: BorderRadius.circular(Radii.lg),
                        boxShadow: Shadows.soft(c),
                        border: c.isDark ? Border.all(color: on ? c.primary : c.border) : null,
                      ),
                      child: Column(children: [
                        Text(_dowShort[d.weekday % 7],
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: on ? const Color(0xD9FFFFFF) : c.textSecondary)),
                        const SizedBox(height: 4),
                        Text('${d.day}',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800, color: on ? Colors.white : c.textPrimary)),
                        if (hasTraining)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.only(top: 6),
                            decoration:
                                BoxDecoration(shape: BoxShape.circle, color: on ? Colors.white : c.primary),
                          ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: c.primary,
              onRefresh: reloadAll,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                // clearance = tab bar + floating Book button zone
                padding: EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, tabBarHeight + 92),
                children: body,
              ),
            ),
          ),
        ]),
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

String _str(dynamic v, [String fallback = '—']) {
  final s = '${v ?? ''}';
  return s.isEmpty ? fallback : s;
}

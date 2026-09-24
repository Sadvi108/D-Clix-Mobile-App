import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/live_refresh.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// Port of `frontend/app/(tabs)/training.tsx` (Expo v2.11.1).
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});
  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen>
    with UseApi<TrainingScreen>, LiveRefreshMixin<TrainingScreen> {
  final _range = RnApi.defaultRange();
  late final _info = useApi(RnApi.myInfo);
  late final _att =
      useApi(() => RnApi.attendanceReport({'fromDate': _range.fromDate, 'toDate': _range.toDate}));

  @override
  void initState() {
    super.initState();
    _info;
    _att;
  }

  @override
  Future<void> refreshLiveData() => reloadAll(silent: true);

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final user = session.authData ?? const <String, dynamic>{};
    final top = MediaQuery.paddingOf(context).top;
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;

    final records = session.scopedRows(_att.data).whereType<Map>().toList();
    final present =
        records.where((r) => RegExp('present', caseSensitive: false).hasMatch('${r['attendanceType'] ?? ''}')).length;

    final infoGrade = '${_info.data?['currentGrade'] ?? ''}';
    final userGrade = '${user['currentGrade'] ?? ''}';
    final grade = infoGrade.isNotEmpty ? infoGrade : (userGrade.isNotEmpty ? userGrade : '—');
    final gradeNum = int.tryParse(RegExp(r'Grade\s*(\d+)', caseSensitive: false).firstMatch(grade)?.group(1) ?? '');
    final beltName = RegExp(r'\(([^)]+)\)').firstMatch(grade)?.group(1) ?? grade;
    final progress = gradeNum != null ? (((10 - gradeNum) / 10) * 100).round().clamp(8, 100) : 50;
    final accent = c.primary;
    final tCenterName = '${_info.data?['tCenterName'] ?? ''}';
    final clubName = '${user['clubName'] ?? ''}';
    final instructorName = '${_info.data?['instructorName'] ?? ''}';

    Widget heroStat(String n, String l) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration:
                BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(Radii.md)),
            child: Column(children: [
              Text(n,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(l, style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 10)),
            ]),
          ),
        );

    Widget spinner(Color color, {double vertical = 24, bool start = false}) => Padding(
          padding: EdgeInsets.symmetric(vertical: vertical),
          child: Align(
            alignment: start ? Alignment.centerLeft : Alignment.center,
            child: SizedBox(
                width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: color)),
          ),
        );

    return ColoredBox(
      color: c.background,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Gaps.xl, top + 14, Gaps.xl, 14),
          child: Row(children: [
            const TabRootBackButton(),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Training',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.textPrimary)),
                const SizedBox(height: 2),
                Text(
                    tCenterName.isNotEmpty
                        ? tCenterName
                        : (clubName.isNotEmpty ? clubName : 'Keep pushing!'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textSecondary, fontSize: 12)),
              ]),
            ),
            const SizedBox(width: Gaps.md),
            Touchable(
              onPress: _att.reload,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                child: Icon(Ion.refresh, size: 20, color: c.primary),
              ),
            ),
          ]),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, tabBarHeight + 24),
            children: [
              Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient:
                      LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(Radii.xl),
                  boxShadow: Shadows.strong(c),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    Icon(Ion.trophy, size: 22, color: Color(0xFFFFF7ED)),
                    SizedBox(width: 8),
                    Text('SESSIONS ATTENDED',
                        style: TextStyle(
                            color: Color(0xFFFFF7ED), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  ]),
                  if (_att.loading)
                    spinner(Colors.white, vertical: 12, start: true)
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text.rich(TextSpan(
                        text: '$present ',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1),
                        children: const [
                          TextSpan(
                              text: 'classes',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500, color: Color(0xCCFFFFFF), letterSpacing: 0)),
                        ],
                      )),
                    ),
                  const SizedBox(height: 2),
                  const Text('Train consistently to advance your grade 🔥',
                      style: TextStyle(color: Color(0xE6FFFFFF), fontSize: 12)),
                  const SizedBox(height: 16),
                  Row(children: [
                    heroStat('${records.length}', 'Recorded'),
                    const SizedBox(width: 12),
                    heroStat(beltName, 'Belt'),
                    const SizedBox(width: 12),
                    heroStat('1', 'Program'),
                  ]),
                ]),
              ),

              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text('Enrolled Program',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
              ),

              if (_info.loading)
                spinner(c.primary)
              else
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Radii.xl),
                    boxShadow: Shadows.card(c),
                    border: c.isDark ? Border.all(color: c.border) : null,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                            colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Ion.medal, size: 40, color: Color(0xFFFFF7ED)),
                        const SizedBox(height: 8),
                        Text(clubName.isEmpty ? 'Martial Arts' : clubName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(
                            child: Text(tCenterName.isEmpty ? 'Training' : tCenterName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
                          ),
                          const SizedBox(width: Gaps.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: accent.hexA(c.isDark ? '33' : '18'),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(beltName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Ion.personCircleOutline, size: 16, color: c.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(instructorName.isEmpty ? 'Instructor' : instructorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                            child: Text('Current grade: $grade',
                                style:
                                    TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                          Text('$progress%',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: accent)),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            height: 8,
                            color: c.surfaceAlt,
                            alignment: Alignment.centerLeft,
                            child: FractionallySizedBox(
                              widthFactor: progress / 100,
                              heightFactor: 1,
                              child: Container(
                                decoration:
                                    BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Expanded(
                              child: Touchable(
                                onPress: () => context.push('/attendance'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                      color: c.primary, borderRadius: BorderRadius.circular(Radii.md)),
                                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(Ion.checkmarkDone, size: 14, color: Colors.white),
                                    SizedBox(width: 6),
                                    Text('View Attendance',
                                        style: TextStyle(
                                            color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                                  ]),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Touchable(
                              onPress: () => context.go('/progress'),
                              child: Container(
                                width: 44,
                                decoration: BoxDecoration(
                                    color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
                                child: Icon(Ion.trendingUp, size: 18, color: c.textSecondary),
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

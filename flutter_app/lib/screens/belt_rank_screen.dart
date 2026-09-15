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
import 'progress_screen.dart' show sessionSelected, sessionSelf;

/// The student's recorded grade, exactly as the academy wrote it.
/// Spec: docs/specs/2026-09-15-progress-belt-grading.md.
///
/// `/Profile/MyInfo.currentGrade` is the only grade data the API has: no grade list, promotion
/// history or eligibility. So there is no belt journey or "next belt" here; clubs use
/// sub-ranks such as "Green 2" and their own orders.
class BeltRankScreen extends StatefulWidget {
  const BeltRankScreen({super.key});
  @override
  State<BeltRankScreen> createState() => _BeltRankScreenState();
}

class _BeltRankScreenState extends State<BeltRankScreen> with UseApi<BeltRankScreen>, LiveRefreshMixin<BeltRankScreen> {
  late final _info = useApi(RnApi.myInfo);

  @override
  void initState() {
    super.initState();
    _info;
  }

  @override
  Future<void> refreshLiveData() => reloadAll(silent: true);

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final self = sessionSelf(session);
    final selected = sessionSelected(session);
    final isSibling = selected != null && !selected.sameAs(self);

    // MyInfo always describes the token's own student. A successful response is the truth,
    // even with an empty grade; the session cache stands in only while that request is
    // pending or failed, and never for a sibling.
    final fetched = _info.data;
    Map<String, dynamic>? info;
    if (fetched != null) {
      final who = StudentIdentity(name: '${fetched['name'] ?? ''}', ic: '${fetched['icNo'] ?? ''}');
      if (!isSibling || who.sameAs(selected)) info = fetched;
    } else if (!isSibling) {
      info = session.myInfo;
    }
    final grade = '${info?['currentGrade'] ?? ''}'.trim();
    final accent = beltAccent(grade);

    final children = <Widget>[
      Text(session.displayName, style: TextStyle(fontSize: 13, color: c.textSecondary, fontWeight: FontWeight.w600)),
      const SizedBox(height: 14),
    ];

    if (isSibling && info == null && fetched != null) {
      children.add(_note(c, Ion.informationCircleOutline,
          "A grade isn't available for ${session.displayName} here. Contact your academy to confirm their rank."));
    } else if (info == null && _info.loading) {
      children.add(const RnSpinner(vertical: 40));
    } else if (info == null) {
      children.add(ErrorState(message: _info.error ?? "Couldn't load the grade.", onRetry: _info.reload));
    } else {
      if (_info.error != null) {
        children.add(_note(c, Ion.cloudOfflineOutline, "Couldn't refresh. Showing the last loaded grade."));
      }
      children.add(Container(
        margin: EdgeInsets.only(top: _info.error != null ? 12 : 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(Radii.xxl),
          boxShadow: Shadows.strong(c),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('CURRENT BELT / RANK',
                  style: TextStyle(
                      color: Color(0xFFFFF7ED), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text(grade.isEmpty ? 'Not recorded' : grade,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.15)),
            ]),
          ),
          const SizedBox(width: 12),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0x2EFFFFFF),
              shape: BoxShape.circle,
              border: accent == null ? null : Border.all(color: accent.color, width: 3),
            ),
            child: Icon(Ion.ribbon, size: 40, color: accent?.color ?? const Color(0xE6FFFFFF)),
          ),
        ]),
      ));
      if (grade.isEmpty) {
        children.add(_note(c, Ion.informationCircleOutline,
            'No grade is recorded for this student yet. Contact your academy if that looks wrong.'));
      }
      final centre = '${info['tCenterName'] ?? ''}'.trim();
      final instructor = '${info['instructorName'] ?? ''}'.trim();
      if (centre.isNotEmpty || instructor.isNotEmpty) {
        children.add(Container(
          margin: const EdgeInsets.only(top: 14),
          padding: const EdgeInsets.all(16),
          decoration: rnCard(c, radius: Radii.xl),
          child: Column(children: [
            if (centre.isNotEmpty) _detail(c, Ion.locationOutline, 'Training centre', centre),
            if (centre.isNotEmpty && instructor.isNotEmpty) Divider(height: 20, color: c.borderLight),
            if (instructor.isNotEmpty) _detail(c, Ion.personCircleOutline, 'Instructor', instructor),
          ]),
        ));
      }
      children.addAll([
        _note(c, Ion.schoolOutline, 'Ask your instructor about your next rank and what it takes to get there.'),
        _note(c, Ion.trendingUp, 'See your attendance in Progress Report', onTap: () => context.go('/progress')),
      ]);
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'Belt / Rank', horizontal: Gaps.lg),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _info.reload,
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

  Widget _detail(AppColors c, IconData icon, String label, String value) => Row(children: [
        Icon(icon, size: 18, color: c.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                style:
                    TextStyle(fontSize: 10, color: c.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 14, color: c.textPrimary, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]);

  Widget _note(AppColors c, IconData icon, String text, {VoidCallback? onTap}) {
    final card = Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: rnCard(c),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
          child: Icon(icon, size: 16, color: c.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 13, color: c.textPrimary, fontWeight: FontWeight.w500, height: 18 / 13)),
        ),
        if (onTap != null) Icon(Ion.chevronForward, size: 16, color: c.textMuted),
      ]),
    );
    return onTap == null ? card : Touchable(activeOpacity: 0.8, onPress: onTap, child: card);
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_version.dart';
import '../services/api.dart';
import '../services/live_refresh.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../theme/theme_provider.dart';
import '../utils/qr_content.dart';
import '../widgets/member_avatar.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// Icon for a MyClubStats row by its label (`statIcon` in profile.tsx).
IconData _statIcon(String text) {
  final t = text.toLowerCase();
  if (t.contains('student')) return Ion.people;
  if (t.contains('training')) return Ion.time;
  if (t.contains('grading')) return Ion.ribbon;
  if (t.contains('tournament')) return Ion.trophy;
  if (t.contains('slip')) return Ion.receipt;
  if (t.contains('payment')) return Ion.card;
  if (t.contains('purchase')) return Ion.bagHandle;
  if (t.contains('whatsapp')) return Ion.logoWhatsapp;
  if (t.contains('registration')) return Ion.personAdd;
  return Ion.statsChart;
}

/// Port of `frontend/app/(tabs)/profile.tsx` (Expo v2.11.1).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with UseApi<ProfileScreen>, LiveRefreshMixin<ProfileScreen> {
  final _isInstructor = UserSession.instance.isInstructor;
  late final _info = useApi(RnApi.myInfo);
  late final _siblings = useApi<List<Map<String, dynamic>>>(
      () async => _isInstructor ? <Map<String, dynamic>>[] : await RnApi.mySiblings());
  late final _clubStats = useApi<List<Map<String, dynamic>>>(
      () async => _isInstructor ? await RnApi.myClubStats() : <Map<String, dynamic>>[]);
  late final _branches = useApi<List<Map<String, dynamic>>>(() async {
    final code = '${UserSession.instance.authData?['clubCode'] ?? ''}';
    if (!_isInstructor || code.isEmpty) return <Map<String, dynamic>>[];
    final resp = await Api.accountGetBranchesByClubCode(code);
    return ((resp is Map ? resp['data'] : resp) as List? ?? const [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  });

  @override
  void initState() {
    super.initState();
    _info;
    _siblings;
    _clubStats;
    _branches;
  }

  @override
  Future<void> refreshLiveData() => reloadAll(silent: true);

  Future<void> _onLogout() async {
    final ok = await confirmDialog(context, 'Logout',
        message: 'Are you sure you want to logout?', confirmLabel: 'Logout', destructive: true);
    if (!ok || !mounted) return;
    UserSession.instance.logout();
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final theme = context.watch<ThemeProvider>();
    final session = context.watch<UserSession>();
    final user = session.authData ?? const <String, dynamic>{};
    String u(String k) => '${user[k] ?? ''}'.trim();
    final isInstructor = session.isInstructor;
    final top = MediaQuery.paddingOf(context).top;
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;

    // A guardian can narrow the app to one sibling; show who is active.
    final name = (session.activeStudentName?.isNotEmpty ?? false) ? session.activeStudentName! : u('name');
    final infoGrade = '${_info.data?['currentGrade'] ?? ''}';
    final grade = infoGrade.isNotEmpty ? infoGrade : (u('currentGrade').isNotEmpty ? u('currentGrade') : '—');
    final clubList = (user['clubList'] as List? ?? const []).whereType<Map>().toList();
    final clubName = u('clubName').isNotEmpty
        ? u('clubName')
        : (clubList.isNotEmpty ? '${clubList.first['text'] ?? '—'}' : '—');
    final code = u('code').isNotEmpty ? u('code') : u('icNo');

    // A student's QR encodes `ST-` + id padded to 8 digits; instructors keep the bare id.
    final qrContent = isInstructor
        ? (u('id').isEmpty ? null : u('id'))
        : (QrContent.studentFromRaw(session.currentStudentId ?? user['id']));

    final branchIds = (user['branchIds'] as List? ?? const []).map((e) => '$e').toSet();
    final myBranches = (_branches.data ?? const []).where((b) => branchIds.contains('${b['id']}')).toList();
    final stats = [...?_clubStats.data]
      ..sort((a, b) => RnApi.number(a['value']).compareTo(RnApi.number(b['value'])));

    final eCenter = '${_info.data?['eCenterName'] ?? ''}';
    final tCenter = '${_info.data?['tCenterName'] ?? ''}';
    final regNo = '${_info.data?['registrationNo'] ?? ''}';
    final personalFields = [
      (icon: Ion.pulseOutline, label: 'Account Status', value: u('status').isEmpty ? '—' : u('status')),
      (icon: Ion.callOutline, label: 'Phone', value: u('handPhone').isEmpty ? '—' : u('handPhone')),
      (icon: Ion.ribbonOutline, label: 'Belt / Grade', value: grade),
      (icon: Ion.businessOutline, label: 'Center', value: eCenter.isNotEmpty ? eCenter : (tCenter.isNotEmpty ? tCenter : '—')),
      (icon: Ion.cardOutline, label: 'Registration No', value: regNo.isEmpty ? '—' : regNo),
    ].where((f) => f.value != '—' || f.label == 'Phone' || f.label == 'Belt / Grade').toList();

    BoxDecoration cardDeco(double r) => BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(r),
          boxShadow: Shadows.soft(c),
          border: c.isDark ? Border.all(color: c.border) : null,
        );

    Widget circleIcon(IconData icon, double size, double iconSize, {Color? bg}) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: bg ?? c.surfaceAlt, shape: BoxShape.circle),
          child: Icon(icon, size: iconSize, color: c.primary),
        );

    Widget badge(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12)),
          child: Text(text, style: TextStyle(color: c.primary, fontSize: 11, fontWeight: FontWeight.w800)),
        );

    Widget card({required Widget child}) => Container(
          margin: const EdgeInsets.fromLTRB(Gaps.xl, 14, Gaps.xl, 0),
          padding: const EdgeInsets.all(16),
          decoration: cardDeco(Radii.xl),
          child: child,
        );

    Widget cardHead(IconData icon, String title, Widget? trailing) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            circleIcon(icon, 38, 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
            ),
            if (trailing != null) trailing,
          ]),
        );

    Widget dualCard(IconData icon, String label, String value, VoidCallback onTap) => Expanded(
          child: Touchable(
            onPress: onTap,
            activeOpacity: 0.85,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: cardDeco(Radii.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  circleIcon(icon, 36, 18),
                  const Spacer(),
                  Icon(Ion.chevronExpand, size: 16, color: c.textMuted),
                ]),
                const SizedBox(height: 12),
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                const SizedBox(height: 3),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textPrimary, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        );

    final rowsDef = isInstructor
        ? [
            (id: 'branch', icon: Ion.gitBranchOutline, label: 'Switch Branch', route: ''),
            (id: 'help', icon: Ion.headsetOutline, label: 'Help Desk', route: '/helpdesk'),
            (id: 'guide', icon: Ion.bookOutline, label: 'User Guide', route: '/user-guide'),
          ]
        : [
            (id: 'scan', icon: Ion.qrCodeOutline, label: 'Scan QR to Check In', route: '/qr-scan'),
            (id: 'help', icon: Ion.headsetOutline, label: 'Help Desk', route: '/helpdesk'),
            (id: 'details', icon: Ion.idCardOutline, label: 'Student Details', route: '/student-details'),
            (id: 'purchases', icon: Ion.bagHandleOutline, label: 'My Purchases', route: '/purchases'),
            (id: 'guide', icon: Ion.bookOutline, label: 'User Guide', route: '/user-guide'),
          ];

    return ColoredBox(
      color: c.background,
      child: ListView(
        padding: EdgeInsets.only(bottom: tabBarHeight + 24),
        children: [
          // Gradient header
          // One rounded block from the status bar down; a square orange backing used to fill the
          // rounded bottom corners back in.
          Container(
            padding: EdgeInsets.only(top: top),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              boxShadow: Shadows.soft(c),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, 56),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    const Expanded(
                      child: Text('My Profile',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    ),
                    Touchable(
                      onPress: () => context.push('/edit-profile'),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(color: Color(0x38FFFFFF), shape: BoxShape.circle),
                        child: const Icon(Ion.pencil, size: 18, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x8CFFFFFF), width: 2),
                  ),
                  child: _ProfilePhoto(
                    url: session.studentPhoto,
                    localPhoto: session.localPhotoB64,
                    icon: isInstructor ? Ion.school : Ion.person,
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(name.isEmpty ? 'Member' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 4),
                Text(code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 13)),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .9 - Gaps.xl * 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0x38FFFFFF), borderRadius: BorderRadius.circular(16)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(isInstructor ? Ion.school : Ion.shieldCheckmark, size: 14, color: const Color(0xFFFFF7ED)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(isInstructor ? 'Instructor · $clubName' : clubName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFFFF7ED), fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),

          // Virtual ID with QR (staff ID for instructors)
          Transform.translate(
            offset: const Offset(0, -34),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
              padding: const EdgeInsets.all(18),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(Radii.xl),
                boxShadow: Shadows.shade(c),
                border: c.isDark ? Border.all(color: c.border) : null,
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.asset(kLogoAssetPath, width: 24, height: 24),
                      ),
                      const SizedBox(width: 8),
                      Text('D-CLIX',
                          style: TextStyle(
                              color: c.primary, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2)),
                    ]),
                    const SizedBox(height: 10),
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text('· $grade',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.textSecondary, fontSize: 13)),
                    const SizedBox(height: 10),
                    Text(code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  ]),
                ),
                const SizedBox(width: 14),
                _VirtualIdQr(content: qrContent),
              ]),
            ),
          ),

          Transform.translate(
            offset: const Offset(0, -34),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              // ── Instructor: Club Overview dashboard ──
              if (isInstructor)
                card(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    cardHead(Ion.speedometer, 'Club Overview', _clubStats.loading ? badge('…') : null),
                    if (_clubStats.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(_clubStats.error!, style: TextStyle(color: c.danger, fontSize: 13)),
                      ),
                    const SizedBox(height: 6),
                    LayoutBuilder(builder: (context, box) {
                      final w = box.maxWidth * .47;
                      return Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final s in stats)
                          Container(
                            width: w,
                            padding: const EdgeInsets.all(12),
                            decoration:
                                BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 30,
                                height: 30,
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                                child: Icon(_statIcon('${s['text'] ?? ''}'), size: 16, color: c.primary),
                              ),
                              Text('${s['id'] ?? ''}',
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.textPrimary)),
                              const SizedBox(height: 2),
                              Text('${s['text'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                      ]);
                    }),
                  ]),
                ),

              // ── Instructor: Branches ──
              if (isInstructor)
                card(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    cardHead(Ion.business, 'Branches',
                        badge('${myBranches.isNotEmpty ? myBranches.length : branchIds.length}')),
                    if (_branches.loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('Loading branches…', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                      ),
                    if (!_branches.loading && myBranches.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                            branchIds.isNotEmpty ? '${branchIds.length} assigned branch(es)' : 'No branches assigned.',
                            style: TextStyle(color: c.textSecondary, fontSize: 13)),
                      ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final b in myBranches)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(999)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Ion.location, size: 12, color: c.primary),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text('${b['text'] ?? ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.textPrimary)),
                            ),
                          ]),
                        ),
                    ]),
                  ]),
                ),

              // ── Student: Active Student + Club switchers ──
              if (!isInstructor)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, 14, Gaps.xl, 0),
                  child: IntrinsicHeight(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      dualCard(Ion.swapHorizontal, 'ACTIVE STUDENT', name, () => _showPicker(
                            title: 'Switch Student',
                            items: [
                              for (final s in _siblings.data ?? const <Map<String, dynamic>>[])
                                (
                                  id: s['id'],
                                  label: '${s['text'] ?? ''}',
                                  active: (session.activeStudentName?.isNotEmpty ?? false)
                                      ? '${s['text']}' == session.activeStudentName
                                      : '${s['id']}' == u('id'),
                                ),
                            ],
                            onPick: (it) => session.switchStudent(it.id ?? 0, studentName: it.label),
                          )),
                      const SizedBox(width: 12),
                      dualCard(Ion.business, 'CLUB', clubName, () => _showPicker(
                            title: 'Switch Club',
                            items: [
                              for (final cl in clubList)
                                (id: cl['id'], label: '${cl['text'] ?? ''}', active: '${cl['id']}' == u('clubId')),
                            ],
                          )),
                    ]),
                  ),
                ),

              // Personal Info
              card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  cardHead(Ion.idCard, 'Personal Info', badge('${personalFields.length} fields')),
                  for (var i = 0; i < personalFields.length; i++) ...[
                    if (i > 0) Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 2), color: c.border),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        circleIcon(personalFields[i].icon, 38, 18),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(personalFields[i].label,
                                style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 1),
                            Text(personalFields[i].value,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 15, color: c.textPrimary, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),

              // Light / Dark Mode
              card(
                child: Row(children: [
                  circleIcon(theme.isDark ? Ion.moon : Ion.sunny, 42, 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(theme.isDark ? 'Dark Mode' : 'Light Mode',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.textPrimary)),
                      const SizedBox(height: 2),
                      Text(theme.isDark ? 'Orange & black' : 'Orange & white',
                          style: TextStyle(fontSize: 12, color: c.textSecondary)),
                    ]),
                  ),
                  Switch.adaptive(
                    value: theme.isDark,
                    onChanged: (_) => theme.toggle(),
                    activeTrackColor: c.primary,
                    inactiveTrackColor: c.border,
                    thumbColor: const WidgetStatePropertyAll(Colors.white),
                    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                  ),
                ]),
              ),

              // Action rows
              for (final r in rowsDef)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 0),
                  child: Touchable(
                    onPress: r.id == 'branch'
                        ? () => _showPicker(
                              title: 'Switch Branch',
                              items: [
                                for (final b in _branches.data ?? const <Map<String, dynamic>>[])
                                  (id: b['id'], label: '${b['text'] ?? ''}', active: '${b['id']}' == u('branchId')),
                              ],
                              onPick: (it) async {
                                final ok = await session.switchBranch(it.id ?? 0, clubCode: u('clubCode'));
                                if (!mounted) return;
                                notify(context, ok ? 'Switched to ${it.label}' : 'Switch failed',
                                    ok ? null : (session.error ?? 'Unknown error'));
                              },
                            )
                        : () => context.push(r.route),
                    activeOpacity: 0.85,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: cardDeco(Radii.lg),
                      child: Row(children: [
                        circleIcon(r.icon, 40, 20),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(r.label,
                              style: TextStyle(fontSize: 16, color: c.textPrimary, fontWeight: FontWeight.w700)),
                        ),
                        Icon(Ion.chevronForward, size: 18, color: c.textMuted),
                      ]),
                    ),
                  ),
                ),

              const SizedBox(height: 20),
              Center(
                child: Touchable(
                  onPress: _onLogout,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Ion.logOutOutline, size: 18, color: c.danger),
                      const SizedBox(width: 8),
                      Text('Logout', style: TextStyle(color: c.danger, fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text('D-Clix · v$kAppVersion',
                  textAlign: TextAlign.center, style: TextStyle(color: c.textMuted, fontSize: 11)),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _showPicker({
    required String title,
    required List<({Object? id, String label, bool active})> items,
    void Function(({Object? id, String label, bool active}) item)? onPick,
  }) {
    final c = context.appColors;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: c.overlay,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * .8),
        padding: EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 20 + MediaQuery.paddingOf(ctx).bottom),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Nothing to switch to.',
                  textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 14)),
            ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final it in items)
                Touchable(
                  onPress: onPick == null
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          onPick(it);
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
                    child: Row(children: [
                      Icon(it.active ? Ion.radioButtonOn : Ion.radioButtonOff,
                          size: 20, color: it.active ? c.primary : c.textMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(it.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      if (it.active)
                        Text('Active', style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// 104px photo with the RN translucent fallback disc + icon.
class _ProfilePhoto extends StatelessWidget {
  final String url;
  final String localPhoto;
  final IconData icon;
  const _ProfilePhoto({required this.url, required this.localPhoto, required this.icon});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty && localPhoto.isEmpty) {
      return Container(
        width: 104,
        height: 104,
        decoration: const BoxDecoration(color: Color(0x2EFFFFFF), shape: BoxShape.circle),
        child: Icon(icon, size: 44, color: const Color(0x80FFFFFF)),
      );
    }
    return MemberAvatar(
      name: '',
      url: url,
      localPhoto: localPhoto,
      size: 104,
      radius: 52,
      background: const Color(0x2EFFFFFF),
    );
  }
}

/// The virtual ID QR: `/Utilities/QRCode` PNG for [content], on a white tile.
class _VirtualIdQr extends StatefulWidget {
  final String? content;
  const _VirtualIdQr({required this.content});

  @override
  State<_VirtualIdQr> createState() => _VirtualIdQrState();
}

class _VirtualIdQrState extends State<_VirtualIdQr> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _VirtualIdQr old) {
    super.didUpdateWidget(old);
    if (old.content != widget.content) _load();
  }

  Future<void> _load() async {
    final content = widget.content?.trim() ?? '';
    setState(() => _bytes = null);
    if (content.isEmpty) return;
    try {
      // The endpoint returns raw PNG bytes — must skip the JSON decoder.
      final bytes = await Api.utilitiesQRCodeBytes(width: 300, height: 300, content: content);
      if (mounted && widget.content?.trim() == content) setState(() => _bytes = bytes.isEmpty ? null : bytes);
    } catch (e) {
      debugPrint('Virtual ID QR load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      width: 96,
      height: 96,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.md)),
      child: _bytes == null
          ? Icon(Ion.qrCode, size: 60, color: c.primary)
          : Image.memory(_bytes!, width: 92, height: 92, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Tints for the instructor's club stat tiles, cycled by position.
const _statTints = [
  Color(0xFF6366F1),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEC4899),
  Color(0xFF0EA5E9),
  Color(0xFF8B5CF6),
  Color(0xFFEF4444),
  Color(0xFF14B8A6),
];

/// Instructor tab routes switch the shell tab with `go`; everything else is pushed.
const _instructorTabs = {'/instructor/home', '/instructor/collections', '/instructor/reports', '/instructor/settings'};

/// Member (student) and instructor profile. The instructor Settings tab uses the same screen.
///
/// Layout: compact identity header, a dark member / staff ID card with a full-screen QR, quick
/// actions, role-specific overview, personal details with tap-to-copy, one grouped settings
/// card (switchers, notifications, theme, guide) and a clear logout button.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with UseApi<ProfileScreen>, LiveRefreshMixin<ProfileScreen> {
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

  /// Past the header, a solid bar fades in behind the status bar so content never scrolls
  /// under the clock.
  bool _pastHeader = false;

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
    final ok = await confirmDialog(context, 'Log out?',
        message: 'You will need to sign in again to use D-Clix on this device.',
        confirmLabel: 'Log out',
        destructive: true);
    if (!ok || !mounted) return;
    UserSession.instance.logout();
    context.go('/login');
  }

  void _open(String route) {
    if (_instructorTabs.contains(route)) {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  Future<void> _copy(String label, String value) async {
    if (value.isEmpty || value == '—') return;
    await Clipboard.setData(ClipboardData(text: value));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    final bottom = 62 + MediaQuery.paddingOf(context).bottom + 12;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('$label copied'),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, bottom),
        duration: const Duration(seconds: 2),
      ));
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
    final infoGrade = '${_info.data?['currentGrade'] ?? ''}'.trim();
    final grade = infoGrade.isNotEmpty ? infoGrade : u('currentGrade');
    final clubList = (user['clubList'] as List? ?? const []).whereType<Map>().toList();
    final clubName =
        u('clubName').isNotEmpty ? u('clubName') : (clubList.isNotEmpty ? '${clubList.first['text'] ?? ''}' : '');
    final regNo = '${_info.data?['registrationNo'] ?? ''}'.trim();
    final code = regNo.isNotEmpty ? regNo : (u('code').isNotEmpty ? u('code') : u('icNo'));
    final status = u('status');
    final isActive = status.toLowerCase() == 'active';

    // A student's QR encodes `ST-` + id padded to 8 digits; instructors keep the bare id.
    final qrContent = isInstructor
        ? (u('id').isEmpty ? null : u('id'))
        : QrContent.studentFromRaw(session.currentStudentId ?? user['id']);

    final branchIds = (user['branchIds'] as List? ?? const []).map((e) => '$e').toSet();
    final myBranches = (_branches.data ?? const []).where((b) => branchIds.contains('${b['id']}')).toList();
    final currentBranch = (_branches.data ?? const []).where((b) => '${b['id']}' == u('branchId')).firstOrNull;
    final stats = [...?_clubStats.data]..sort((a, b) => RnApi.number(a['value']).compareTo(RnApi.number(b['value'])));

    final eCenter = '${_info.data?['eCenterName'] ?? ''}'.trim();
    final tCenter = '${_info.data?['tCenterName'] ?? ''}'.trim();
    final instructorName = '${_info.data?['instructorName'] ?? ''}'.trim();
    final phone = u('handPhone');
    final details = [
      (icon: Ion.callOutline, label: 'Phone', value: phone, copy: true),
      if (!isInstructor) (icon: Ion.ribbonOutline, label: 'Belt / Grade', value: grade, copy: false),
      if (tCenter.isNotEmpty) (icon: Ion.locationOutline, label: 'Training centre', value: tCenter, copy: false),
      if (eCenter.isNotEmpty && eCenter != tCenter)
        (icon: Ion.businessOutline, label: 'Exam centre', value: eCenter, copy: false),
      if (!isInstructor && instructorName.isNotEmpty)
        (icon: Ion.personOutline, label: 'Instructor', value: instructorName, copy: false),
      (icon: Ion.cardOutline, label: isInstructor ? 'Staff code' : 'Registration no', value: code, copy: true),
    ];

    final quickActions = isInstructor
        ? const [
            (icon: Ion.checkmarkDoneCircleOutline, label: 'Check-In', route: '/instructor/attendance'),
            (icon: Ion.documentTextOutline, label: 'Reports', route: '/instructor/reports'),
            (icon: Ion.cashOutline, label: 'Collections', route: '/instructor/collections'),
            (icon: Ion.headsetOutline, label: 'Help Desk', route: '/helpdesk'),
          ]
        : const [
            (icon: Ion.qrCodeOutline, label: 'Check In', route: '/qr-scan'),
            (icon: Ion.idCardOutline, label: 'My Details', route: '/student-details'),
            (icon: Ion.bagHandleOutline, label: 'Purchases', route: '/purchases'),
            (icon: Ion.headsetOutline, label: 'Help Desk', route: '/helpdesk'),
          ];

    // ── building blocks ─────────────────────────────────────────────────────────────────────
    BoxDecoration cardDeco([double r = Radii.xl]) => BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(r),
          boxShadow: Shadows.soft(c),
          border: Border.all(color: c.isDark ? c.border : c.borderLight),
        );

    Widget iconTile(IconData icon, {Color? tint, double size = 38}) {
      final color = tint ?? c.primary;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.hexA(c.isDark ? '2E' : '17'),
          borderRadius: BorderRadius.circular(Radii.sm + 2),
        ),
        child: Icon(icon, size: size * .5, color: color),
      );
    }

    Widget sectionLabel(String text, {Widget? trailing}) => Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.xl + 4, 24, Gaps.xl + 4, 10),
          child: Row(children: [
            Expanded(
              child: Text(text.toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.1, color: c.textMuted)),
            ),
            if (trailing != null) trailing,
          ]),
        );

    Widget groupCard(List<Widget> rows) => Container(
          margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
          decoration: cardDeco(),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, margin: const EdgeInsets.only(left: 66), color: c.borderLight),
              rows[i],
            ],
          ]),
        );

    Widget settingRow({
      required IconData icon,
      required String title,
      String? value,
      Widget? trailing,
      VoidCallback? onTap,
      Color? tint,
    }) {
      final row = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          iconTile(icon, tint: tint),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
              if (value != null && value.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary, fontWeight: FontWeight.w500)),
              ],
            ]),
          ),
          if (trailing != null) trailing else if (onTap != null) Icon(Ion.chevronForward, size: 18, color: c.textMuted),
        ]),
      );
      if (onTap == null) return row;
      return Semantics(
        button: true,
        label: value == null ? title : '$title, $value',
        excludeSemantics: trailing == null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(onTap: onTap, child: row),
        ),
      );
    }

    // ── header ──────────────────────────────────────────────────────────────────────────────
    Widget headerButton(IconData icon, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: Touchable(
            onPress: onTap,
            activeOpacity: 0.7,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0x2EFFFFFF),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              child: Icon(icon, size: 19, color: Colors.white),
            ),
          ),
        );

    Widget headerChip(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: const Color(0x2EFFFFFF), borderRadius: BorderRadius.circular(999)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 5),
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ]),
        );

    final header = Container(
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: Shadows.soft(c),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.xl, 6, Gaps.xl, 64),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            // Reachable both as the Profile tab root (no back wanted) and as a Quick
            // Access / All Features drill-down push (back wanted) — same gate as
            // TabRootBackButton, but this header already has its own icon-button style.
            if (canPopHere(context)) ...[
              headerButton(Ion.chevronBack, 'Back', () => safeBack(context)),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(isInstructor ? 'Instructor Profile' : 'My Profile',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            headerButton(theme.isDark ? Ion.sunny : Ion.moon,
                theme.isDark ? 'Switch to light mode' : 'Switch to dark mode', theme.toggle),
            const SizedBox(width: 10),
            headerButton(Ion.pencil, 'Edit profile', () => context.push('/edit-profile')),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Semantics(
              button: true,
              label: 'Change profile photo',
              child: Touchable(
                onPress: () => context.push('/edit-profile'),
                activeOpacity: 0.85,
                child: Stack(clipBehavior: Clip.none, children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(color: Color(0x40FFFFFF), shape: BoxShape.circle),
                    child: _ProfilePhoto(
                      url: session.studentPhoto,
                      localPhoto: session.localPhotoB64,
                      icon: isInstructor ? Ion.school : Ion.person,
                      size: 78,
                    ),
                  ),
                  if (status.isNotEmpty)
                    Positioned(
                      right: 2,
                      bottom: 4,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.isEmpty ? 'Member' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.2)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  headerChip(isInstructor ? Ion.school : Ion.shieldCheckmark, isInstructor ? 'Instructor' : 'Student'),
                  if (status.isNotEmpty)
                    headerChip(isActive ? Ion.checkmarkDoneCircleOutline : Ion.pulseOutline, status),
                  if (!isInstructor && grade.isNotEmpty) headerChip(Ion.ribbonOutline, grade),
                ]),
                if (clubName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(clubName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 12.5, fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          ]),
        ]),
      ),
    );

    // ── member / staff ID card ──────────────────────────────────────────────────────────────
    final idCard = Container(
      margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
        ),
        boxShadow: Shadows.shade(c),
        border: c.isDark ? Border.all(color: const Color(0xFF334155)) : null,
      ),
      child: Stack(children: [
        Positioned(
          left: -50,
          bottom: -70,
          child: IgnorePointer(
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [c.primary.hexA('4D'), c.primary.hexA('00')]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset(kLogoAssetPath, width: 22, height: 22),
                  ),
                  const SizedBox(width: 8),
                  Text(isInstructor ? 'STAFF ID' : 'MEMBER ID',
                      style: const TextStyle(
                          color: Color(0xFFFDBA74), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                ]),
                const SizedBox(height: 14),
                Text(name.isEmpty ? 'Member' : name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 4),
                Text(
                    isInstructor
                        ? (clubName.isEmpty ? 'Instructor' : clubName)
                        : (grade.isEmpty ? 'Grade not recorded' : grade),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5)),
                const SizedBox(height: 12),
                if (code.isNotEmpty)
                  Semantics(
                    button: true,
                    label: 'Copy ${isInstructor ? 'staff code' : 'registration number'} $code',
                    excludeSemantics: true,
                    child: Touchable(
                      onPress: () => _copy(isInstructor ? 'Staff code' : 'Registration number', code),
                      activeOpacity: 0.7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration:
                            BoxDecoration(color: const Color(0x1AFFFFFF), borderRadius: BorderRadius.circular(8)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Flexible(
                            child: Text(code,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Ion.copyOutline, size: 13, color: Color(0xFFCBD5E1)),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: 14),
            Semantics(
              button: true,
              label: 'Show QR code full screen',
              child: Touchable(
                onPress: qrContent == null ? null : () => _showQr(name: name, code: code, content: qrContent),
                activeOpacity: 0.85,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _VirtualIdQr(content: qrContent, size: 96),
                  const SizedBox(height: 6),
                  const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Ion.expandOutline, size: 11, color: Color(0xFFCBD5E1)),
                    SizedBox(width: 4),
                    Text('Tap to enlarge', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 10.5)),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );

    // ── quick actions ───────────────────────────────────────────────────────────────────────
    final actions = Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.xl, 16, Gaps.xl, 0),
      child: Row(children: [
        for (final (i, a) in quickActions.indexed) ...[
          if (i > 0) const SizedBox(width: Gaps.sm),
          Expanded(
            child: Semantics(
              button: true,
              label: a.label,
              excludeSemantics: true,
              child: Touchable(
                onPress: () => _open(a.route),
                activeOpacity: 0.7,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: cardDeco(Radii.lg),
                  child: Column(children: [
                    iconTile(a.icon, size: 40),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(a.label,
                          maxLines: 1,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.textPrimary)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ]),
    );

    // ── instructor: club overview + branches ────────────────────────────────────────────────
    final overview = <Widget>[
      if (isInstructor) ...[
        sectionLabel('Club overview',
            trailing: _clubStats.loading
                ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                : null),
        if (_clubStats.error != null && stats.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
            child: ErrorState(compact: true, message: _clubStats.error, onRetry: _clubStats.reload),
          )
        else if (stats.isEmpty && !_clubStats.loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.xl + 4),
            child: Text('No club figures yet.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
            child: LayoutBuilder(builder: (context, box) {
              final w = (box.maxWidth - Gaps.sm) / 2;
              return Wrap(spacing: Gaps.sm, runSpacing: Gaps.sm, children: [
                for (final (i, s) in stats.indexed)
                  Container(
                    width: w,
                    padding: const EdgeInsets.all(14),
                    decoration: cardDeco(Radii.lg),
                    child: Row(children: [
                      iconTile(_statIcon('${s['text'] ?? ''}'), tint: _statTints[i % _statTints.length], size: 40),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text('${s['id'] ?? ''}',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary)),
                          ),
                          Text('${s['text'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                  ),
              ]);
            }),
          ),
        if (myBranches.isNotEmpty || branchIds.isNotEmpty) ...[
          sectionLabel('Your branches'),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
            padding: const EdgeInsets.all(14),
            decoration: cardDeco(),
            child: myBranches.isEmpty
                ? Text(
                    _branches.loading
                        ? 'Loading branches…'
                        : '${branchIds.length} assigned branch${branchIds.length == 1 ? '' : 'es'}',
                    style: TextStyle(color: c.textSecondary, fontSize: 13))
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final b in myBranches)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: '${b['id']}' == u('branchId') ? c.primary.hexA('1F') : c.surfaceAlt,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: '${b['id']}' == u('branchId') ? c.primary : Colors.transparent),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Ion.locationOutline, size: 13, color: c.primary),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text('${b['text'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          ),
                        ]),
                      ),
                  ]),
          ),
        ],
      ],
    ];

    // ── details ─────────────────────────────────────────────────────────────────────────────
    final detailRows = [
      for (final d in details)
        settingRow(
          icon: d.icon,
          title: d.value.isEmpty ? 'Not recorded' : d.value,
          value: d.label,
          trailing: d.copy && d.value.isNotEmpty
              ? Semantics(
                  button: true,
                  label: 'Copy ${d.label}',
                  child: Touchable(
                    onPress: () => _copy(d.label, d.value),
                    activeOpacity: 0.6,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Ion.copyOutline, size: 18, color: c.textMuted),
                    ),
                  ),
                )
              : null,
        ),
    ];

    // ── settings ────────────────────────────────────────────────────────────────────────────
    final settingsRows = <Widget>[
      if (isInstructor)
        settingRow(
          icon: Ion.gitBranchOutline,
          title: 'Switch branch',
          value: '${currentBranch?['text'] ?? ''}',
          tint: const Color(0xFF6366F1),
          onTap: () => _showPicker(
            title: 'Switch Branch',
            items: [
              for (final b in _branches.data ?? const <Map<String, dynamic>>[])
                (id: b['id'], label: '${b['text'] ?? ''}', active: '${b['id']}' == u('branchId')),
            ],
            onPick: (it) async {
              final ok = await session.switchBranch(it.id ?? 0, clubCode: u('clubCode'));
              if (!mounted) return;
              notify(this.context, ok ? 'Switched to ${it.label}' : 'Switch failed',
                  ok ? null : (session.error ?? 'Unknown error'));
            },
          ),
        )
      else ...[
        settingRow(
          icon: Ion.swapHorizontal,
          title: 'Switch student',
          value: name,
          tint: const Color(0xFF6366F1),
          onTap: () => _showPicker(
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
          ),
        ),
        settingRow(
          icon: Ion.businessOutline,
          title: 'Club',
          value: clubName,
          tint: const Color(0xFF0EA5E9),
          onTap: () => _showPicker(
            title: 'Switch Club',
            items: [
              for (final cl in clubList)
                (id: cl['id'], label: '${cl['text'] ?? ''}', active: '${cl['id']}' == u('clubId')),
            ],
          ),
        ),
      ],
      settingRow(
        icon: Ion.notificationsOutline,
        title: 'Notifications',
        value: 'Alerts, sound and quiet hours',
        tint: const Color(0xFFF59E0B),
        onTap: () => _open('/notification-settings'),
      ),
      settingRow(
        icon: theme.isDark ? Ion.moon : Ion.sunny,
        title: 'Dark mode',
        value: theme.isDark ? 'On' : 'Off',
        tint: const Color(0xFF8B5CF6),
        trailing: Switch.adaptive(
          value: theme.isDark,
          onChanged: (_) => theme.toggle(),
          activeTrackColor: c.primary,
          inactiveTrackColor: c.border,
          thumbColor: const WidgetStatePropertyAll(Colors.white),
          trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      settingRow(
        icon: Ion.bookOutline,
        title: 'User guide',
        value: 'How the app works',
        tint: const Color(0xFF10B981),
        onTap: () => _open('/user-guide'),
      ),
    ];

    return ColoredBox(
      color: c.background,
      child: Stack(children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            final past = n.metrics.pixels > 140;
            if (past != _pastHeader) setState(() => _pastHeader = past);
            return false;
          },
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: () => reloadAll(),
            edgeOffset: top,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: tabBarHeight + 28),
              children: [
                header,
                // The ID card overlaps the header's rounded edge. Both live inside the same list, so
                // nothing clips it.
                Transform.translate(offset: const Offset(0, -44), child: idCard),
                Transform.translate(
                  offset: const Offset(0, -44),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    actions,
                    ...overview,
                    sectionLabel(isInstructor ? 'Your details' : 'Member details'),
                    groupCard(detailRows),
                    sectionLabel('Settings'),
                    groupCard(settingsRows),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
                      child: Semantics(
                        button: true,
                        label: 'Log out',
                        excludeSemantics: true,
                        child: Touchable(
                          onPress: _onLogout,
                          activeOpacity: 0.8,
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 52),
                            decoration: BoxDecoration(
                              color: c.danger.hexA(c.isDark ? '24' : '12'),
                              borderRadius: BorderRadius.circular(Radii.lg),
                              border: Border.all(color: c.danger.hexA('55')),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Ion.logOutOutline, size: 19, color: c.danger),
                              const SizedBox(width: 8),
                              Text('Log out',
                                  style: TextStyle(color: c.danger, fontWeight: FontWeight.w800, fontSize: 15)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('D-Clix · v$kAppVersion',
                        textAlign: TextAlign.center, style: TextStyle(color: c.textMuted, fontSize: 11)),
                  ]),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _pastHeader ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: Container(
                height: top,
                decoration: BoxDecoration(color: c.background, boxShadow: Shadows.soft(c)),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// Full-screen QR so a scanner at the counter can read it from arm's length.
  Future<void> _showQr({required String name, required String code, required String content}) {
    final c = context.appColors;
    return showModalBottomSheet<void>(
      context: context,
      // Above the tab bar, which the shell draws over its own navigator.
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: c.overlay,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, 24 + MediaQuery.paddingOf(ctx).bottom),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(3)),
          ),
          Text(_isInstructor ? 'Staff ID' : 'Member ID',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.primary)),
          const SizedBox(height: 6),
          Text(name.isEmpty ? 'Member' : name,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(Radii.xl),
              border: Border.all(color: c.borderLight),
              boxShadow: Shadows.card(c),
            ),
            child: _VirtualIdQr(content: content, size: 240),
          ),
          const SizedBox(height: 16),
          if (code.isNotEmpty)
            Text(code,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.textPrimary)),
          const SizedBox(height: 6),
          Text('Show this code when your academy asks for your ID.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: c.textSecondary)),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: Touchable(
              onPress: () => Navigator.pop(ctx),
              child: Container(
                constraints: const BoxConstraints(minHeight: 50),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.lg)),
                child: Text('Done', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary)),
              ),
            ),
          ),
        ]),
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
      // Above the tab bar, which the shell draws over its own navigator.
      useRootNavigator: true,
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

/// Round profile photo with a translucent fallback disc + icon.
class _ProfilePhoto extends StatelessWidget {
  final String url;
  final String localPhoto;
  final IconData icon;
  final double size;
  const _ProfilePhoto({required this.url, required this.localPhoto, required this.icon, this.size = 104});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty && localPhoto.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Color(0x2EFFFFFF), shape: BoxShape.circle),
        child: Icon(icon, size: size * .42, color: const Color(0xB3FFFFFF)),
      );
    }
    return MemberAvatar(
      name: '',
      url: url,
      localPhoto: localPhoto,
      size: size,
      radius: size / 2,
      background: const Color(0x2EFFFFFF),
    );
  }
}

/// The virtual ID QR: `/Utilities/QRCode` PNG for [content], on a white tile.
class _VirtualIdQr extends StatefulWidget {
  final String? content;
  final double size;
  const _VirtualIdQr({required this.content, this.size = 96});

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
    final s = widget.size;
    return Container(
      width: s,
      height: s,
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.md)),
      child: _bytes == null
          ? Icon(Ion.qrCode, size: s * .6, color: c.primary)
          : Image.memory(_bytes!, width: s - 4, height: s - 4, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }
}

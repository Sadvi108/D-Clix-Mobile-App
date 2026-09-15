import 'package:cached_network_image/cached_network_image.dart';
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

typedef _Tile = ({String id, String label, IconData icon, Color color});

/// Quick Access tiles — `TILES` in `frontend/src/screens/InstructorHome.tsx`.
const List<_Tile> _tiles = [
  (id: 'training-time', label: 'Training Time', icon: Ion.timeOutline, color: Color(0xFFF59E0B)),
  (id: 'activities', label: 'Activities', icon: Ion.pulseOutline, color: Color(0xFF10B981)),
  // Attendance is self-scoped server-side; the screen shows the class list + centre QR.
  (id: 'update-attendance', label: 'Class Check-In', icon: Ion.checkmarkDoneCircleOutline, color: Color(0xFF4F46E5)),
  (id: 'receipt', label: 'Receipt', icon: Ion.receiptOutline, color: Color(0xFF0EA5E9)),
  (id: 'grading-schedule', label: 'Grading Schedule', icon: Ion.schoolOutline, color: Color(0xFF9333EA)),
  (id: 'tournament-summary', label: 'Tournament Summary', icon: Ion.trophyOutline, color: Color(0xFFEF4444)),
  (id: 'collections', label: 'Collections', icon: Ion.cashOutline, color: Color(0xFFDB2777)),
  (id: 'missing-invoice', label: 'Missing Invoice', icon: Ion.documentTextOutline, color: Color(0xFFF97316)),
  (id: 'fee-master', label: 'Fee Master', icon: Ion.pricetagsOutline, color: Color(0xFF64748B)),
  (id: 'new-student', label: 'New Student', icon: Ion.personAddOutline, color: Color(0xFF10B981)),
  (id: 'payment-slip', label: 'Payment Slip', icon: Ion.documentAttachOutline, color: Color(0xFF4F46E5)),
  (id: 'more', label: 'More', icon: Ion.gridOutline, color: Color(0xFF0EA5E9)),
];

/// `TILE_ROUTES`. Activities and Fee Master were "coming soon" in RN; this app has working
/// report screens for both, so they open those instead of a dead-end notice.
const Map<String, String> _tileRoutes = {
  'training-time': '/instructor/reports/training-time',
  'activities': '/instructor/reports/activity',
  'update-attendance': '/instructor/attendance',
  'receipt': '/instructor/reports/receipt',
  'grading-schedule': '/instructor/reports/grading-schedule',
  'tournament-summary': '/instructor/reports/tournament-summary',
  'collections': '/instructor/collections',
  'missing-invoice': '/instructor/reports/outstanding',
  'fee-master': '/instructor/reports/fee-master',
  'payment-slip': '/instructor/reports/payment-slip',
  'new-student': '/instructor/reports/new-student',
  'more': '/instructor/reports',
};

/// Port of `frontend/src/screens/InstructorHome.tsx` (Expo v2.11.1).
class InstructorHomeScreen extends StatefulWidget {
  const InstructorHomeScreen({super.key});
  @override
  State<InstructorHomeScreen> createState() => _InstructorHomeScreenState();
}

class _InstructorHomeScreenState extends State<InstructorHomeScreen>
    with UseApi<InstructorHomeScreen>, LiveRefreshMixin<InstructorHomeScreen> {
  late final _stats = useApi(RnApi.homePageStats);
  late final _clubStats = useApi(RnApi.myClubStats);

  /// The dues card counts the very invoices it navigates to. HomePageStats' totals do not
  /// agree with the `/Outstanding/Fetch` list behind the card (probed live 2026-08-10:
  /// 3 invoices / RM 420 vs 649 / RM 47,365), so one query feeds both.
  late final _dues = useApi(() => RnApi.outstanding());

  @override
  void initState() {
    super.initState();
    _stats;
    _clubStats;
    _dues;
  }

  @override
  Future<void> refreshLiveData() => reloadAll(silent: true);

  void _onTile(_Tile t) {
    final route = _tileRoutes[t.id];
    if (route == null) {
      notify(context, t.label, 'This feature is coming soon.');
    } else if (route == '/instructor/collections' || route == '/instructor/reports') {
      context.go(route);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final user = session.authData ?? const <String, dynamic>{};
    String userField(String k) => '${user[k] ?? ''}'.trim();
    final top = MediaQuery.paddingOf(context).top;
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;

    final dueRows = _dues.data ?? const [];
    final invoiceCount = dueRows.length;
    final dueAmount = dueRows.fold<num>(0, (s, r) => s + RnApi.number(r['dueAmount']));
    final offers = ((_stats.data?['myoffers'] as List?) ?? const []).whereType<Map>().toList();
    final unread = session.unreadNotifications;
    // MyClubStats rows: id = count, text = label, value = display order ("1".."10").
    final rows = [...?_clubStats.data]
      ..sort((a, b) => RnApi.number(a['value']).compareTo(RnApi.number(b['value'])));

    final dueFg = c.isDark ? const Color(0xFFFDBA74) : const Color(0xFF9A3412);
    final duesFailed = _dues.error != null && _dues.data == null;

    Widget iconBtn(IconData icon, VoidCallback onTap, {int badge = 0}) => Touchable(
          onPress: onTap,
          activeOpacity: 0.8,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(color: Color(0x38FFFFFF), shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
              if (badge > 0)
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
                    child: Text(badge > 99 ? '99+' : '$badge',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
          ),
        );

    Widget sectionHead(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(Gaps.xl, 24, Gaps.xl, 12),
          child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
        );

    BoxDecoration cardDeco(double r) => BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(r),
          boxShadow: Shadows.soft(c),
          border: c.isDark ? Border.all(color: c.border) : null,
        );

    Widget card(Widget child) => Container(
          margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
          padding: const EdgeInsets.all(16),
          decoration: cardDeco(Radii.xl),
          child: child,
        );

    Widget spinner() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary)),
          ),
        );

    Widget empty(String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 13)),
        );

    final clubName = userField('clubName');
    final name = userField('name');
    final clubPic = UserSession.resolvePhotoUrl(userField('clubPic'));
    const avatarFallback = ColoredBox(
      color: Color(0x40FFFFFF),
      child: Center(child: Icon(Ion.business, size: 26, color: Color(0xD9FFFFFF))),
    );

    return ColoredBox(
      color: c.background,
      child: Column(children: [
        Container(
          color: c.primary,
          padding: EdgeInsets.only(top: top),
          child: Container(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, 6, Gaps.xl, 26),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Expanded(
                  child: Row(children: [
                    Container(
                      width: 52,
                      height: 52,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: clubPic.isEmpty ? null : Colors.white,
                        border: const Border.fromBorderSide(BorderSide(color: Color(0x99FFFFFF), width: 2)),
                      ),
                      child: clubPic.isEmpty
                          ? avatarFallback
                          : CachedNetworkImage(
                              imageUrl: clubPic,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => avatarFallback,
                            ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Welcome,', style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 12)),
                        Text(name.isEmpty ? 'Instructor' : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        const SizedBox(height: 2),
                        Text('(${clubName.isEmpty ? 'Club' : clubName})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFFFF7ED), fontSize: 12, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                iconBtn(Ion.settingsOutline, () => context.go('/instructor/settings')),
                const SizedBox(width: 10),
                iconBtn(Ion.notificationsOutline, () => context.push('/notifications'), badge: unread),
              ]),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: () => Future.wait([reloadAll(), session.refresh(background: true)]),
            child: ListView(
              padding: EdgeInsets.only(bottom: tabBarHeight + 24),
              children: [
                // Dues summary card
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl, 18, Gaps.xl, 0),
                  child: Touchable(
                    onPress: () => context.push('/invoices'),
                    activeOpacity: 0.9,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.xl),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: c.isDark
                              ? const [Color(0xFF2D1A0A), Color(0xFF3F2410)]
                              : const [Color(0xFFFEF3C7), Color(0xFFFED7AA)],
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.isDark ? const Color(0x40000000) : const Color(0xB3FFFFFF),
                          ),
                          child: Icon(Ion.notifications, size: 22, color: c.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (_dues.loading && _dues.data == null)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary)),
                              )
                            else
                              Text(
                                duesFailed
                                    ? "Dues couldn't be loaded"
                                    : '$invoiceCount invoice${invoiceCount == 1 ? '' : 's'} ${invoiceCount == 1 ? 'is' : 'are'} due',
                                style: TextStyle(
                                    color: c.isDark ? const Color(0xFFFED7AA) : const Color(0xFF7C2D12),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800),
                              ),
                            const SizedBox(height: 3),
                            Text(
                              duesFailed ? 'Tap to open Pay Your Dues' : 'RM ${money2(dueAmount)} total due amount',
                              style: TextStyle(color: dueFg, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 14),
                        Icon(Ion.chevronForward, size: 18, color: dueFg),
                      ]),
                    ),
                  ),
                ),

                sectionHead('Quick Access'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
                  child: LayoutBuilder(builder: (context, box) {
                    final w = box.maxWidth * .30;
                    final gap = (box.maxWidth - w * 3) / 2;
                    return Wrap(spacing: gap, runSpacing: 14, children: [
                      for (final t in _tiles)
                        SizedBox(
                          width: w,
                          child: Touchable(
                            onPress: () => _onTile(t),
                            activeOpacity: 0.8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
                              decoration: cardDeco(Radii.lg),
                              child: Column(children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle, color: t.color.hexA(c.isDark ? '33' : '18')),
                                  child: Icon(t.icon, size: 22, color: t.color),
                                ),
                                SizedBox(
                                  height: 28,
                                  child: Text(t.label,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: c.textPrimary,
                                          fontWeight: FontWeight.w600,
                                          height: 14 / 11)),
                                ),
                              ]),
                            ),
                          ),
                        ),
                    ]);
                  }),
                ),

                sectionHead('Latest Updates'),
                card(_clubStats.loading
                    ? spinner()
                    : rows.isEmpty
                        ? empty('No updates right now.')
                        : Column(children: [
                            for (var i = 0; i < rows.length; i++) ...[
                              if (i > 0) Container(height: 1, color: c.border),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(children: [
                                  Expanded(
                                    child: Text('${rows[i]['text'] ?? ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 14, color: c.textPrimary, fontWeight: FontWeight.w600)),
                                  ),
                                  const SizedBox(width: 12),
                                  Text('${rows[i]['id'] ?? ''}',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.primary)),
                                ]),
                              ),
                            ],
                          ])),

                sectionHead('Latest News'),
                if (_stats.loading)
                  card(spinner())
                else if (offers.isNotEmpty)
                  for (final o in offers.take(2))
                    Container(
                      margin: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, 12),
                      padding: const EdgeInsets.all(16),
                      decoration: cardDeco(Radii.lg),
                      child: Row(children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                          child: Icon(Ion.megaphoneOutline, size: 20, color: c.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${o['name'] ?? ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, color: c.textPrimary, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text(('${o['code'] ?? ''}'.isEmpty ? 'NEWS' : '${o['code']}').toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: c.textSecondary,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5)),
                          ]),
                        ),
                      ]),
                    )
                else
                  card(empty('No news right now.')),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

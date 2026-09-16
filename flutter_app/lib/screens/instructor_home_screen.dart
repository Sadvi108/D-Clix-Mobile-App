import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/live_refresh.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/premium_kit.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

typedef _Tile = ({String id, String label, IconData icon, Color color, String group});

const _classes = 'Classes & students';
const _payments = 'Payments & records';

/// Quick Access tiles — `TILES` in `frontend/src/screens/InstructorHome.tsx`, grouped.
const List<_Tile> _tiles = [
  // Attendance is self-scoped server-side; the screen shows the class list + centre QR.
  (
    id: 'update-attendance',
    label: 'Class Check-In',
    icon: Ion.checkmarkDoneCircleOutline,
    color: PremiumTint.indigo,
    group: _classes
  ),
  (id: 'training-time', label: 'Training Time', icon: Ion.timeOutline, color: PremiumTint.amber, group: _classes),
  (id: 'new-student', label: 'New Student', icon: Ion.personAddOutline, color: PremiumTint.green, group: _classes),
  (
    id: 'grading-schedule',
    label: 'Grading Schedule',
    icon: Ion.schoolOutline,
    color: PremiumTint.violet,
    group: _classes
  ),
  (
    id: 'tournament-summary',
    label: 'Tournament Summary',
    icon: Ion.trophyOutline,
    color: PremiumTint.red,
    group: _classes
  ),
  (id: 'activities', label: 'Activities', icon: Ion.pulseOutline, color: PremiumTint.teal, group: _classes),
  (id: 'collections', label: 'Collections', icon: Ion.cashOutline, color: PremiumTint.pink, group: _payments),
  (
    id: 'payment-slip',
    label: 'Payment Slip',
    icon: Ion.documentAttachOutline,
    color: PremiumTint.violet,
    group: _payments
  ),
  (
    id: 'missing-invoice',
    label: 'Missing Invoice',
    icon: Ion.documentTextOutline,
    color: PremiumTint.orange,
    group: _payments
  ),
  (id: 'receipt', label: 'Receipt', icon: Ion.receiptOutline, color: PremiumTint.sky, group: _payments),
  (id: 'fee-master', label: 'Fee Master', icon: Ion.pricetagsOutline, color: PremiumTint.slate, group: _payments),
  (id: 'more', label: 'All Reports', icon: Ion.gridOutline, color: PremiumTint.sky, group: _payments),
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

/// Icon for a MyClubStats row by its label.
IconData _statIconFor(String text) {
  final t = text.toLowerCase();
  if (t.contains('student')) return Ion.people;
  if (t.contains('training')) return Ion.time;
  if (t.contains('grading')) return Ion.ribbon;
  if (t.contains('tournament')) return Ion.trophy;
  if (t.contains('slip')) return Ion.receipt;
  if (t.contains('payment')) return Ion.card;
  if (t.contains('purchase')) return Ion.bagHandle;
  if (t.contains('registration')) return Ion.personAdd;
  return Ion.statsChart;
}

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
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;

    final dueRows = _dues.data ?? const [];
    final invoiceCount = dueRows.length;
    final dueAmount = dueRows.fold<num>(0, (s, r) => s + RnApi.number(r['dueAmount']));
    final offers = ((_stats.data?['myoffers'] as List?) ?? const []).whereType<Map>().toList();
    final unread = session.unreadNotifications;
    // MyClubStats rows: id = count, text = label, value = display order ("1".."10").
    final rows = [...?_clubStats.data]..sort((a, b) => RnApi.number(a['value']).compareTo(RnApi.number(b['value'])));

    final duesFailed = _dues.error != null && _dues.data == null;
    final clubName = userField('clubName');
    final name = userField('name');
    final clubPic = UserSession.resolvePhotoUrl(userField('clubPic'));
    const avatarFallback = ColoredBox(
      color: Color(0x40FFFFFF),
      child: Center(child: Icon(Ion.business, size: 24, color: Color(0xD9FFFFFF))),
    );

    const statTints = [
      PremiumTint.indigo,
      PremiumTint.green,
      PremiumTint.amber,
      PremiumTint.pink,
      PremiumTint.sky,
      PremiumTint.violet,
      PremiumTint.red,
      PremiumTint.teal,
    ];

    Widget grid(List<Widget> children, {int columns = 3}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
          child: LayoutBuilder(builder: (context, box) {
            const gap = Gaps.sm + 2;
            final w = (box.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(spacing: gap, runSpacing: gap, children: [
              for (final child in children) SizedBox(width: w, child: child),
            ]);
          }),
        );

    Widget spinner() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child:
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary)),
          ),
        );

    Widget emptyCard(IconData icon, String text) => Container(
          margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
          padding: const EdgeInsets.all(16),
          decoration: premiumCard(c),
          child: Row(children: [
            TintedIcon(icon, tint: PremiumTint.slate, size: 36),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: TextStyle(color: c.textSecondary, fontSize: 13))),
          ]),
        );

    final header = PremiumHeader(
      title: name.isEmpty ? 'Instructor' : name,
      subtitle: clubName.isEmpty ? 'Instructor' : '$clubName · Instructor',
      leading: Container(
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
            : CachedNetworkImage(imageUrl: clubPic, fit: BoxFit.cover, errorWidget: (_, __, ___) => avatarFallback),
      ),
      actions: [
        HeaderIconButton(icon: Ion.settingsOutline, label: 'Settings', onTap: () => context.go('/instructor/settings')),
        HeaderIconButton(
            icon: Ion.notificationsOutline,
            label: 'Notifications',
            badge: unread,
            onTap: () => context.push('/notifications')),
      ],
    );

    final dues = Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.lg, Gaps.xl, 0),
      child: Semantics(
        button: true,
        label: duesFailed
            ? 'Outstanding dues unavailable, open Pay Your Dues'
            : 'Outstanding dues RM ${money2(dueAmount)}, $invoiceCount invoices',
        excludeSemantics: true,
        child: Touchable(
          onPress: () => context.push('/invoices'),
          activeOpacity: 0.9,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: premiumSlate(c),
            child: Stack(children: [
              const SlateGlow(),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(right: 14),
                    decoration:
                        BoxDecoration(color: c.primary.hexA('26'), borderRadius: BorderRadius.circular(Radii.md)),
                    child: Icon(Ion.wallet, size: 22, color: c.primary),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('OUTSTANDING DUES',
                          style: TextStyle(
                              color: Color(0xFFFDBA74), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      if (_dues.loading && _dues.data == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)),
                        )
                      else
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(duesFailed ? 'Unavailable' : 'RM ${money2(dueAmount)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                        ),
                      const SizedBox(height: 2),
                      Text(
                          duesFailed
                              ? 'Tap to open Pay Your Dues'
                              : '$invoiceCount invoice${invoiceCount == 1 ? '' : 's'} due',
                          style:
                              const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(999)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('View', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
                      SizedBox(width: 4),
                      Icon(Ion.arrowForward, size: 14, color: Colors.white),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );

    return ColoredBox(
      color: c.background,
      child: Column(children: [
        header,
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: () => Future.wait([reloadAll(), session.refresh(background: true)]),
            child: ListView(
              padding: EdgeInsets.only(bottom: tabBarHeight + 24),
              children: [
                dues,
                for (final group in const [_classes, _payments]) ...[
                  SectionLabel(group),
                  grid([
                    for (final t in _tiles.where((t) => t.group == group))
                      PremiumTile(icon: t.icon, tint: t.color, label: t.label, onTap: () => _onTile(t)),
                  ]),
                ],
                SectionLabel('Club at a glance',
                    trailing: _clubStats.loading && rows.isNotEmpty
                        ? SizedBox(
                            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary))
                        : null),
                if (_clubStats.loading && rows.isEmpty)
                  spinner()
                else if (rows.isEmpty)
                  emptyCard(Ion.statsChartOutline, 'No club figures right now.')
                else
                  grid(columns: 2, [
                    for (final (i, r) in rows.indexed)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: premiumCard(c, radius: Radii.lg),
                        child: Row(children: [
                          TintedIcon(_statIconFor('${r['text'] ?? ''}'), tint: statTints[i % statTints.length]),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text('${r['id'] ?? ''}',
                                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary)),
                              ),
                              Text('${r['text'] ?? ''}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ]),
                      ),
                  ]),
                const SectionLabel('Latest news'),
                if (_stats.loading && offers.isEmpty)
                  spinner()
                else if (offers.isEmpty)
                  emptyCard(Ion.megaphoneOutline, 'No news right now.')
                else
                  GroupCard(children: [
                    for (final o in offers.take(3))
                      PremiumRow(
                        icon: Ion.megaphoneOutline,
                        tint: PremiumTint.orange,
                        title: '${o['name'] ?? ''}',
                        titleLines: 2,
                        subtitle: ('${o['code'] ?? ''}'.isEmpty ? 'News' : '${o['code']}').toUpperCase(),
                      ),
                  ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

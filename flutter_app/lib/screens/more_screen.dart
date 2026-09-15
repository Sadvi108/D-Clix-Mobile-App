import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';
import 'home_screen.dart' show openRoute;

typedef _Option = ({String id, String label, IconData icon, Color color, String route});

/// Port of `frontend/app/more.tsx` (Expo v2.11.1) — the full feature catalogue, a superset of
/// the home Quick Access grid. Icons and colours match the home grid.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const List<({String title, List<_Option> items})> _sections = [
    (
      title: 'Training',
      items: [
        (id: 'training', label: 'Training', icon: Ion.barbell, color: Color(0xFF4F46E5), route: '/training'),
        (id: 'classes', label: "Today's Classes", icon: Ion.flash, color: Color(0xFFF59E0B), route: '/schedule'),
        (id: 'timetable', label: 'Timetable', icon: Ion.calendar, color: Color(0xFF0EA5E9), route: '/schedule'),
        (id: 'trainer', label: 'My Trainer', icon: Ion.personCircle, color: Color(0xFF8B5CF6), route: '/training'),
        (id: 'attendance', label: 'Attendance', icon: Ion.checkmarkDoneCircle, color: Color(0xFF10B981), route: '/attendance'),
        (id: 'book', label: 'Book a Class', icon: Ion.addCircle, color: Color(0xFF14B8A6), route: '/book-class'),
        (id: 'scan', label: 'Scan QR', icon: Ion.qrCode, color: Color(0xFF0EA5E9), route: '/qr-scan'),
      ],
    ),
    (
      title: 'Payments',
      items: [
        (id: 'feesdue', label: 'Fees Due', icon: Ion.wallet, color: Color(0xFFEF4444), route: '/payments'),
        (id: 'payments', label: 'Payment History', icon: Ion.receipt, color: Color(0xFF14B8A6), route: '/payments?tab=history'),
        (id: 'prepay', label: 'Advance Payment', icon: Ion.card, color: Color(0xFF8B5CF6), route: '/payments?tab=prepay'),
        (id: 'autopay', label: 'Auto Pay', icon: Ion.syncCircle, color: Color(0xFF0EA5E9), route: '/autopay'),
        (id: 'purchase', label: 'Purchase Request', icon: Ion.bagHandle, color: Color(0xFFF59E0B), route: '/purchase-request'),
        (id: 'purchases', label: 'My Purchases', icon: Ion.bagCheck, color: Color(0xFFF97316), route: '/purchases'),
      ],
    ),
    (
      title: 'Progress',
      items: [
        (id: 'progress', label: 'Progress Report', icon: Ion.trendingUp, color: Color(0xFF6366F1), route: '/progress'),
        (id: 'belt', label: 'Belt / Rank', icon: Ion.ribbon, color: Color(0xFFEAB308), route: '/belt-rank'),
      ],
    ),
    (
      title: 'Club',
      items: [
        (id: 'events', label: 'Events', icon: Ion.calendar, color: Color(0xFFF97316), route: '/events'),
        (id: 'tournament', label: 'Tournament', icon: Ion.trophy, color: Color(0xFFDB2777), route: '/tournament'),
        (id: 'offers', label: 'Offers', icon: Ion.pricetags, color: Color(0xFF10B981), route: '/events?tab=offers'),
        (id: 'chat', label: 'Chat Academy', icon: Ion.chatbubbles, color: Color(0xFF22C55E), route: '/chat'),
        (id: 'helpdesk', label: 'Help Desk', icon: Ion.headset, color: Color(0xFF0EA5E9), route: '/helpdesk'),
        (id: 'notifications', label: 'Notifications', icon: Ion.notifications, color: Color(0xFFF59E0B), route: '/notifications'),
        (id: 'notifsettings', label: 'Notification Settings', icon: Ion.options, color: Color(0xFF64748B), route: '/notification-settings'),
      ],
    ),
    (
      title: 'Account',
      items: [
        (id: 'profile', label: 'Profile', icon: Ion.personCircle, color: Color(0xFF64748B), route: '/profile'),
        (id: 'details', label: 'Student Details', icon: Ion.idCard, color: Color(0xFF4F46E5), route: '/student-details'),
        (id: 'editprofile', label: 'Edit Profile', icon: Ion.create, color: Color(0xFF8B5CF6), route: '/edit-profile'),
      ],
    ),
  ];

  /// Every route this screen can navigate to — a test asserts each one is registered.
  static List<String> get catalogueRoutes => [
        for (final s in _sections)
          for (final i in s.items) i.route
      ];

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const RnHeader(title: 'All Features'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 60),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text('Quick access to everything', style: TextStyle(color: c.textSecondary, fontSize: 13)),
              ),
              for (final s in _sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  child: Text(s.title.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: c.textMuted)),
                ),
                LayoutBuilder(builder: (context, box) {
                  final w = box.maxWidth * .305;
                  final gap = (box.maxWidth - w * 3) / 2;
                  return Wrap(spacing: gap, children: [
                    for (final o in s.items)
                      SizedBox(
                        width: w,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Touchable(
                            activeOpacity: 0.8,
                            onPress: () => openRoute(context, o.route),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
                              decoration: rnCard(c),
                              child: Column(children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration:
                                      BoxDecoration(shape: BoxShape.circle, color: o.color.hexA(c.isDark ? '33' : '18')),
                                  child: Icon(o.icon, size: 24, color: o.color),
                                ),
                                SizedBox(
                                  height: 28,
                                  child: Text(o.label,
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
                      ),
                  ]);
                }),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

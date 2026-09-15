import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';

typedef _Report = ({String id, String label, IconData icon, String route});

/// `REPORTS` in `frontend/app/(tabs)/reports.tsx` (Expo v2.11.1), in the original order.
const List<_Report> kInstructorReports = [
  (id: 'student-centers', label: 'Student Centers', icon: Ion.businessOutline, route: '/instructor/reports/student-centers'),
  (id: 'training-centers', label: 'Training Centers', icon: Ion.barbellOutline, route: '/instructor/reports/training-centers'),
  (id: 'exam-centers', label: 'Exam Centers', icon: Ion.clipboardOutline, route: '/instructor/reports/exam-centers'),
  (id: 'student-list', label: 'Student List', icon: Ion.peopleOutline, route: '/instructor/reports/student-list'),
  (id: 'training-time', label: 'Training Schedule', icon: Ion.timeOutline, route: '/instructor/reports/training-time'),
  (id: 'grading-schedule', label: 'Grading Schedule', icon: Ion.schoolOutline, route: '/instructor/reports/grading-schedule'),
  (id: 'outstanding', label: 'Outstanding Report', icon: Ion.alertCircleOutline, route: '/instructor/reports/outstanding'),
  (id: 'attendance', label: 'Attendance Report', icon: Ion.checkmarkDoneCircleOutline, route: '/instructor/reports/attendance'),
  (id: 'receipt', label: 'Receipt Report', icon: Ion.receiptOutline, route: '/instructor/reports/receipt'),
  (id: 'grading-past', label: 'Grade Completed', icon: Ion.ribbonOutline, route: '/instructor/reports/grading-past'),
  (id: 'purchase-request', label: 'Purchase Requests', icon: Ion.cartOutline, route: '/instructor/reports/purchase-request'),
  (id: 'payment-slip', label: 'Payment Slips', icon: Ion.documentAttachOutline, route: '/instructor/reports/payment-slip'),
  (id: 'tournament-summary', label: 'Tournament Summary', icon: Ion.trophyOutline, route: '/instructor/reports/tournament-summary'),
  (id: 'contribution', label: 'Contribution Report', icon: Ion.gitCompareOutline, route: '/instructor/reports/contribution'),
  (id: 'reimbursement', label: 'Reimbursement', icon: Ion.cashOutline, route: '/instructor/reports/reimbursement'),
  (id: 'pay-dues', label: 'Pay Your Dues', icon: Ion.cardOutline, route: '/invoices'),
];

/// Port of `frontend/app/(tabs)/reports.tsx` (Expo v2.11.1).
class InstructorReportsScreen extends StatelessWidget {
  const InstructorReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final top = MediaQuery.paddingOf(context).top;
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: c.background,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          color: c.primary,
          padding: EdgeInsets.only(top: top),
          child: Container(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, 6, Gaps.xl, 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
            ),
            child: const Row(children: [
              SizedBox(
                width: 44,
                height: 44,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Color(0x38FFFFFF), shape: BoxShape.circle),
                  child: Icon(Ion.documentText, size: 20, color: Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Reports',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                  SizedBox(height: 3),
                  Text('Tap a report to view details', style: TextStyle(color: Color(0xD9FFFFFF), fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(Gaps.xl, 4, Gaps.xl, tabBarHeight + 24),
            children: [
              for (final r in kInstructorReports)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Touchable(
                    activeOpacity: 0.85,
                    onPress: () => context.push(r.route),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: rnCard(c),
                      child: Row(children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                          child: Icon(r.icon, size: 20, color: c.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(r.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.textPrimary)),
                        ),
                        Icon(Ion.chevronForward, size: 18, color: c.textMuted),
                      ]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ]),
    );
  }
}

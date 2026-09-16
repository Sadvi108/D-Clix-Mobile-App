import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/premium_kit.dart';

typedef InstructorReport = ({String id, String label, String group, IconData icon, Color tint, String route});

const _groupCentres = 'Centres & students';
const _groupClasses = 'Classes & grading';
const _groupFinance = 'Payments & finance';

/// `REPORTS` in `frontend/app/(tabs)/reports.tsx` (Expo v2.11.1), grouped for scanning.
const List<InstructorReport> kInstructorReports = [
  (
    id: 'student-list',
    label: 'Student List',
    group: _groupCentres,
    icon: Ion.peopleOutline,
    tint: PremiumTint.indigo,
    route: '/instructor/reports/student-list'
  ),
  (
    id: 'student-centers',
    label: 'Student Centers',
    group: _groupCentres,
    icon: Ion.businessOutline,
    tint: PremiumTint.sky,
    route: '/instructor/reports/student-centers'
  ),
  (
    id: 'training-centers',
    label: 'Training Centers',
    group: _groupCentres,
    icon: Ion.barbellOutline,
    tint: PremiumTint.orange,
    route: '/instructor/reports/training-centers'
  ),
  (
    id: 'exam-centers',
    label: 'Exam Centers',
    group: _groupCentres,
    icon: Ion.clipboardOutline,
    tint: PremiumTint.teal,
    route: '/instructor/reports/exam-centers'
  ),
  (
    id: 'training-time',
    label: 'Training Schedule',
    group: _groupClasses,
    icon: Ion.timeOutline,
    tint: PremiumTint.amber,
    route: '/instructor/reports/training-time'
  ),
  (
    id: 'attendance',
    label: 'Attendance Report',
    group: _groupClasses,
    icon: Ion.checkmarkDoneCircleOutline,
    tint: PremiumTint.green,
    route: '/instructor/reports/attendance'
  ),
  (
    id: 'grading-schedule',
    label: 'Grading Schedule',
    group: _groupClasses,
    icon: Ion.schoolOutline,
    tint: PremiumTint.violet,
    route: '/instructor/reports/grading-schedule'
  ),
  (
    id: 'grading-past',
    label: 'Grade Completed',
    group: _groupClasses,
    icon: Ion.ribbonOutline,
    tint: PremiumTint.pink,
    route: '/instructor/reports/grading-past'
  ),
  (
    id: 'tournament-summary',
    label: 'Tournament Summary',
    group: _groupClasses,
    icon: Ion.trophyOutline,
    tint: PremiumTint.red,
    route: '/instructor/reports/tournament-summary'
  ),
  (
    id: 'outstanding',
    label: 'Outstanding Report',
    group: _groupFinance,
    icon: Ion.alertCircleOutline,
    tint: PremiumTint.red,
    route: '/instructor/reports/outstanding'
  ),
  (
    id: 'receipt',
    label: 'Receipt Report',
    group: _groupFinance,
    icon: Ion.receiptOutline,
    tint: PremiumTint.sky,
    route: '/instructor/reports/receipt'
  ),
  (
    id: 'payment-slip',
    label: 'Payment Slips',
    group: _groupFinance,
    icon: Ion.documentAttachOutline,
    tint: PremiumTint.violet,
    route: '/instructor/reports/payment-slip'
  ),
  (
    id: 'purchase-request',
    label: 'Purchase Requests',
    group: _groupFinance,
    icon: Ion.cartOutline,
    tint: PremiumTint.amber,
    route: '/instructor/reports/purchase-request'
  ),
  (
    id: 'contribution',
    label: 'Contribution Report',
    group: _groupFinance,
    icon: Ion.gitCompareOutline,
    tint: PremiumTint.teal,
    route: '/instructor/reports/contribution'
  ),
  (
    id: 'reimbursement',
    label: 'Reimbursement',
    group: _groupFinance,
    icon: Ion.cashOutline,
    tint: PremiumTint.green,
    route: '/instructor/reports/reimbursement'
  ),
  (
    id: 'pay-dues',
    label: 'Pay Your Dues',
    group: _groupFinance,
    icon: Ion.cardOutline,
    tint: PremiumTint.orange,
    route: '/invoices'
  ),
];

/// Instructor Reports tab: every report, grouped, with a search box.
class InstructorReportsScreen extends StatefulWidget {
  const InstructorReportsScreen({super.key});

  @override
  State<InstructorReportsScreen> createState() => _InstructorReportsScreenState();
}

class _InstructorReportsScreenState extends State<InstructorReportsScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;
    final q = _search.text.trim().toLowerCase();
    final shown =
        q.isEmpty ? kInstructorReports : kInstructorReports.where((r) => r.label.toLowerCase().contains(q)).toList();
    final groups = <String, List<InstructorReport>>{};
    for (final r in shown) {
      groups.putIfAbsent(r.group, () => []).add(r);
    }

    return ColoredBox(
      color: c.background,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PremiumHeader(
          title: 'Reports',
          subtitle: '${kInstructorReports.length} reports for your club',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0x2EFFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: const Icon(Ion.documentText, size: 20, color: Colors.white),
          ),
          bottom: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.lg),
              boxShadow: Shadows.soft(c),
            ),
            child: Row(children: [
              Icon(Ion.searchOutline, size: 18, color: c.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _search,
                  autocorrect: false,
                  textInputAction: TextInputAction.search,
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(fontSize: 15, color: c.textPrimary),
                  cursorColor: c.primary,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Search reports',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 15),
                  ),
                ),
              ),
              if (_search.text.isNotEmpty)
                Semantics(
                  button: true,
                  label: 'Clear search',
                  child: GestureDetector(
                    onTap: _search.clear,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Ion.closeCircle, size: 18, color: c.textMuted),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        Expanded(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.only(bottom: tabBarHeight + 24),
            children: [
              if (shown.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(children: [
                    Icon(Ion.searchOutline, size: 40, color: c.textMuted),
                    const SizedBox(height: 10),
                    Text('No report matches "${_search.text.trim()}".',
                        textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 14)),
                  ]),
                ),
              for (final entry in groups.entries) ...[
                SectionLabel(entry.key,
                    trailing: Text('${entry.value.length}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c.textMuted))),
                GroupCard(children: [
                  for (final r in entry.value)
                    PremiumRow(icon: r.icon, tint: r.tint, title: r.label, onTap: () => context.push(r.route)),
                ]),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

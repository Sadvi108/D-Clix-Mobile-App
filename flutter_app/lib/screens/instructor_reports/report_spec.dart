import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../services/api.dart';
import 'student_list_fetch.dart';

/// A filter control a report can show.
enum RFilter { trainingCenter, examCenter, dateRange, status, nameText, icText }

/// User-chosen filter values for a report.
class ReportQuery {
  int tCenterId;
  int eCenterId;
  DateTime? fromDate;
  DateTime? toDate;
  String name;
  String ic;
  String? status;

  ReportQuery({
    this.tCenterId = 0,
    this.eCenterId = 0,
    this.fromDate,
    this.toDate,
    this.name = '',
    this.ic = '',
    this.status,
  });
}

typedef SpecFetch = Future<dynamic> Function(ReportQuery q);
typedef RowStatus = String Function(Map row);
typedef RowTap = void Function(BuildContext ctx, Map<String, dynamic> row);

/// Per-report configuration.
class ReportSpec {
  final String title;
  final List<RFilter> filters;
  final SpecFetch fetch;
  final List<String> statusOptions;
  final RowStatus? rowStatus;
  final String statusLabel;
  final bool trainingTimeMode;

  /// Optional row-tap handler — when set, rows become tappable (e.g. open
  /// a per-student detail screen from the Student List report).
  final RowTap? onRowTap;

  const ReportSpec({
    required this.title,
    required this.fetch,
    this.filters = const [],
    this.statusOptions = const [],
    this.rowStatus,
    this.statusLabel = 'Status',
    this.trainingTimeMode = false,
    this.onRowTap,
  });
}

/// Build the `/Reports/*` request body from the chosen filters. Only
/// non-default values are sent; `Api._reportBody` fills the rest.
Map<String, dynamic> reportBody(ReportQuery q) {
  final m = <String, dynamic>{};
  if (q.tCenterId != 0) m['tCenterId'] = q.tCenterId;
  if (q.eCenterId != 0) m['eCenterId'] = q.eCenterId;
  if (q.fromDate != null) {
    final f = q.fromDate!;
    // Start of the picked day.
    m['fromDate'] = DateTime(f.year, f.month, f.day).toIso8601String();
  }
  if (q.toDate != null) {
    final t = q.toDate!;
    // End of the picked day — a midnight toDate would exclude every
    // record timestamped later that same day.
    m['toDate'] =
        DateTime(t.year, t.month, t.day, 23, 59, 59).toIso8601String();
  }
  return m;
}

/// Body for `/Reports/Receipts`. The server filters receipts by payment mode
/// through `reportType`, but only accepts `'Cash'` or `'FPX'` — any other
/// value returns zero rows (a false "no records"). So `reportType` is sent
/// ONLY when one of those two modes is selected; otherwise it is omitted and
/// every receipt is returned.
Map<String, dynamic> receiptReportBody(ReportQuery q) {
  final body = reportBody(q);
  if (q.status == 'Cash' || q.status == 'FPX') {
    body['reportType'] = q.status!;
  }
  return body;
}

/// Specs keyed by the route slug (last path segment of the report route).
/// Routes not present here fall back to a no-filter spec built in the
/// router from a bare fetcher.
final Map<String, ReportSpec> kReportSpecs = {
  'student-list': ReportSpec(
    title: 'Student List',
    filters: const [
      RFilter.trainingCenter,
      RFilter.nameText,
      RFilter.icText,
    ],
    // /Reports/StudentDetails returns the instructor's schedule rows
    // (tCenterName / dayOfWeek / instructorName), NOT students. The
    // aggregator below pulls real students from listingStudentListByTcId
    // and enriches them with stats from /Outstanding/Fetch.
    fetch: fetchInstructorStudentList,
    onRowTap: (ctx, row) => ctx.push('/instructor/student-detail', extra: row),
  ),
  'outstanding': ReportSpec(
    title: 'Outstanding Report',
    filters: const [RFilter.trainingCenter, RFilter.dateRange],
    fetch: (q) {
      final now = DateTime.now();
      final start = q.fromDate != null
          ? DateTime(q.fromDate!.year, q.fromDate!.month, q.fromDate!.day)
              .toIso8601String()
          : DateTime(now.year - 2, 1, 1).toIso8601String();
      final end = q.toDate != null
          ? DateTime(q.toDate!.year, q.toDate!.month, q.toDate!.day, 23, 59, 59)
              .toIso8601String()
          : DateTime(now.year + 2, 12, 31).toIso8601String();
      return Api.outstandingFetch(<String, dynamic>{
        'studentId': 0,
        'studentName': '',
        'icNo': '',
        'startDate': start,
        'endDate': end,
        'eCenterId': 0,
        'tCenterId': q.tCenterId,
        'sCenterId': 0,
        'transactionType': '',
      });
    },
  ),
  'training-time': ReportSpec(
    title: 'Training Time',
    filters: const [RFilter.trainingCenter],
    trainingTimeMode: true,
    fetch: (q) => q.tCenterId == 0
        ? Future<dynamic>.value(const <dynamic>[])
        : Api.listingTrainingTimeByTcId(q.tCenterId),
  ),
  // No grading specs: /Reports/GradingSchedule returns every club's exams, so it is only read
  // through RnApi.gradingSchedule, which scopes it to the instructor's club (RGradingScreen).
  'receipt': ReportSpec(
    title: 'Receipt',
    filters: const [RFilter.trainingCenter, RFilter.dateRange, RFilter.status],
    statusLabel: 'Payment mode',
    // /Reports/Receipts filters by mode server-side via `reportType`, which the
    // server only honours for 'Cash' or 'FPX' (any other value returns zero
    // rows). So those are the only modes we offer, and the filter is applied on
    // the server (no client-side rowStatus filtering — see receiptReportBody).
    statusOptions: const ['Cash', 'FPX'],
    fetch: (q) => Api.reportsReceipts(receiptReportBody(q)),
  ),
  'attendance': ReportSpec(
    title: 'Attendance Report',
    filters: const [RFilter.dateRange],
    fetch: (q) => Api.reportsAttendance(reportBody(q)),
  ),
  'purchase-request': ReportSpec(
    title: 'Purchase Request',
    filters: const [RFilter.trainingCenter, RFilter.status],
    statusLabel: 'Action status',
    statusOptions: const ['Pending', 'Approved', 'Rejected'],
    rowStatus: (r) =>
        (r['actionStatus'] ?? r['status'] ?? r['approvalStatus'] ?? '')
            .toString(),
    fetch: (q) => Api.reportsPurchaseRequests(reportBody(q)),
  ),
  'payment-slip': ReportSpec(
    title: 'Payment Slip',
    filters: const [RFilter.trainingCenter, RFilter.status],
    statusLabel: 'Action status',
    statusOptions: const ['Pending', 'Approved', 'Rejected'],
    rowStatus: (r) =>
        (r['actionStatus'] ?? r['status'] ?? r['approvalStatus'] ?? '')
            .toString(),
    fetch: (q) => Api.reportsPaymentSlips(reportBody(q)),
  ),
  'reimbursement': ReportSpec(
    title: 'Reimbursement',
    filters: const [RFilter.dateRange, RFilter.status],
    statusLabel: 'Status',
    statusOptions: const ['Reimbursed', 'Not Reimbursed'],
    rowStatus: (r) {
      final v = r['isReimbursed'] ?? r['reimbursed'];
      if (v is bool) return v ? 'Reimbursed' : 'Not Reimbursed';
      final s = (r['status'] ?? r['reimbursementStatus'] ?? '')
          .toString()
          .toLowerCase();
      if (s.contains('not')) return 'Not Reimbursed';
      if (s.contains('reimburs')) return 'Reimbursed';
      return '';
    },
    fetch: (q) => Api.reportsReimbursement(reportBody(q)),
  ),
  'contribution': ReportSpec(
    title: 'Contribution',
    filters: const [RFilter.dateRange],
    fetch: (q) => Api.reportsContribution(reportBody(q)),
  ),
};

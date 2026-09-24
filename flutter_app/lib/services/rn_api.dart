import 'api.dart';
import 'api_service.dart';
import 'response_utils.dart';

/// Mirror of the React Native `api` object (`frontend/src/api/endpoints.ts`, Expo v2.11.1).
///
/// RN's `http` layer unwraps the `{status, meta, data}` envelope and throws on an in-envelope
/// error; every method here does the same on top of [Api], so a screen ported from RN makes
/// the same request and receives the same payload shape. Lists come back as
/// `List<Map<String, dynamic>>` (an absent `data` is an empty list, as `?? []` does in RN).
class RnApi {
  RnApi._();

  static List<Map<String, dynamic>> _rows(dynamic resp) {
    final data = unwrapData(resp);
    if (data is! List) return const [];
    return data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  static Map<String, dynamic>? _map(dynamic resp) {
    final data = unwrapData(resp);
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  /// RN `defaultRange()`: last 18 months → end of next year.
  static ({String fromDate, String toDate}) defaultRange() {
    final now = DateTime.now();
    final from = DateTime(now.year, now.month - 18, now.day, now.hour, now.minute, now.second);
    final to = DateTime(now.year + 1, 12, 31);
    return (fromDate: from.toUtc().toIso8601String(), toDate: to.toUtc().toIso8601String());
  }

  /// RN `numericReportType`: some report procedures cast reportType to int.
  static Map<String, dynamic> numericReportType(Map<String, dynamic> body) {
    final rt = body['reportType'];
    final s = rt?.toString().trim() ?? '';
    return {...body, 'reportType': RegExp(r'^-?\d+$').hasMatch(s) ? s : null};
  }

  /// A report POST with only the fields the RN caller sends. [Api]'s report helpers merge
  /// their own defaults (a ±2 year window), which RN never sends — so go direct.
  static Future<dynamic> _report(String path, Map<String, dynamic> body) =>
      ApiService.post(path, body);

  // ── Profile ──
  static Future<Map<String, dynamic>?> myInfo() async => _map(await Api.profileMyInfo());
  static Future<Map<String, dynamic>?> studentAddtnlInfo() async =>
      _map(await Api.profileStudentAddtnlInfo());
  static Future<List<Map<String, dynamic>>> myClubStats() async => _rows(await Api.profileMyClubStats());
  static Future<List<Map<String, dynamic>>> myNotifications() async =>
      _rows(await Api.profileMyNotifications());
  static Future<List<Map<String, dynamic>>> mySiblings() async => _rows(await Api.listingMySiblings());

  // ── Home / Reports ──
  static Future<Map<String, dynamic>?> homePageStats() async => _map(await Api.reportsHomePageStats());
  static Future<List<Map<String, dynamic>>> receipts(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/Receipts', body));
  static Future<List<Map<String, dynamic>>> attendanceReport(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/Attendance', body));
  static Future<List<Map<String, dynamic>>> gradingSchedule(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/GradingSchedule', body));
  static Future<List<Map<String, dynamic>>> tournamentSummary(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/TournamentSummary', numericReportType(body)));
  static Future<List<Map<String, dynamic>>> purchaseRequests(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/PurchaseRequests', body));
  static Future<List<Map<String, dynamic>>> studentDetails(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/StudentDetails', body));
  static Future<List<Map<String, dynamic>>> paymentSlips(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/PaymentSlips', body));
  static Future<List<Map<String, dynamic>>> reimbursementReport(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/Reimbursement', numericReportType(body)));
  static Future<List<Map<String, dynamic>>> activityReport(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/Activity', body));
  static Future<List<Map<String, dynamic>>> contributionReport(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/Contribution', numericReportType(body)));
  static Future<List<Map<String, dynamic>>> reportTrainingCenters() async =>
      _rows(await Api.reportsTrainingCenters());
  static Future<List<Map<String, dynamic>>> reportExamCenters() async => _rows(await Api.reportsExamCenters());
  static Future<List<Map<String, dynamic>>> reportStudentCenters() async =>
      _rows(await Api.reportsStudentCenters());

  // ── Help desk ──
  static Future<dynamic> send2ClubHelpDesk(Map<String, dynamic> body) async =>
      unwrapData(await Api.profileSend2ClubHelpDesk(body));

  // ── Outstanding (fees) ──
  static Future<List<Map<String, dynamic>>> outstanding(
          {int? studentId, String? startDate, String? endDate}) async =>
      _rows(await Api.outstandingFetch({'studentId': studentId, 'startDate': startDate, 'endDate': endDate}));

  // ── Listings ──
  static Future<List<Map<String, dynamic>>> trainingCenters() async => _rows(await Api.listingTrainingCenters());
  static Future<List<Map<String, dynamic>>> studentCenters() async => _rows(await Api.listingStudentCenters());
  static Future<List<Map<String, dynamic>>> instructors() async => _rows(await Api.listingInstructors());
  static Future<List<Map<String, dynamic>>> dropdownListByType(Object typeId) async =>
      _rows(await Api.listingDropdownListByType(typeId));

  /// The instructor's training centres as `{id, text}` rows — the one source every centre
  /// picker and centre fan-out reads.
  ///
  /// `/Listing/DropdownListByType/3` is what RN used, but routes in that family can answer with
  /// `data` omitted entirely (ARCHITECTURE.md records type 6 doing exactly that), and an empty
  /// answer left every instructor report with a dead "Training Center" picker — which also locks
  /// the Attendance report's Training Time and Student selects, since both unlock off the centre
  /// (manual QA 2026-09-24). `/Listing/TrainingCenters` answers the same question and is what
  /// `student_list_fetch.dart` already trusts, so fall back to it. The two routes disagree on key
  /// spelling, hence [_centreRows].
  static Future<List<Map<String, dynamic>>> trainingCentres() async {
    final primary = _centreRows(await Api.listingDropdownListByType(3));
    return primary.isNotEmpty ? primary : _centreRows(await Api.listingTrainingCenters());
  }

  /// `id` keeps its original type — callers compare it as both a number and a string.
  static List<Map<String, dynamic>> _centreRows(dynamic resp) => [
        for (final r in findRecordList(resp).whereType<Map>())
          if ((r['id'] ?? r['centerId'] ?? r['tCenterId'] ?? r['value']) case final id?
              when '$id'.trim().isNotEmpty)
            {'id': id, 'text': pickField(r, ['text', 'name', 'centerName', 'tCenterName'])},
      ];
  static Future<List<Map<String, dynamic>>> studentListByTcId(int tCenterId) async =>
      _rows(await Api.listingStudentListByTcId(tCenterId));
  static Future<List<Map<String, dynamic>>> trainingTimeByTcId(int tCenterId) async =>
      _rows(await Api.listingTrainingTimeByTcId(tCenterId));
  static Future<List<Map<String, dynamic>>> invoiceTypes() async => _rows(await Api.listingInvoceTypes());

  // ── Class booking ──
  static Future<List<Map<String, dynamic>>> getBookings() async => _rows(await Api.classBookingGetBookings());

  // ── Instructor: collections ──
  static Future<Map<String, dynamic>?> collectionCount() async => _map(await Api.outstandingCollectionCount());
  static Future<List<Map<String, dynamic>>> collectionCountList(int typeId) async =>
      _rows(await Api.outstandingCollectionCountList(typeId));
  static Future<dynamic> updateCollectionCount(int typeId) async =>
      unwrapData(await Api.outstandingUpdateCollectionCount(typeId));

  // ── Purchases ──
  static Future<List<Map<String, dynamic>>> purchaseProducts() async =>
      _rows(await Api.purchaseRequestFetchProducts({}));

  // ── Utilities (public URLs, no auth) ──
  static String receiptPdfUrl(int clubId, int paymentId, int invoiceId) =>
      '${ApiService.baseUrl}/Utilities/ReceiptAsPDF/$clubId/$paymentId/$invoiceId';
  static String qrCodeUrl(Object content, [int size = 300]) =>
      '${ApiService.baseUrl}/Utilities/QRCode/$size/$size/${Uri.encodeComponent('$content')}';
  static String trainingCenterQRCodeUrl(int clubId, int tcid) =>
      '${ApiService.baseUrl}/Utilities/TrainingCenterQRCode/$clubId/$tcid';

  /// RN `Number(x)` for an API field: numbers pass, numeric strings parse, anything else 0.
  static num number(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim()) ?? 0;
    return 0;
  }
}

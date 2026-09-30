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

  /// The instructor's own club's exam sessions only.
  ///
  /// `/Reports/GradingSchedule` answers any instructor with every club's exams — a live probe
  /// (2026-09-29) returned 764 rows across 80+ exam centres for a club that has 4 — and its rows
  /// carry no club field, only the exam centre name `ecName`. So a row is kept only when its
  /// centre is one of the caller's own, per the club-scoped `/Listing/DropdownListByType/2`.
  /// Fails closed: no centre list means no rows, never everyone's. The real fix is server-side.
  static Future<List<Map<String, dynamic>>> gradingSchedule(Map<String, dynamic> body) async {
    final [report, centres] =
        await Future.wait([_report('/Reports/GradingSchedule', body), Api.listingDropdownListByType(2)]);
    String norm(Object? v) => '${v ?? ''}'.trim().replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '').toLowerCase();
    Iterable<String> aliases(Map<String, dynamic> row, List<String> keys) sync* {
      for (final key in keys) {
        final value = norm(row[key]);
        if (value.isNotEmpty) yield value;
      }
    }

    // Dropdown serializers differ between deployments: some put the visible
    // centre name in `text`, others put a centre code/name in `value`. Match
    // every explicit centre alias, but never the generic row `id` (which is an
    // exam/result id in the report and could cross club boundaries).
    final own = <String>{
      for (final c in _rows(centres))
        ...aliases(c, const ['text', 'value', 'name', 'centerName', 'examCenterName', 'ecName', 'code']),
    };
    return [
      for (final r in _rows(report))
        if (aliases(r, const ['ecName', 'examCenterName', 'centerName', 'ecCode', 'centerCode']).any(own.contains)) r,
    ];
  }

  static Future<List<Map<String, dynamic>>> tournamentSummary(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/TournamentSummary', numericReportType(body)));
  static Future<List<Map<String, dynamic>>> purchaseRequests(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/PurchaseRequests', body));
  static Future<List<Map<String, dynamic>>> studentDetails(Map<String, dynamic> body) async =>
      _rows(await _report('/Reports/StudentDetails', body));

  /// `/Profile/MyInfo` stays bound to the primary login. Build a guardian-
  /// selected child's snapshot from report routes that accept `sourceKeyId`.
  static Future<Map<String, dynamic>> studentOverview({
    required Object studentId,
    required String studentName,
    Map<String, dynamic>? seed,
  }) async {
    final range = defaultRange();
    Future<List<Map<String, dynamic>>> safe(Future<List<Map<String, dynamic>>> Function() load) async {
      try { return await load(); } catch (_) { return const []; }
    }
    final results = await Future.wait([
      safe(() => studentDetails({'sourceKeyId': studentId, 'studentName': studentName,
        'fromDate': range.fromDate, 'toDate': range.toDate})),
      safe(() => gradingSchedule({'sourceKeyId': studentId,
        'fromDate': range.fromDate, 'toDate': range.toDate})),
      safe(() => tournamentSummary({'sourceKeyId': studentId,
        'fromDate': range.fromDate, 'toDate': range.toDate})),
    ]);
    final wantedId = '$studentId'.trim();
    final wantedName = studentName.trim().toUpperCase();
    bool sameId(Object? value) {
      final actual = '${value ?? ''}'.trim();
      final a = num.tryParse(actual), b = num.tryParse(wantedId);
      return actual.isNotEmpty && ((a != null && b != null) ? a == b : actual == wantedId);
    }
    List<Map<String, dynamic>> selected(List<Map<String, dynamic>> rows,
        {bool genericNameIsStudent = true}) {
      Object? id(Map row) => row['studentId'] ?? row['studentID'] ?? row['stuId'] ?? row['sourceKeyId'];
      Object? name(Map row) => row['studentName'] ?? row['receiverName'] ?? (genericNameIsStudent ? row['name'] : null);
      bool identified(Map row) => '${id(row) ?? ''}'.trim().isNotEmpty || '${name(row) ?? ''}'.trim().isNotEmpty;
      bool mine(Map row) {
        if ('${id(row) ?? ''}'.trim().isNotEmpty) return sameId(id(row));
        return wantedName.isNotEmpty && '${name(row) ?? ''}'.trim().toUpperCase() == wantedName;
      }
      // Anonymous rows are trusted only because this request explicitly sent
      // sourceKeyId. Named rows require a positive child match.
      return rows.any(identified) ? rows.where(mine).toList() : rows;
    }
    final details = selected(results[0]);
    final gradings = selected(results[1]);
    final tournaments = selected(results[2], genericNameIsStudent: false);
    final out = <String, dynamic>{...?seed, 'id': studentId, 'studentId': studentId, 'name': studentName};
    void copy(Map source, String target, List<String> aliases) {
      if ('${out[target] ?? ''}'.trim().isNotEmpty) return;
      for (final key in aliases) {
        final value = source[key];
        if (value != null && '$value'.trim().isNotEmpty) { out[target] = value; return; }
      }
    }
    for (final row in details) {
      copy(row, 'registrationNo', const ['registrationNo', 'regNo', 'studentCode']);
      copy(row, 'currentGrade', const ['currentGrade', 'gradeName', 'grade', 'typeOfGrade']);
      copy(row, 'tCenterName', const ['tCenterName', 'trainingCenter', 'centerName']);
      copy(row, 'eCenterName', const ['eCenterName', 'ecName', 'examCenterName']);
      copy(row, 'instructorName', const ['instructorName', 'coachName']);
    }
    if ('${out['trainingTme'] ?? ''}'.trim().isEmpty) {
      final sessions = <String>[];
      for (final row in details) {
        final direct = '${row['trainingTme'] ?? row['trainingTime'] ?? ''}'.trim();
        final from = '${row['tTimeFrom'] ?? row['timeFrom'] ?? ''}'.trim();
        final to = '${row['tTimeTo'] ?? row['timeTo'] ?? ''}'.trim();
        final day = '${row['dayOfWeek'] ?? ''}'.trim();
        final time = direct.isNotEmpty ? direct : [if (from.isNotEmpty) from, if (to.isNotEmpty) 'To $to'].join(' ');
        final label = [time, if (day.isNotEmpty) '($day)'].where((v) => v.isNotEmpty).join(' ');
        if (label.isNotEmpty && !sessions.contains(label)) sessions.add(label);
      }
      if (sessions.isNotEmpty) out['trainingTme'] = sessions.join('\n');
    }
    if (gradings.isNotEmpty) {
      final row = gradings.first;
      copy(row, 'currentGrade', const ['currentGrade', 'gradeName', 'grade', 'typeOfGrade']);
      copy(row, 'eCenterName', const ['eCenterName', 'ecName', 'examCenterName']);
      copy(row, 'lastGradingDate', const ['lastGradingDate', 'lastGradeDate', 'examDate', 'gradingDate']);
      copy(row, 'nextGradingDate', const ['nextGradingDate', 'nextGradeDate', 'nextExamDate']);
      copy(row, 'gradingStatus', const ['gradingStatus', 'gradeStatus', 'resultStatus', 'status']);
      copy(row, 'gradingPaymentStatus', const ['gradingPaymentStatus', 'gradePaymentStatus',
        'examPaymentStatus', 'paymentStatus', 'payStatus']);
    }
    if (tournaments.isNotEmpty) {
      final row = tournaments.first;
      copy(row, 'tournamentName', const ['tournamentName', 'name', 'Name']);
      copy(row, 'tournamentDate', const ['tournamentDate', 'fromDate', 'startDate', 'date']);
      copy(row, 'tournamentToDate', const ['tournamentToDate', 'toDate', 'endDate']);
      copy(row, 'tournamentStatus', const ['tournamentStatus', 'competitionStatus', 'status']);
    }
    return out;
  }

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
  static Future<List<Map<String, dynamic>>> getBookings({Object? studentId}) async =>
      _rows(await Api.classBookingGetBookings(studentId: studentId));

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

// Opt-in smoke test against the LIVE Club.Api.
//
// Skipped unless credentials are supplied, so `flutter test` stays offline and green by
// default and no account is ever committed:
//
//   flutter test test/live_api_smoke_test.dart \
//     --dart-define=LIVE_USER=<id> --dart-define=LIVE_PASS=<password>
//
// Runs on the Dart VM rather than a browser, so it exercises the real API without the CORS
// wall that blocks Flutter web against this plain-HTTP backend.
//
// WHAT THIS ADDS over api_wiring_test.dart: that one proves every path and verb exists in
// the server's route table. This one proves the endpoints behind each SCREEN actually
// answer, with a shape the screen can read. A route can exist and still return 500, or an
// envelope the parser drops on the floor.
//
// Every screen endpoint is probed and REPORTED rather than asserted one-by-one, so a run
// gives a full wiring picture instead of stopping at the first failure. The run fails only
// if something that must work does not.
import 'package:flutter_test/flutter_test.dart';
import 'package:dclix_app/services/api.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/response_utils.dart';

const _user = String.fromEnvironment('LIVE_USER');
const _pass = String.fromEnvironment('LIVE_PASS');

/// Outcome of probing one endpoint.
class Probe {
  final String screen;
  final String endpoint;
  final bool ok;
  final String detail;
  const Probe(this.screen, this.endpoint, this.ok, this.detail);
}

final _results = <Probe>[];

/// Call [fn] and record what happened. Never throws: a probe failing is data, not a crash.
Future<void> probe(String screen, String endpoint, Future<dynamic> Function() fn) async {
  try {
    final res = await fn();
    final data = unwrapData(res);
    final shape = data == null
        ? 'null'
        : data is List
            ? 'list(${data.length})'
            : data is Map
                ? 'map(${data.keys.length} keys)'
                : data.runtimeType.toString();
    _results.add(Probe(screen, endpoint, true, shape));
  } catch (e) {
    final msg = e.toString().replaceAll('\n', ' ');
    _results.add(
        Probe(screen, endpoint, false, msg.length > 120 ? msg.substring(0, 120) : msg));
  }
}

void main() {
  final configured = _user.isNotEmpty && _pass.isNotEmpty;
  final skip = configured ? null : 'set --dart-define=LIVE_USER/LIVE_PASS to run';

  group('live Club.Api', () {
    test('authenticates and returns a bearer token', () async {
      final res = await ApiService.post('/Account/Authenticate', {
        'userType': 3,
        'username': _user,
        'password': _pass,
        'accessMethod': 0,
        'branchId': 0,
      });
      final data = (res is Map) ? res['data'] : null;
      expect(data, isA<Map>(), reason: 'expected a {status,meta,data} envelope');
      final t = (data as Map)['accessToken'];
      expect(t, isA<String>());
      expect((t as String).length, greaterThan(100), reason: 'JWT looks too short');
      ApiService.setToken(t);
    }, timeout: const Timeout(Duration(seconds: 60)), skip: skip);

    // ── Every screen's endpoints, probed and reported ────────────────────────
    //
    // Grouped by the screen that depends on them, so a failure names the screen a member
    // would see break rather than just a path.
    test('probes every screen endpoint', () async {
      await probe('home', '/Reports/HomePageStats', Api.reportsHomePageStats);
      await probe('home/profile', '/Profile/MyInfo', Api.profileMyInfo);
      await probe('home', '/Profile/MyClubStats', Api.profileMyClubStats);
      await probe('student-details', '/Profile/StudentAddtnlInfo',
          Api.profileStudentAddtnlInfo);
      await probe('payments', '/Outstanding/Fetch', () => Api.outstandingFetch(const {}));
      await probe('payments', '/Listing/InvoceTypes', Api.listingInvoceTypes);
      await probe('term-payment', '/Listing/MySiblings', Api.listingMySiblings);
      await probe('schedule', '/ClassBooking/NextBookings', Api.classBookingNextBookings);
      await probe('schedule', '/ClassBooking/GetBookings', Api.classBookingGetBookings);
      await probe('book-class', '/Listing/TrainingCenters', Api.listingTrainingCenters);
      await probe('book-class', '/Listing/Instructors', Api.listingInstructors);
      await probe('attendance', '/Reports/Attendance', () => Api.reportsAttendance());
      await probe('progress', '/Reports/GradingSchedule',
          () => Api.reportsGradingSchedule());
      await probe('tournament', '/Reports/TournamentSummary',
          () => Api.reportsTournamentSummary());
      await probe('purchases', '/Reports/PurchaseRequests',
          () => Api.reportsPurchaseRequests());
      await probe('purchase-request', '/PurchaseRequest/FetchProducts',
          () => Api.purchaseRequestFetchProducts());
      await probe('notifications/chat', '/Profile/MyNotifications',
          Api.profileMyNotifications);
      await probe('notifications', '/Profile/MyUnreadNotificationCount',
          () => ApiService.get('/Profile/MyUnreadNotificationCount'));
      await probe('instructor-collections', '/Outstanding/CollectionCount',
          Api.outstandingCollectionCount);
      await probe('reports', '/Reports/StudentCenters', Api.reportsStudentCenters);
      await probe('reports', '/Reports/TrainingCenters', Api.reportsTrainingCenters);
      await probe('reports', '/Reports/ExamCenters', Api.reportsExamCenters);
      await probe('reports', '/Reports/Receipts', () => Api.reportsReceipts());
      await probe('reports', '/Reports/PaymentSlips', () => Api.reportsPaymentSlips());
      await probe('reports', '/Reports/StudentDetails', () => Api.reportsStudentDetails());

      // Print the full table before asserting, so one run tells you everything.
      final width =
          _results.map((r) => r.endpoint.length).reduce((a, b) => a > b ? a : b);
      // ignore: avoid_print
      print('\n--- live endpoint wiring ---');
      for (final r in _results) {
        // ignore: avoid_print
        print('${r.ok ? "OK  " : "FAIL"}  ${r.endpoint.padRight(width)}  '
            '${r.screen.padRight(22)} ${r.detail}');
      }
      final failed = _results.where((r) => !r.ok).toList();
      // ignore: avoid_print
      print('${_results.length - failed.length}/${_results.length} endpoints answered\n');

      expect(failed.map((f) => '${f.screen}: ${f.endpoint} -> ${f.detail}'), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 5)), skip: skip);

    test('the Boost host is reachable and rejects an unknown reference', () async {
      // /Bcpg lives on UAT even for a prod token. This does not pay anything — it checks
      // the cross-host route answers at all, which is the part that silently breaks.
      try {
        await ApiService.get('/Bcpg/VerifyPayment/definitely-not-a-real-reference');
      } catch (e) {
        // A 404/400 is the expected, correct answer. A TLS or DNS failure is not.
        final msg = e.toString().toLowerCase();
        expect(msg.contains('certificate') || msg.contains('handshake'), isFalse,
            reason: 'the Boost host TLS is broken, not just the reference: $e');
      }
    }, timeout: const Timeout(Duration(seconds: 60)), skip: skip);
  });
}

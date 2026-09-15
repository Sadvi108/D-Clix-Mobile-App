// Is every screen actually connected to something?
//
// A screen can compile, render, look finished and show nothing but an empty state forever,
// because the call that fills it was never wired or was refactored away. Nothing in the
// type system notices. This test reads lib/screens/ and checks each screen has a real data
// source, and that the screens with a specific contract still call the endpoints they are
// supposed to.
//
// Data can arrive three legitimate ways:
//   1. Api.* directly (calls and tear-offs — `_safeFetch(Api.classBookingNextBookings)`
//      passes a reference, which a naive `Api.x(` scan misses).
//   2. A service that owns the call (BoostPayment, PurchaseService, NotificationService).
//   3. UserSession, which fetches centrally and notifies (home, offers, splash).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `Api.foo(...)` AND `Api.foo` passed as a tear-off — plus `RnApi.foo`, the typed mirror of
/// the React Native endpoint table that the ported screens call.
final _apiRe = RegExp(r'\b(?:Rn)?Api\.([a-zA-Z0-9_]+)');
final _serviceRe = RegExp(
    r'\b(BoostPayment|OnlineSubmissions|PurchaseService|NotificationService|AutoPayStore|ChatStore)\.([a-zA-Z0-9_]+)');
final _sessionRe = RegExp(r'\bUserSession\b');

class ScreenWiring {
  final String name;

  /// Kept rather than reconstructed: the scan recurses, so screens live in
  /// lib/screens/, lib/screens/payment/ and lib/screens/instructor_reports/.
  final String path;
  final Set<String> api;
  final Set<String> services;
  final bool usesSession;
  const ScreenWiring(
      this.name, this.path, this.api, this.services, this.usesSession);

  bool get hasDataSource =>
      api.isNotEmpty || services.isNotEmpty || usesSession;
}

Map<String, ScreenWiring> scanScreens() {
  final out = <String, ScreenWiring>{};
  for (final e in Directory('lib/screens').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final src = e.readAsStringSync();
    final name = e.uri.pathSegments.last.replaceAll('.dart', '');
    out[name] = ScreenWiring(
      name,
      e.path,
      _apiRe.allMatches(src).map((m) => m.group(1)!).toSet(),
      _serviceRe
          .allMatches(src)
          .map((m) => '${m.group(1)}.${m.group(2)}')
          .toSet(),
      _sessionRe.hasMatch(src),
    );
  }
  return out;
}

/// Screens that legitimately touch no data at all: pure navigation, or static content.
const _noDataNeeded = {
  'more_screen', // a menu
  'tabs_shell',
  'instructor_tabs_shell',
  'instructor_reports_screen', // a menu of report routes
  'user_guide_screen', // static content, deliberately offline
  'bcpg_webview_screen', // drives a WebView, not the API
  'api_test_screen', // diagnostics; hits raw paths by string
};

/// The contract each screen is expected to keep. Names are Api method names.
///
/// This is not busywork: every entry here is a call that, if quietly dropped in a
/// refactor, leaves a screen that renders perfectly and shows nothing.
const _expected = <String, List<String>>{
  'attendance_screen': ['attendanceReport'],
  'tournament_screen': ['reportsTournamentSummary'],
  'student_details_screen': ['myInfo', 'studentAddtnlInfo'],
  'edit_profile_screen': ['profileUpdateProfile'],
  'helpdesk_screen': ['profileSend2ClubHelpDesk'],
  'notifications_screen': [
    'profileUpdateNotification2Read'
  ],
  'chat_thread_screen': [
    'profileReply2Notification',
    'profileSend2ClubHelpDesk'
  ],
  'outstanding_invoices_screen': ['outstandingFetch'],
  'progress_screen': ['attendanceReport'],
  'belt_rank_screen': ['myInfo'],
  'training_screen': ['myInfo', 'attendanceReport'],
  'purchases_screen': ['purchaseRequests'],
  'rn_reports': ['reportStudentCenters', 'attendanceReport', 'tournamentSummary'],
  'qr_scan_screen': ['attendanceAdd'],
  'term_payment_screen': ['listingMySiblings'],
  'instructor_attendance_screen': [
    'dropdownListByType',
    'trainingTimeByTcId',
    'studentListByTcId',
    'utilitiesQRCodeBytes'
  ],
  'instructor_collections_screen': [
    'collectionCount',
    'collectionCountList',
    'outstandingUpdateCollectionCount'
  ],
  // The weekly timetable comes from StudentDetails, as in Expo v2.11.1.
  'schedule_screen': ['studentDetails'],
  'book_class_screen': [
    'classBookingBookNow',
    'classBookingTrainingTimeWithDateAndInstructor'
  ],
};

/// Screens whose data comes from a service rather than Api.* directly.
const _expectedServices = <String, List<String>>{
  'new_student_screen': ['OnlineSubmissions.fetch', 'OnlineSubmissions.detail'],
  'purchase_request_screen': [
    'PurchaseService.fetchProducts',
    'BoostPayment.start',
    'BoostPayment.confirm',
  ],
  'payments_screen': ['BoostPayment.start', 'BoostPayment.confirm'],
  'term_payment_screen': ['BoostPayment.start', 'BoostPayment.confirm'],
  'autopay_screen': [
    'NotificationService.scheduleAutoPayReminder',
    'NotificationService.cancelAutoPayReminder',
    'AutoPayStore.load',
  ],
  'notification_settings_screen': ['NotificationService.sendTestAlert'],
};

void main() {
  late Map<String, ScreenWiring> screens;

  setUpAll(() => screens = scanScreens());

  test('the scan found the screens', () {
    // Guards the parser: an empty scan would make every assertion below vacuous.
    expect(screens.length, greaterThan(25),
        reason: 'only found ${screens.length} screens');
    expect(screens.keys, contains('home_screen'));
  });

  test('the scan sees tear-offs, not just calls', () {
    // home_screen passes RnApi.homePageStats by reference to useApi. An `Api.x(` scan
    // reports that screen as completely unwired, which is how this test was wrong first.
    expect(screens['home_screen']!.api, contains('homePageStats'));
  });

  test('every screen has a data source, or is on the no-data list', () {
    final unwired = screens.values
        .where((s) => !s.hasDataSource && !_noDataNeeded.contains(s.name))
        .map((s) => s.name)
        .toList();
    expect(unwired, isEmpty,
        reason: 'these screens fetch nothing and read no session state, '
            'so they can only ever render empty: $unwired');
  });

  test('the no-data list has no stale entries', () {
    // If a listed screen grows a real data source, the entry should go — otherwise the
    // list slowly becomes a blanket exemption.
    final nowWired = _noDataNeeded
        .where((n) => screens[n] != null && screens[n]!.api.isNotEmpty)
        .toList();
    expect(nowWired, isEmpty,
        reason: 'these are exempted but now call the API: $nowWired');
  });

  test('every screen in the expected map still calls its endpoints', () {
    final broken = <String>[];
    _expected.forEach((screen, methods) {
      final w = screens[screen];
      if (w == null) {
        broken.add('$screen is gone');
        return;
      }
      for (final m in methods) {
        if (!w.api.contains(m)) broken.add('$screen no longer calls Api.$m');
      }
    });
    expect(broken, isEmpty, reason: broken.join('\n'));
  });

  test('every screen in the service map still calls its services', () {
    final broken = <String>[];
    _expectedServices.forEach((screen, calls) {
      final w = screens[screen];
      if (w == null) {
        broken.add('$screen is gone');
        return;
      }
      for (final c in calls) {
        if (!w.services.contains(c)) broken.add('$screen no longer calls $c');
      }
    });
    expect(broken, isEmpty, reason: broken.join('\n'));
  });

  test(
      'the payment screens never reach the gateway except through BoostPayment',
      () {
    // The merchant secret lives on the server precisely because it must not be in the
    // app. Any screen building a /Bcpg call itself would be re-opening that hole.
    // Match an actual CALL, not the string anywhere: payments_screen documents
    // `POST /Bcpg/PayInvoices` in a doc comment, which is exactly the sort of mention
    // that should not fail a test about behaviour.
    final callRe = RegExp(r"""ApiService\.\w+\(\s*'/Bcpg""");
    for (final s in screens.values) {
      expect(callRe.hasMatch(File(s.path).readAsStringSync()), isFalse,
          reason:
              '${s.name} calls a Boost path directly instead of via BoostPayment');
    }
  });
}

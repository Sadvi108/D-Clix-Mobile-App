// Render smoke tests for the screens that need no network.
//
// A Dart analyzer error is not the failure mode that reaches members — an unbounded-height
// Column, a null-deref in a builder or an overflow is, and none of those show up until the
// widget is actually laid out.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:dclix_app/screens/belt_rank_screen.dart';
import 'package:dclix_app/screens/offer_detail_screen.dart';
import 'package:dclix_app/screens/offers_screen.dart';
import 'package:dclix_app/screens/progress_screen.dart';
import 'package:dclix_app/screens/student_details_screen.dart';
import 'package:dclix_app/screens/tournament_screen.dart';
import 'package:dclix_app/screens/user_guide_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';

Widget _wrap(Widget child) => ChangeNotifierProvider<UserSession>.value(
      value: UserSession.instance,
      // A router, because the progress screens link out with context.push / context.go.
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [GoRoute(path: '/', builder: (_, __) => child)]),
      ),
    );

MockClient _api(Map<String, Object?> routes) => MockClient((req) async => routes.containsKey(req.url.path)
    ? http.Response(jsonEncode({'status': 200, 'data': routes[req.url.path]}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'})
    : http.Response('not stubbed', 404));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  setUp(() {
    UserSession.instance.myInfo = null;
    UserSession.instance.homeStats = null;
    UserSession.instance.studentAddtnlInfo = null;
  });

  group('UserGuideScreen', () {
    testWidgets('opens on the sign-in page and pages forward to the end', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const UserGuideScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Signing in'), findsOneWidget);
      expect(find.text('STEP 1 OF 12'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Walk every page: each one lays out its own steps, tips and callout.
      for (var i = 2; i <= 12; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('STEP $i OF 12'), findsOneWidget, reason: 'stuck before page $i');
        expect(tester.takeException(), isNull, reason: 'page $i threw');
      }
      // The last page offers Got it, not Next.
      expect(find.text('Got it'), findsOneWidget);
    });
  });

  group('OffersScreen', () {
    testWidgets('with no offers it says so rather than rendering blank', (tester) async {
      await tester.pumpWidget(_wrap(const OffersScreen()));
      await tester.pump();
      expect(find.text('No offers right now.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders an offer and flags an expired one', (tester) async {
      UserSession.instance.homeStats = {
        'myoffers': [
          {'code': 'A1', 'title': 'Raya Special', 'description': '20% off'},
          {'code': 'B2', 'title': 'Old Deal', 'expiryDate': '2020-01-01T00:00:00'},
        ]
      };
      await tester.pumpWidget(_wrap(const OffersScreen()));
      await tester.pump();
      expect(find.text('Raya Special'), findsOneWidget);
      expect(find.text('Expired'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('OfferDetailScreen', () {
    testWidgets('an unknown code shows not-found, never another offer', (tester) async {
      // The regression that matters: this screen is the voucher shown at the counter,
      // so falling back to "the first offer" would present someone else's terms.
      UserSession.instance.homeStats = {
        'myoffers': [
          {'code': 'REAL', 'title': 'Members Only 30%'},
        ]
      };
      await tester.pumpWidget(_wrap(const OfferDetailScreen(code: 'GONE')));
      await tester.pump();
      expect(find.text('Offer not found'), findsOneWidget);
      expect(find.text('Members Only 30%'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the matching offer renders with its voucher strip', (tester) async {
      UserSession.instance.homeStats = {
        'myoffers': [
          {'code': 'REAL', 'title': 'Members Only 30%', 'expiryDate': '2099-06-01T00:00:00'},
        ]
      };
      UserSession.instance.myInfo = {'name': 'Test Member', 'registrationNo': 'D-123'};
      await tester.pumpWidget(_wrap(const OfferDetailScreen(code: 'REAL')));
      await tester.pump();
      expect(find.text('Members Only 30%'), findsOneWidget);
      expect(find.text('REAL'), findsOneWidget);
      expect(find.text('Show this screen to redeem'), findsOneWidget);
      expect(find.text('01 Jun 2099'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('StudentDetailsScreen', () {
    // Both API calls fail in a test (no network), which is exactly the flaky-connection
    // case this guards.
    testWidgets('a failed refresh does not put a red error over good cached data', (tester) async {
      UserSession.instance.myInfo = {
        'name': 'Alex Tan',
        'registrationNo': 'DCX-0001',
        'currentGrade': 'Green Belt',
      };
      await tester.pumpWidget(_wrap(const StudentDetailsScreen()));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }

      expect(find.text('Alex Tan'), findsOneWidget);
      expect(find.textContaining('Could not load'), findsNothing,
          reason: 'the details rendered fine; an error banner reads as "my record is broken"');
      expect(tester.takeException(), isNull);
    });

    testWidgets('with nothing cached it DOES report the failure', (tester) async {
      // The opposite case still has to work — silence here would be a blank screen with
      // no explanation.
      UserSession.instance.myInfo = null;
      UserSession.instance.studentAddtnlInfo = null;
      UserSession.instance.authData = null;
      await tester.pumpWidget(_wrap(const StudentDetailsScreen()));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(find.textContaining('Could not load'), findsOneWidget);
    });
  });

  group('BeltRankScreen', () {
    late http.Client original;
    setUp(() => original = ApiService.client);
    tearDown(() {
      ApiService.client = original;
      UserSession.instance.activeStudentName = null;
    });

    testWidgets('shows the exact grade with its sub-rank and no invented next belt', (tester) async {
      ApiService.client = _api({
        '/Profile/MyInfo': {'name': 'Alex Tan', 'currentGrade': 'Grade 5 (Green 2)'}
      });
      await tester.pumpWidget(_wrap(const BeltRankScreen()));
      await _settle(tester);
      expect(find.text('Grade 5 (Green 2)'), findsOneWidget);
      expect(find.textContaining('Next'), findsNothing);
      expect(find.text('Belt Journey'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a successful empty grade replaces a cached one', (tester) async {
      UserSession.instance.myInfo = {'name': 'Alex Tan', 'currentGrade': 'Grade 8 (Yellow)'};
      ApiService.client = _api({
        '/Profile/MyInfo': {'name': 'Alex Tan', 'currentGrade': ''}
      });
      await tester.pumpWidget(_wrap(const BeltRankScreen()));
      await _settle(tester);
      expect(find.text('Grade 8 (Yellow)'), findsNothing);
      expect(find.text('Not recorded'), findsOneWidget);
    });

    testWidgets("a selected sibling never sees the account holder's grade", (tester) async {
      UserSession.instance.myInfo = {'name': 'Alex Tan', 'currentGrade': 'Grade 8 (Yellow)'};
      UserSession.instance.activeStudentName = 'Mia Tan';
      ApiService.client = _api({
        '/Profile/MyInfo': {'name': 'Alex Tan', 'currentGrade': 'Grade 8 (Yellow)'}
      });
      await tester.pumpWidget(_wrap(const BeltRankScreen()));
      await _settle(tester);
      expect(find.text('Grade 8 (Yellow)'), findsNothing);
      expect(find.textContaining("isn't available"), findsOneWidget);
    });
  });

  group('ProgressScreen', () {
    late http.Client original;
    setUp(() => original = ApiService.client);
    tearDown(() {
      ApiService.client = original;
      UserSession.instance.activeStudentName = null;
    });

    String daysAgo(int d) => DateTime.now().subtract(Duration(days: d)).toIso8601String();

    testWidgets('anonymous rows count for the member; rate uses Present and Absent only', (tester) async {
      UserSession.instance.myInfo = {'name': 'Alex Tan'};
      ApiService.client = _api({
        '/Reports/Attendance': [
          {'recordedTime': daysAgo(1), 'attendanceType': 'Present'},
          {'recordedTime': daysAgo(3), 'attendanceType': 'Absent'},
          {'recordedTime': daysAgo(5), 'attendanceType': 'Leave'},
        ],
      });
      await tester.pumpWidget(_wrap(const ProgressScreen()));
      await _settle(tester);
      expect(find.text('50%'), findsOneWidget);
      expect(find.text('1 present · 1 absent · 1 other'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a selected sibling with unattributed rows sees no metrics', (tester) async {
      UserSession.instance.myInfo = {'name': 'Alex Tan'};
      UserSession.instance.activeStudentName = 'Mia Tan';
      ApiService.client = _api({
        '/Reports/Attendance': [
          {'recordedTime': daysAgo(1), 'attendanceType': 'Present'},
        ],
      });
      await tester.pumpWidget(_wrap(const ProgressScreen()));
      await _settle(tester);
      expect(find.textContaining("isn't available"), findsOneWidget);
      expect(find.text('ATTENDANCE RATE'), findsNothing);
    });

    testWidgets('a failed first load shows retry, not a rate', (tester) async {
      ApiService.client = MockClient((_) async => http.Response('down', 503));
      await tester.pumpWidget(_wrap(const ProgressScreen()));
      await _settle(tester);
      expect(find.text('ATTENDANCE RATE'), findsNothing);
      expect(find.text('Upcoming Grading'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('TournamentScreen', () {
    late http.Client original;
    setUp(() => original = ApiService.client);
    tearDown(() => ApiService.client = original);

    testWidgets('shows real medal totals and no invented Upcoming or Past status', (tester) async {
      ApiService.client = _api({
        '/Reports/TournamentSummary': [
          {'id': 1, 'name': '', 'gender': 'Male', 'playerCount': 3, 'medalGold': 2, 'medalSilver': 1, 'medalBronze': 0},
          {'id': 2, 'name': '', 'gender': 'Female', 'playerCount': 2, 'medalGold': 1, 'medalSilver': 0, 'medalBronze': 1},
        ],
      });
      await tester.pumpWidget(_wrap(const TournamentScreen()));
      await _settle(tester);
      expect(find.text('Tournament'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('5'), findsOneWidget, reason: 'total players');
      expect(find.textContaining('Upcoming'), findsNothing);
      expect(find.text('UPCOMING'), findsNothing);
      expect(find.text('COMPLETED'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty summary says no results, not "no upcoming tournaments"', (tester) async {
      ApiService.client = _api({'/Reports/TournamentSummary': []});
      await tester.pumpWidget(_wrap(const TournamentScreen()));
      await _settle(tester);
      expect(find.text('No tournament results yet'), findsOneWidget);
      expect(find.textContaining('scheduled'), findsNothing);
    });
  });
}

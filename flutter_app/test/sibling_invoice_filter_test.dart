// KAN-35: /Outstanding/Fetch answers a guardian's token with every sibling's invoices whatever
// studentId it is sent, so both child chips on the Pay tab showed the same merged list. Each
// chip must show only its child's invoices, "All" shows them together, and an invoice ticked
// from a merged list is paid for the child it belongs to.
//
// Every name and id here is invented.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/screens/payments_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';

http.Response _ok(Object? data) => http.Response(jsonEncode({'status': 200, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Map<String, dynamic> _inv(int id, int studentId, String name, String what) => {
      'invoiceId': id,
      'studentId': studentId,
      'studentName': name,
      'invoiceDescription': what,
      'transactionType': 'Monthly',
      'dueAmount': 50,
    };

void main() {
  late http.Client original;
  late List<Object?> fetchedFor;

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    fetchedFor = [];
    final s = UserSession.instance;
    s.authData = {'id': 1, 'studentId': 1, 'userType': 3, 'name': 'Ari Lim'};
    s.myInfo = {'name': 'Ari Lim'};
    s.activeStudentId = null;
    s.activeStudentName = null;
    ApiService.client = MockClient((req) async {
      switch (req.url.path) {
        case '/Listing/MySiblings':
          return _ok([
            {'id': 1, 'text': 'Ari Lim'},
            {'id': 2, 'text': 'Bea Lim'},
          ]);
        case '/Outstanding/Fetch':
          fetchedFor.add((jsonDecode(req.body) as Map)['studentId']);
          // The live server ignores studentId and returns the whole family.
          return _ok([
            _inv(101, 1, 'ARI LIM', 'Ari October fee'),
            _inv(102, 1, 'ARI LIM', 'Ari November fee'),
            _inv(201, 2, 'BEA LIM', 'Bea October fee'),
            _inv(202, 2, 'BEA LIM', 'Bea November fee'),
            // No studentId: owned by name, as the History tab already matches.
            {..._inv(203, 0, 'BEA LIM', 'Bea December fee')}..remove('studentId'),
            // Not one of this family: never listed, not even under All.
            _inv(901, 99, 'ZED TAN', 'Zed October fee'),
          ]);
      }
      return _ok([]);
    });
  });

  tearDown(() {
    ApiService.client = original;
    UserSession.instance.activeStudentId = null;
    UserSession.instance.activeStudentName = null;
    UserSession.instance.stopNotificationPolling();
  });

  testWidgets('each child chip shows only that child\'s invoices', (tester) async {
    // Tall enough that the merged list builds every card.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);

    expect(find.text('Ari October fee'), findsOneWidget);
    expect(find.text('Ari November fee'), findsOneWidget);
    expect(find.text('Bea October fee'), findsNothing);

    await tester.tap(find.text('Bea Lim'));
    await _settle(tester);
    expect(find.text('Bea October fee'), findsOneWidget);
    expect(find.text('Bea November fee'), findsOneWidget);
    expect(find.text('Bea December fee'), findsOneWidget);
    expect(find.text('Ari October fee'), findsNothing);
  });

  testWidgets('All shows every child\'s invoices together, named', (tester) async {
    // Tall enough that the merged list builds every card.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);

    await tester.tap(find.text('All'));
    await _settle(tester);

    // The old app's request: no studentId, the whole family.
    expect(fetchedFor.last, isNull);
    for (final t in ['Ari October fee', 'Ari November fee', 'Bea October fee', 'Bea November fee', 'Bea December fee']) {
      expect(find.text(t), findsOneWidget);
    }
    expect(find.textContaining('BEA LIM'), findsNWidgets(3));
    expect(find.text('Zed October fee'), findsNothing);
  });

  testWidgets('invoices ticked under All are paid for the child they belong to', (tester) async {
    // Tall enough that the merged list builds every card.
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);
    await tester.tap(find.text('All'));
    await _settle(tester);

    await tester.ensureVisible(find.text('Ari October fee'));
    await tester.tap(find.text('Ari October fee'));
    await tester.pump();
    // The name-matched row must be paid for Bea too, not lumped into an unknown account.
    await tester.ensureVisible(find.text('Bea December fee'));
    await tester.tap(find.text('Bea December fee'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Pay').last);
    await _settle(tester);
    expect(find.text('Ari Lim: 50.00  •  Bea Lim: 50.00'), findsOneWidget);
  });
}

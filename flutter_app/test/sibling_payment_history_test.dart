// Manual QA 2026-09-29: paying a sibling's invoice left no trace in Payment History.
// History ignored the Pay tab's account chips and kept only the signed-in student's receipts
// (scopeToSelf), so the sibling's receipt was filtered out. Spec:
// docs/superpowers/specs/2026-09-29-sibling-payment-history-design.md
//
// Every name here is invented.
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

Map<String, Object> _receipt(int id, String name, String no) => {
      'id': id,
      'name': name,
      'icNo': '',
      'receiptNo': no,
      'receiptDate': '2026-09-20T00:00:00',
      'receiptAmount': 85,
      'paymentMethod': 'Online',
      'tcName': 'Sample Centre',
    };

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

void main() {
  late http.Client original;
  late List<int> duesFor;
  late List<Map<String, Object>> receipts;

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    duesFor = [];
    receipts = [
      _receipt(11, 'Alex Tan', 'R-ALEX'),
      _receipt(12, 'Mia Tan', 'R-MIA'),
      _receipt(13, 'Someone Else', 'R-OTHER'),
    ];
    final s = UserSession.instance;
    s.authData = {'id': 1, 'studentId': 1, 'userType': 3, 'name': 'Alex Tan'};
    s.myInfo = {'name': 'Alex Tan'};
    s.activeStudentId = null;
    s.activeStudentName = null;
    ApiService.client = MockClient((req) async {
      switch (req.url.path) {
        case '/Listing/MySiblings':
          return _ok([
            {'id': 1, 'text': 'Alex Tan'},
            {'id': 2, 'text': 'Mia Tan'},
          ]);
        case '/Outstanding/Fetch':
          final id = (jsonDecode(req.body) as Map)['studentId'] as int;
          duesFor.add(id);
          return _ok([
            {'invoiceId': 100 + id, 'studentId': id, 'invoiceDescription': 'Fee for account $id', 'dueAmount': 85},
          ]);
        case '/Reports/Receipts':
          return _ok(receipts);
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

  testWidgets('Payments opens on the child picked app-wide', (tester) async {
    UserSession.instance.activeStudentId = 2;
    UserSession.instance.activeStudentName = 'Mia Tan';

    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);

    expect(duesFor.first, 2);
    expect(find.text('Fee for account 2'), findsOneWidget);
  });

  testWidgets("History on a sibling's chip lists that sibling's receipt", (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen(initialTab: 'history')));
    await _settle(tester);

    expect(find.text('Mia Tan'), findsOneWidget, reason: 'History shows the same child chips as Pay');
    await tester.tap(find.text('Mia Tan'));
    await _settle(tester);

    expect(find.textContaining('R-MIA'), findsOneWidget);
    expect(find.textContaining('R-ALEX'), findsNothing);
    expect(find.textContaining('R-OTHER'), findsNothing);
  });

  testWidgets("the signed-in student's chip lists only their own receipts", (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen(initialTab: 'history')));
    await _settle(tester);

    expect(find.textContaining('R-ALEX'), findsOneWidget);
    expect(find.textContaining('R-MIA'), findsNothing);
    expect(find.textContaining('R-OTHER'), findsNothing);
  });

  testWidgets('the child picked on Pay is still picked on History', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);
    await tester.tap(find.text('Mia Tan'));
    await _settle(tester);

    await tester.tap(find.text('History'));
    await _settle(tester);

    expect(find.textContaining('R-MIA'), findsOneWidget);
    expect(find.textContaining('R-ALEX'), findsNothing);
  });

  testWidgets('a sibling with no receipts says so', (tester) async {
    receipts = [_receipt(11, 'Alex Tan', 'R-ALEX')];

    await tester.pumpWidget(_wrap(const PaymentsScreen(initialTab: 'history')));
    await _settle(tester);
    await tester.tap(find.text('Mia Tan'));
    await _settle(tester);

    expect(find.text('No receipts for Mia Tan yet.'), findsOneWidget);
  });
}

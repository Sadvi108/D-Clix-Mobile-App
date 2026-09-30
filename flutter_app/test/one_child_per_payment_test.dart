// Manual QA 2026-09-30: three invoices ticked across siblings on the Pay tab, and the payment
// picked up only one. The app sent all three ids; /Outstanding/PayInvoices billed a subset.
// The production app never mixed children in one invoice payment, so the Pay tab now takes
// one child per payment. Advance payment still bills siblings together (term model).
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

// The segment tab is labelled "Pay" too; the cart's Pay bar comes later in the tree.
Future<void> _tapPayBar(WidgetTester tester) async {
  await tester.tap(find.text('Pay').last);
  await _settle(tester);
}

void main() {
  late http.Client original;
  late List<String> paths;
  late List<String> payBodies;

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    paths = [];
    payBodies = [];
    final s = UserSession.instance;
    s.authData = {'id': 1, 'studentId': 1, 'userType': 3, 'name': 'Ari Lim'};
    s.myInfo = {'name': 'Ari Lim'};
    s.activeStudentId = null;
    s.activeStudentName = null;
    ApiService.client = MockClient((req) async {
      paths.add(req.url.path);
      switch (req.url.path) {
        case '/Listing/MySiblings':
          return _ok([
            {'id': 1, 'text': 'Ari Lim'},
            {'id': 2, 'text': 'Bea Lim'},
          ]);
        case '/Outstanding/Fetch':
          final id = (jsonDecode(req.body) as Map)['studentId'] as int;
          return _ok([
            for (final n in [1, 2])
              {'invoiceId': id * 100 + n, 'studentId': id, 'invoiceDescription': 'Fee $n for account $id', 'dueAmount': 85},
          ]);
        case '/Outstanding/FetchTermPayments':
          final ids = ((jsonDecode(req.body) as Map)['studentIds'] as List).cast<int>();
          return _ok([
            for (final id in ids)
              {'invoiceId': 900 + id, 'studentId': id, 'invoiceDate': '2026-10-01T00:00:00', 'dueAmount': 85},
          ]);
        case '/Outstanding/PayInvoices':
          payBodies.add(req.body);
          // An in-envelope error stops the flow before the gateway WebView, which has no
          // implementation under test.
          return http.Response(jsonEncode({'status': 400, 'meta': {'code': 400, 'error': 'stop before the gateway'}}),
              200,
              headers: {'content-type': 'application/json'});
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

  Future<void> tickOnePerChild(WidgetTester tester) async {
    await tester.tap(find.text('Fee 1 for account 1'));
    await tester.pump();
    await tester.tap(find.text('Bea Lim'));
    await _settle(tester);
    await tester.tap(find.text('Fee 1 for account 2'));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
  }

  testWidgets('a cart holding two children is refused before the pay sheet opens', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);
    await tickOnePerChild(tester);

    await _tapPayBar(tester);

    expect(find.text('Pay for one child at a time'), findsOneWidget);
    expect(find.text('Make Payment'), findsNothing, reason: 'no method or slip may be chosen for a mixed cart');
    expect(paths.where((p) => p.endsWith('/PayInvoices')), isEmpty);
  });

  testWidgets("one child's invoices open the sheet and every id is posted", (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);
    await tester.tap(find.text('Bea Lim'));
    await _settle(tester);
    await tester.tap(find.text('Fee 1 for account 2'));
    await tester.pump();
    await tester.tap(find.text('Fee 2 for account 2'));
    await tester.pump();

    await _tapPayBar(tester);
    expect(find.text('Pay for one child at a time'), findsNothing);
    expect(find.text('Make Payment'), findsOneWidget);

    await tester.tap(find.text('Proceed to pay'));
    await _settle(tester);

    expect(payBodies, hasLength(1));
    final ids = RegExp(r'name="InvoiceIds"\r\n\r\n(\d+)').allMatches(payBodies.single).map((m) => m.group(1));
    expect(ids, unorderedEquals(['201', '202']));
  });

  testWidgets('advance payment for two children is not blocked by a mixed invoice cart', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);
    await tickOnePerChild(tester);

    await tester.tap(find.text('Advance Payment'));
    await _settle(tester);
    await tester.tap(find.text('Bea Lim'));
    await _settle(tester);
    await tester.tap(find.text('Oct'));
    await tester.pump();
    await tester.ensureVisible(find.textContaining('Pay Now'));
    await tester.pump();
    await tester.tap(find.textContaining('Pay Now'));
    await _settle(tester);

    expect(find.text('Pay for one child at a time'), findsNothing);
    expect(find.text('Make Payment'), findsOneWidget);
  });
}

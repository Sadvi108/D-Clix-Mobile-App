// Manual QA 2026-09-30: three invoices ticked across siblings on the Pay tab, and the payment
// picked up only one. /Outstanding/PayInvoices binds one student to a payment, so a shared
// bank-in receipt must be submitted once per sibling with that sibling's invoice ids.
//
// Every name and id here is invented.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late List<String> payBodies;
  late Directory tmp;

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    payBodies = [];
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
          final body = latin1.decode(req.bodyBytes);
          payBodies.add(body);
          if (body.contains('name="PaymentMethod"\r\n\r\n1')) return _ok('Saved');
          // An in-envelope error stops the flow before the gateway WebView, which has no
          // implementation under test.
          return http.Response(jsonEncode({'status': 400, 'meta': {'code': 400, 'error': 'stop before the gateway'}}),
              200,
              headers: {'content-type': 'application/json'});
      }
      return _ok([]);
    });
    tmp = Directory.systemTemp.createTempSync('sibling_slip');
    final slip = File('${tmp.path}/slip.png')..writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => call.method == 'pickImage' ? slip.path : null);
  });

  tearDown(() {
    ApiService.client = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/image_picker'), null);
    tmp.deleteSync(recursive: true);
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

  testWidgets('one sibling receipt creates a correctly scoped payment for each child', (tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen()));
    await _settle(tester);
    await tickOnePerChild(tester);

    await _tapPayBar(tester);

    expect(find.text('Make Payment'), findsOneWidget);
    expect(find.text('Ari Lim: 85.00  •  Bea Lim: 85.00'), findsOneWidget);
    await tester.tap(find.text('Direct Bank-In'));
    await tester.pump();
    await tester.tap(find.text('Gallery'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Submit Slip'));
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Submit Slip'));
      await Future<void>.delayed(const Duration(seconds: 1));
    });
    await _settle(tester);

    expect(payBodies, hasLength(2));
    final groups = payBodies
        .map((body) => RegExp(r'name="InvoiceIds"\r\n\r\n(\d+)').allMatches(body).map((m) => m.group(1)).toList())
        .toList();
    expect(groups, unorderedEquals([
      ['101'],
      ['201'],
    ]));
    expect(payBodies.every((body) => body.contains('filename="slip.png"')), isTrue);
    expect(find.text('Submitted'), findsOneWidget);
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

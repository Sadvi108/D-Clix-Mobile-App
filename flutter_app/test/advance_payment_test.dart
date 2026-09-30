// Manual QA 2026-09-30: "Pay in Advance" did not work.
//
// Online, the months went to /Bcpg/PayInvoices, which answers 400 for anything carrying invoice
// ids or a term. Bank-In sent `?PayTermPayments=true`, a query flag the server never reads, so
// the months and siblings picked never reached it. The production app paid both ways through
// multipart /Outstanding/PayInvoices, the term in a JSON part named PayTermPayments
// (TermPaymentPageViewModel.cs:82-99, OutstandingDataAccess.cs:81-119).
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

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
http.Response _ok(Object? data) => _json({'status': 200, 'data': data});

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

/// The raw multipart body. latin1, because the slip is binary and would not decode as UTF-8.
String _text(http.Request req) => latin1.decode(req.bodyBytes);

/// Form parts by name; repeated parts joined with commas.
Map<String, String> _parts(http.Request req) {
  final out = <String, String>{};
  for (final m in RegExp(r'name="([^"]+)"(?:; filename="[^"]*")?\r\n\r\n([^\r]*)').allMatches(_text(req))) {
    out[m.group(1)!] = out.containsKey(m.group(1)) ? '${out[m.group(1)]},${m.group(2)}' : m.group(2)!;
  }
  return out;
}

// A 1x1 PNG, so the slip preview decodes.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  final year = DateTime.now().year;
  late http.Client original;
  late List<http.Request> pays;
  late Directory tmp;

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    pays = [];
    final s = UserSession.instance;
    s.authData = {'id': 1, 'studentId': 1, 'userType': 3, 'name': 'Ari Lim'};
    s.myInfo = {'name': 'Ari Lim'};
    s.activeStudentId = null;
    s.activeStudentName = null;
    s.clearPaymentLock();
    ApiService.client = MockClient((req) async {
      switch (req.url.path) {
        case '/Listing/MySiblings':
          return _ok([
            {'id': 1, 'text': 'Ari Lim'},
            {'id': 2, 'text': 'Bea Lim'},
          ]);
        case '/Outstanding/FetchTermPayments':
          final body = jsonDecode(req.body) as Map;
          final y = body['year'];
          // October is invoiced; November is the academy's projected fee (invoiceId 0).
          return _ok([
            for (final id in (body['studentIds'] as List).cast<int>()) ...[
              {'invoiceId': 900 + id, 'studentId': id, 'invoiceDate': '$y-10-01T00:00:00', 'period': 'October-$y', 'dueAmount': 85},
              {'invoiceId': 0, 'studentId': id, 'invoiceDate': '$y-11-01T00:00:00', 'period': 'November-$y', 'dueAmount': 85},
            ],
          ]);
        case '/Bcpg/PayInvoices':
          pays.add(req);
          // What the server answers for a term (docs/superpowers/specs/2026-07-28-uat-boost-gateway-integration.md §6.1).
          return _json({
            'status': 400,
            'meta': {
              'code': 400,
              'error': 'The JSON value could not be converted to System.String. Path: \$.status | LineNumber: 0 | BytePositionInLine: 58.'
            }
          });
        case '/Outstanding/PayInvoices':
          pays.add(req);
          if (_parts(req)['PaymentMethod'] == '1') return _ok('Saved');
          // An in-envelope error stops the online flow before the gateway WebView, which has
          // no implementation under test.
          return _json({'status': 400, 'meta': {'code': 400, 'error': 'stop before the gateway'}});
      }
      return _ok([]);
    });

    tmp = Directory.systemTemp.createTempSync('advance_slip');
    final slip = File('${tmp.path}/slip.png')..writeAsBytesSync(_png);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/image_picker'),
        (call) async => call.method == 'pickImage' ? slip.path : null);
  });

  tearDown(() {
    ApiService.client = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/image_picker'), null);
    tmp.deleteSync(recursive: true);
    UserSession.instance.clearPaymentLock();
    UserSession.instance.stopNotificationPolling();
  });

  /// Both children, October (invoiced) and November (not yet), then the pay sheet.
  Future<void> pickMonthsAndOpenSheet(WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const PaymentsScreen(initialTab: 'prepay')));
    await _settle(tester);
    await tester.ensureVisible(find.text('Bea Lim'));
    await tester.pump();
    await tester.tap(find.text('Bea Lim'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Oct'));
    await tester.pump();
    await tester.tap(find.text('Oct'));
    await tester.pump();
    await tester.tap(find.text('Nov*'));
    await tester.pump();
    await tester.ensureVisible(find.textContaining('Pay Now'));
    await tester.pump();
    await tester.tap(find.textContaining('Pay Now'));
    await _settle(tester);
    expect(find.text('Make Payment'), findsOneWidget);
  }

  void expectTerm(http.Request req, {required String method}) {
    expect(req.url.path, '/Outstanding/PayInvoices');
    expect(req.url.query, isEmpty, reason: 'the server never reads the term from the query string');
    final parts = _parts(req);
    expect(parts['PaymentMethod'], method);
    expect(parts['InvoiceIds'], '901,902', reason: 'issued invoices only; November has none yet');
    expect(jsonDecode(parts['PayTermPayments'] ?? 'null'), {
      'StudentIds': [1, 2],
      'Year': year,
      'Months': [10, 11],
    });
    expect(
        _text(req),
        contains('content-type: application/json; charset=utf-8\r\n'
            'content-disposition: form-data; name="PayTermPayments"\r\n\r\n'));
  }

  testWidgets('online: the months and children picked reach the gateway route as the term', (tester) async {
    await pickMonthsAndOpenSheet(tester);

    await tester.tap(find.text('Proceed to pay'));
    await _settle(tester);

    expect(pays, hasLength(1));
    expectTerm(pays.single, method: '2');
    expect(pays.single.url.origin, Uri.parse(ApiService.boostBaseUrl).origin);
  });

  testWidgets('bank-in: the slip goes with the term, and the member is told it was submitted', (tester) async {
    await pickMonthsAndOpenSheet(tester);

    await tester.tap(find.text('Direct Bank-In'));
    await tester.pump();
    await tester.tap(find.text('Gallery'));
    await _settle(tester);
    await tester.ensureVisible(find.text('Submit Slip'));
    await tester.pump();
    // Reading the slip off disk is real I/O, which fake time never completes.
    await tester.runAsync(() async {
      await tester.tap(find.text('Submit Slip'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await _settle(tester);

    expect(pays, hasLength(1));
    expectTerm(pays.single, method: '1');
    expect(_text(pays.single), contains('filename="slip.png"'));
    expect(find.text('Submitted'), findsOneWidget);
  });
}

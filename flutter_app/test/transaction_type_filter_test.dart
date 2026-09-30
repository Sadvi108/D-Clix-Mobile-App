// "Filter By Transaction Type" must narrow the dues list (manual QA 2026-09-30: picking a type
// on Pay Your Dues still showed the same invoices).
//
// The app sent the picked type's `id` as `transactionType` and left the filtering to
// /Outstanding/Fetch, which answered with the same rows. The production Xamarin app never asked
// the server to filter: it fetched once with an empty RequestOutstandingViewModel and kept the
// rows whose `TransactionType` equals the picked type's *text* (OutstandingPageViewModel.cs:86,
// :203, :291; the report twin does the same in OutstandingReportPageViewModel.cs:74, :140, :214).
// The mock answers the way the live route did on the phone: the same rows whatever the body says.
import 'dart:convert';

import 'package:dclix_app/screens/instructor_reports/rn_reports.dart';
import 'package:dclix_app/screens/outstanding_invoices_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

const _types = [
  {'id': 1, 'text': 'Monthly Fee'},
  {'id': 2, 'text': 'Grading Fee'},
];

const _rows = [
  {
    'invoiceId': 7101,
    'studentName': 'Member Monthly',
    'transactionType': 'Monthly Fee',
    'period': 'Sep 2026',
    'dueAmount': 80,
    'paymentStatus': 'Pending',
  },
  {
    'invoiceId': 7102,
    'studentName': 'Member Grading',
    'transactionType': 'Grading Fee',
    'period': 'Sep 2026',
    'dueAmount': 50,
    'paymentStatus': 'Pending',
  },
];

Widget wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late List<Map<String, dynamic>> fetchBodies;

  setUp(() {
    fetchBodies = [];
    ApiService.client = MockClient((req) async {
      if (req.url.path == '/Outstanding/Fetch') fetchBodies.add(jsonDecode(req.body) as Map<String, dynamic>);
      final data = switch (req.url.path) {
        '/Listing/InvoceTypes' => _types,
        '/Outstanding/Fetch' => _rows,
        _ => const <Object>[],
      };
      return http.Response(jsonEncode({'status': 200, 'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
  });

  tearDown(() => ApiService.client = http.Client());

  for (final (name, screen) in <(String, Widget)>[
    ('Pay Your Dues', const OutstandingInvoicesScreen()),
    ('Outstanding report', const ROutstandingScreen()),
  ]) {
    testWidgets('$name: picking a transaction type lists only that type', (tester) async {
      await tester.pumpWidget(wrap(screen));
      await settle(tester);
      expect(find.text('Member Monthly'), findsOneWidget);
      expect(find.text('Member Grading'), findsOneWidget);

      await tester.tap(find.text('All'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Grading Fee')));
      await settle(tester);

      expect(find.text('Member Grading'), findsOneWidget);
      expect(find.text('Member Monthly'), findsNothing);
      // As the old app did: the server is never handed the type (least of all its id).
      expect(fetchBodies, isNotEmpty);
      expect(fetchBodies.map((b) => b['transactionType']), everyElement(isNull));
    });
  }
}

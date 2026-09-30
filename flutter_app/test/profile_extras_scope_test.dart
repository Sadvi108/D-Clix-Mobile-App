// Editing a profile must not destroy what it never loaded, must not carry one
// account's edits into another, and must still let a member clear a field they
// can see. Parity review finding F11.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/screens/edit_profile_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/theme_provider.dart';

/// The multipart parts, tolerating the extra `content-type` /
/// `content-transfer-encoding` headers package:http adds for an empty value.
Map<String, String> partsOf(http.Request request) => {
      for (final m
          in RegExp(r'name="([^"\r\n]+)"((?:\r\n[a-z-]+: [^\r\n]+)*)\r\n\r\n([\s\S]*?)\r\n--').allMatches(request.body))
        m.group(1)!: m.group(3)!,
    };

void main() {
  final session = UserSession.instance;
  late http.Client original;
  late List<http.Request> writes;
  late bool extrasFail;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiService.client;
    writes = [];
    extrasFail = false;
    session.authData = {
      'id': 100,
      'userId': 100,
      'userType': 3,
      'name': 'Test Member',
      'icNo': 'OLD-IC',
      'branchId': 10,
      'clubId': 20,
    };
    session.myInfo = null;
    session.studentAddtnlInfo = null;
    session.setActiveStudent(name: null, id: null);
    ApiService.client = MockClient((request) async {
      dynamic data;
      if (request.url.path.endsWith('/StudentAddtnlInfo')) {
        if (extrasFail) return http.Response('nope', 503);
        data = {'schoolname': 'Test School', 'healthstatus': 'Test health note'};
      } else if (request.url.path.endsWith('/UpdateProfile')) {
        writes.add(request);
        data = '';
      } else {
        data = <String, dynamic>{};
      }
      return http.Response(
          jsonEncode({
            'status': 200,
            'meta': {'code': 200},
            'data': data
          }),
          200);
    });
  });
  tearDown(() => ApiService.client = original);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: session),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MaterialApp(home: EditProfileScreen()),
    ));
    addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await settle(tester);
  }

  Finder input(String hint) => find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

  testWidgets('loaded extras are sent back untouched', (tester) async {
    await open(tester);
    await save(tester);
    expect(partsOf(writes.single)['Schoolname'], 'Test School');
    expect(partsOf(writes.single)['Healthstatus'], 'Test health note');
  });

  testWidgets('a student can edit their IC number', (tester) async {
    await open(tester);
    expect(input('IC No'), findsOneWidget);
    await tester.ensureVisible(input('IC No'));
    await tester.enterText(input('IC No'), 'NEW-IC-99');
    await save(tester);

    expect(partsOf(writes.single)['IcNo'], 'NEW-IC-99');
    expect(session.authData?['icNo'], 'NEW-IC-99');
  });

  testWidgets('a field the member cleared is sent empty, not dropped', (tester) async {
    await open(tester);
    await tester.ensureVisible(input('School'));
    await tester.enterText(input('School'), '');
    await save(tester);
    final parts = partsOf(writes.single);
    expect(parts.containsKey('Schoolname'), isTrue, reason: 'the server can only clear it if it is sent');
    expect(parts['Schoolname'], '');
    expect(parts['Healthstatus'], 'Test health note');
  });

  testWidgets('extras that never loaded are left out entirely', (tester) async {
    extrasFail = true;
    await open(tester);
    await save(tester);
    final parts = partsOf(writes.single);
    expect(parts.containsKey('Schoolname'), isFalse);
    expect(parts.containsKey('Healthstatus'), isFalse);
  });

  testWidgets('the identity snapshot is taken when the form opens, not on first read', (tester) async {
    // A lazily-initialised snapshot would capture whoever is signed in at the
    // moment it is first read — i.e. the NEW account — and wave the stale form
    // through. Switching before anything reads it must still be caught.
    await open(tester);
    session.authData = {'id': 300, 'userId': 300, 'userType': 3, 'name': 'Someone Else'};
    session.setActiveStudent(name: null, id: null);
    await save(tester);
    expect(writes, isEmpty);
    expect(session.authData!['name'], 'Someone Else', reason: 'the new account is left alone');
  });

  testWidgets('a form opened for one account cannot save into another', (tester) async {
    await open(tester);
    session.authData = {'id': 300, 'userId': 300, 'userType': 3, 'name': 'Someone Else'};
    session.setActiveStudent(name: null, id: null);
    await save(tester);
    expect(writes, isEmpty);
  });
}

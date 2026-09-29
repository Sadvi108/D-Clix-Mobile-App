# Sibling Payments in Payment History — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A receipt for a sibling's invoice shows in Payment History, on that sibling's chip.

**Architecture:** One account chip for the whole Payments screen. Pay and History both follow
`_activeAccount`, which now defaults to the app-wide selected student. History narrows the
receipts it already fetches with `scopeStudentRows`, the Progress screens' rule: the signed-in
student's rows, or a sibling's positive name matches only. No new requests.

**Tech Stack:** Flutter, `flutter_test` + `package:http/testing.dart` `MockClient` (the repo's
`ApiService.client` injection), provider.

Spec: `docs/superpowers/specs/2026-09-29-sibling-payment-history-design.md`

**House rules for this repo (from the owner):** one QA issue = one commit, pushed straight to
`main` once finished (full `flutter test` passing, `flutter analyze` adding nothing). So the
tasks below do not commit individually; Task 3 commits once. Every value in tests is invented.

---

## File structure

- Modify `flutter_app/lib/screens/payments_screen.dart`
  - `_accountId` getter (line ~89): add the app-wide default.
  - `build()`: show the chip row on History as well as Pay (lines ~316-352); History rows via
    `scopeStudentRows` (line ~462) with a per-child empty state.
  - Import `../utils/progress_stats.dart`.
- Create `flutter_app/test/sibling_payment_history_test.dart` — all tests for this issue.

---

### Task 1: Payments opens on the child picked app-wide

**Files:**
- Create: `flutter_app/test/sibling_payment_history_test.dart`
- Modify: `flutter_app/lib/screens/payments_screen.dart:89`

- [ ] **Step 1: Write the test file with the shared setup and the first failing test**

```dart
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
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `cd flutter_app && flutter test test/sibling_payment_history_test.dart`
Expected: FAIL — `Expected: <2> Actual: <1>` (Payments ignores the app-wide pick today).

- [ ] **Step 3: Default the chip to the app-wide pick**

In `flutter_app/lib/screens/payments_screen.dart`, replace

```dart
  int? get _accountId => _activeAccount?.id ?? (_user['id'] == null ? null : _intOf(_user['id']));
```

with

```dart
  int? get _accountId =>
      _activeAccount?.id ?? _appWideAccountId ?? (_user['id'] == null ? null : _intOf(_user['id']));

  /// The child picked app-wide (Home or Profile switcher), so Payments opens on the same one.
  /// The switcher and these chips both carry /Listing/MySiblings ids.
  int? get _appWideAccountId {
    final id = _intOf(UserSession.instance.activeStudentId);
    return id == 0 ? null : id;
  }
```

- [ ] **Step 4: Run it and watch it pass**

Run: `cd flutter_app && flutter test test/sibling_payment_history_test.dart`
Expected: PASS (1 test).

---

### Task 2: History shows the chips and only the chosen child's receipts

**Files:**
- Modify: `flutter_app/test/sibling_payment_history_test.dart`
- Modify: `flutter_app/lib/screens/payments_screen.dart` (imports; `build()` lines ~316-352 and ~461-468)

- [ ] **Step 1: Add the failing tests** — inside `main()`, after the Task 1 test:

```dart
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
```

- [ ] **Step 2: Run them and watch them fail**

Run: `cd flutter_app && flutter test test/sibling_payment_history_test.dart`
Expected: 3 FAIL — "History on a sibling's chip…" and "a sibling with no receipts…" fail with
`Found 0 widgets with text "Mia Tan"` (no chips on History); "the child picked on Pay…" fails with
`Found 0 widgets with text containing R-MIA`. "the signed-in student's chip…" PASSES already —
it is a guard that today's own-receipts behaviour survives the change.

- [ ] **Step 3: Import the scoping rule**

In `flutter_app/lib/screens/payments_screen.dart`, after `import '../theme/ion.dart';` add:

```dart
import '../utils/progress_stats.dart';
```

- [ ] **Step 4: Show the chip row on History too**

Replace

```dart
    final body = <Widget>[];
    if (_seg == 'pay') {
      body.add(SizedBox(
        height: 46,
```

with

```dart
    final body = <Widget>[];
    // One child for the whole screen: Pay and History follow the same chip.
    if (_seg == 'pay' || _seg == 'history') {
      body.add(SizedBox(
        height: 46,
```

and replace (the end of the chip row, where the Auto Pay card begins)

```dart
          },
        ),
      ));
      body.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Touchable(
          onPress: () => context.push('/autopay'),
```

with

```dart
          },
        ),
      ));
    }
    if (_seg == 'pay') {
      body.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Touchable(
          onPress: () => context.push('/autopay'),
```

- [ ] **Step 5: Narrow History to the chosen child**

Replace

```dart
    if (_seg == 'history') {
      final rows = session.scopedRows(_history.data).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      if (_history.loading) body.add(const SkeletonList(rows: 4, lines: 2, padding: EdgeInsets.only(top: 4)));
      if (!_history.loading && _history.error != null && rows.isEmpty) {
        body.add(ErrorState(message: _history.error, onRetry: _history.reload));
      } else if (!_history.loading && rows.isEmpty) {
        body.add(emptyTxt('No receipts found.'));
      }
```

with

```dart
    if (_seg == 'history') {
      // /Reports/Receipts returns the whole branch to a student token. Keep the chip's child only:
      // the signed-in student by name or IC (not displayName, which becomes an app-wide-picked
      // sibling's name), a sibling by positive name match only.
      final chosen = accounts.where((a) => a.id == accountId).firstOrNull;
      final sibling = chosen != null && chosen.id != _intOf(user['id']) ? chosen : null;
      final all = (_history.data ?? const <Map<String, dynamic>>[]).cast<Map>().toList();
      final rows = scopeStudentRows(all,
              self: StudentIdentity(name: '${user['name'] ?? ''}', ic: '${user['icNo'] ?? ''}'),
              selected: sibling == null ? null : StudentIdentity(name: sibling.name))
          .rows
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      if (_history.loading) body.add(const SkeletonList(rows: 4, lines: 2, padding: EdgeInsets.only(top: 4)));
      if (!_history.loading && _history.error != null && rows.isEmpty) {
        body.add(ErrorState(message: _history.error, onRetry: _history.reload));
      } else if (!_history.loading && rows.isEmpty) {
        body.add(emptyTxt(
            sibling == null || all.isEmpty ? 'No receipts found.' : 'No receipts for ${sibling.name.trim()} yet.'));
      }
```

- [ ] **Step 6: Run the file and watch everything pass**

Run: `cd flutter_app && flutter test test/sibling_payment_history_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 7: Analyze the touched file**

Run: `cd flutter_app && flutter analyze lib/screens/payments_screen.dart`
Expected: `No issues found!` If it reports `session` as unused, it is still used elsewhere in
`build()` — check before deleting anything.

---

### Task 3: Verify, commit once, push

- [ ] **Step 1: Full suite**

Run: `cd flutter_app && flutter test`
Expected: `All tests passed!` (baseline before this change: 427 passed, 3 skipped).

- [ ] **Step 2: Analyzer baseline**

Run: `cd flutter_app && flutter analyze | tail -1`
Expected: `53 issues found.` (the pre-existing baseline; nothing new).

- [ ] **Step 3: Commit and push to main**

```bash
cd /Users/sadvi/Projects/Dclix
git fetch origin && git status --short
git add flutter_app/lib/screens/payments_screen.dart flutter_app/test/sibling_payment_history_test.dart docs/superpowers/plans/2026-09-29-sibling-payment-history.md
git commit -m "fix(payments): show a sibling's payment in Payment History"
git push origin main
```

(The spec commit `9f9fe44` rides along in the same push.)

- [ ] **Step 4: Check it against real data**

On the simulator, signed in as a student with a sibling: Payments → History → tap the
sibling's chip. Their past receipts must list there. If they do not, `/Reports/Receipts` is not
returning the sibling's rows to this token — the spec's fallback (per-child fetch) applies.

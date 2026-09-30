// Identity boundaries: a guardian's picked child must never survive a logout, a
// login as someone else or a branch switch, and must never be relabelled onto
// another child's rows. Parity review findings F1 and F2.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/services/user_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final s = UserSession.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    s.authData = null;
    s.setActiveStudent(name: null, id: null);
    s.siblings = null;
    s.clearPaymentLock();
  });

  group('the picked child is account-scoped (F1)', () {
    test('logout drops the selection, the sibling list and the payment lock', () {
      s.authData = {'id': 100, 'userType': 3};
      s.setActiveStudent(name: 'CHILD A', id: 4001);
      s.siblings = [
        {'id': 4001, 'text': 'CHILD A'}
      ];
      s.startPaymentLock();

      s.logout();

      expect(s.activeStudentName, isNull);
      expect(s.activeStudentId, isNull);
      expect(s.siblings, isNull);
      expect(s.paymentLocked, isFalse);
    });

    test('after logout the next account is not targeted through the old child', () {
      s.authData = {'id': 100, 'userType': 3};
      s.setActiveStudent(name: 'CHILD A', id: 4001);
      expect(s.currentStudentId, 4001);

      s.logout();
      // …a different guardian signs in on the same device.
      s.authData = {'id': 200, 'userType': 3};

      expect(s.currentStudentId, 200, reason: 'prepay and booking must target the new account');
      expect(s.displayName, isNot('CHILD A'), reason: 'the header must not show the old child');
    });
  });

  group('sibling filter never shows another child (F2)', () {
    final rows = [
      {'studentId': 4001, 'studentName': 'CHILD A', 'amount': 10},
      {'studentId': 4002, 'studentName': 'CHILD B', 'amount': 20},
    ];

    test('matches on student id when the rows carry one', () {
      s.setActiveStudent(name: 'CHILD A', id: 4001);
      expect(s.filterByActiveStudent(rows), [rows[0]]);
    });

    test('a child with no rows gets an empty list, not the siblings', () {
      s.setActiveStudent(name: 'CHILD C', id: 4003);
      expect(s.filterByActiveStudent(rows), isEmpty);
    });

    test('falls back to the name when rows carry no id', () {
      final byName = [
        {'name': 'CHILD A', 'amount': 10},
        {'name': 'CHILD B', 'amount': 20},
      ];
      s.setActiveStudent(name: 'CHILD B', id: 4002);
      expect(s.filterByActiveStudent(byName), [byName[1]]);
    });

    test('one row naming someone else is still dropped', () {
      final one = [
        {'studentId': 4002, 'studentName': 'CHILD B', 'amount': 20}
      ];
      s.setActiveStudent(name: 'CHILD A', id: 4001);
      expect(s.filterByActiveStudent(one), isEmpty);
    });

    test('rows that name nobody are kept: the server scoped them to the token', () {
      final anon = [
        {'amount': 10},
        {'amount': 20},
      ];
      s.setActiveStudent(name: 'CHILD A', id: 4001);
      expect(s.filterByActiveStudent(anon), anon);
    });

    test('an id-only selection still scopes', () {
      s.setActiveStudent(name: null, id: 4002);
      expect(s.filterByActiveStudent(rows), [rows[1]]);
    });

    test('ids match across string and number', () {
      s.setActiveStudent(name: 'CHILD A', id: '4001');
      expect(s.filterByActiveStudent(rows), [rows[0]]);
    });

    test('no selection leaves the aggregate alone', () {
      s.setActiveStudent(name: null, id: null);
      expect(s.filterByActiveStudent(rows), rows);
    });
  });
}

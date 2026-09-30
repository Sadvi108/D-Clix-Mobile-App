import 'dart:convert';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response _ok(Object? data) => http.Response(
      jsonEncode({'status': 200, 'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = UserSession.instance;
  late http.Client original;

  setUp(() {
    original = ApiService.client;
    session.authData = {
      'id': 100,
      'userType': 3,
      'name': 'Primary Student',
    };
    session.siblings = [
      {'id': 202, 'text': 'Mia Student', 'value': 'MIA-202'},
    ];
    session.setActiveStudent(name: null, id: null);
  });

  tearDown(() {
    ApiService.client = original;
    session.setActiveStudent(name: null, id: null);
    session.siblings = null;
  });

  test('switching student requests and exposes that child report details', () async {
    final reportBodies = <String, Map<String, dynamic>>{};
    ApiService.client = MockClient((request) async {
      if (request.method == 'POST') {
        reportBodies[request.url.path] = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      }
      return switch (request.url.path) {
        '/Reports/StudentDetails' => _ok([
            {
              'studentId': 101,
              'studentName': 'Primary Student',
              'tCenterName': 'Wrong Centre',
            },
            {
              'studentId': 202,
              'studentName': 'Mia Student',
              'registrationNo': 'REG-202',
              'currentGrade': 'Grade 5 (Blue)',
              'tCenterName': 'Mia Centre',
              'instructorName': 'Coach Mia',
              'dayOfWeek': 'Tuesday',
              'tTimeFrom': '18:00',
              'tTimeTo': '19:00',
            },
          ]),
        '/Reports/GradingSchedule' => _ok([
            {
              'studentId': 202,
              'studentName': 'Mia Student',
              'ecName': 'Own Exam Hall',
              'examDate': '2026-10-18T00:00:00',
              'gradingStatus': 'Registered',
              'paymentStatus': 'Paid',
            },
            {
              'studentId': 999,
              'studentName': 'Another Student',
              'ecName': 'Own Exam Hall',
              'gradingStatus': 'Wrong',
            },
          ]),
        '/Listing/DropdownListByType/2' => _ok([
            {'id': 9, 'text': 'Own Exam Hall'},
          ]),
        '/Reports/TournamentSummary' => _ok([
            {
              'tournamentName': 'Junior Open',
              'tournamentDate': '2026-11-02T00:00:00',
              'tournamentStatus': 'Confirmed',
            },
          ]),
        _ => _ok([]),
      };
    });

    expect(await session.switchStudent(202, studentName: 'Mia Student'), isTrue);

    for (final path in const [
      '/Reports/StudentDetails',
      '/Reports/GradingSchedule',
      '/Reports/TournamentSummary',
    ]) {
      expect(reportBodies[path]?['sourceKeyId'], 202, reason: path);
    }
    expect(reportBodies['/Reports/StudentDetails']?['studentName'], 'Mia Student');

    final info = session.activeStudentInfo!;
    expect(info['name'], 'Mia Student');
    expect(info['registrationNo'], 'REG-202');
    expect(info['currentGrade'], 'Grade 5 (Blue)');
    expect(info['tCenterName'], 'Mia Centre');
    expect(info['trainingTme'], '18:00 To 19:00 (Tuesday)');
    expect(info['eCenterName'], 'Own Exam Hall');
    expect(info['gradingStatus'], 'Registered');
    expect(info['gradingPaymentStatus'], 'Paid');
    expect(info['tournamentName'], 'Junior Open');
    expect(info['tournamentStatus'], 'Confirmed');
    expect('${info.values}', isNot(contains('Wrong Centre')));
  });
}

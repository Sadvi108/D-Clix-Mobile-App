import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/manual_attendance.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  late http.Client original;
  setUp(() {
    original = ApiService.client;
    ManualAttendance.resetCache();
  });
  tearDown(() => ApiService.client = original);

  group('isAvailable', () {
    test('false while the deployed route table lacks the marking route', () async {
      ApiService.client = MockClient((req) async => _json({
            'paths': {'/Attendance/Add': {}, '/Reports/Attendance': {}}
          }));
      expect(await ManualAttendance.isAvailable(), isFalse);
    });

    test('true once the route is deployed, and cached for the session', () async {
      var calls = 0;
      ApiService.client = MockClient((req) async {
        calls++;
        expect(req.url.path, '/swagger/v1/swagger.json');
        return _json({
          'paths': {ManualAttendance.route: {}}
        });
      });
      expect(await ManualAttendance.isAvailable(), isTrue);
      expect(await ManualAttendance.isAvailable(), isTrue);
      expect(calls, 1);
    });

    test('a failed check is an error, not "unavailable", and is not cached', () async {
      ApiService.client = MockClient((_) async => http.Response('down', 503));
      await expectLater(ManualAttendance.isAvailable(), throwsA(isA<ApiException>()));
      ApiService.client = MockClient((_) async => _json({
            'paths': {ManualAttendance.route: {}}
          }));
      expect(await ManualAttendance.isAvailable(), isTrue);
    });
  });

  group('markPresent', () {
    test('posts one entry per student for the centre, class time and date', () async {
      Map<String, dynamic>? sent;
      ApiService.client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, ManualAttendance.route);
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _json({
          'status': 200,
          'data': [
            {'studentId': 11, 'status': 0, 'message': 'Marked'},
            {'studentId': 12, 'status': -1, 'message': 'Already marked'},
          ],
        });
      });
      final results = await ManualAttendance.markPresent(
          tCenterId: 3303, tTimeId: 5250, date: DateTime(2026, 9, 15, 18, 30), studentIds: [11, 12]);
      expect(sent, {
        'tCenterId': 3303,
        'tTimeId': 5250,
        'attendanceDate': '2026-09-15',
        'entries': [
          {'studentId': 11, 'attendanceTypeId': ManualAttendance.presentTypeId},
          {'studentId': 12, 'attendanceTypeId': ManualAttendance.presentTypeId},
        ],
      });
      expect(results[11]!.ok, isTrue);
      expect(results[12]!.ok, isFalse);
      expect(results[12]!.message, 'Already marked');
    });

    test('a student missing from the response is unconfirmed, never assumed marked', () async {
      ApiService.client = MockClient((_) async => _json({'status': 200, 'data': []}));
      final results =
          await ManualAttendance.markPresent(tCenterId: 1, tTimeId: 2, date: DateTime(2026, 9, 15), studentIds: [7]);
      expect(results[7]!.ok, isFalse);
      expect(results[7]!.message, contains('not confirmed'));
    });

    test('an envelope error is thrown', () async {
      ApiService.client = MockClient((_) async => _json({
            'status': 400,
            'meta': {'code': 0, 'error': 'Invalid Instructor details'}
          }));
      await expectLater(
          ManualAttendance.markPresent(tCenterId: 1, tTimeId: 2, date: DateTime(2026, 9, 15), studentIds: [7]),
          throwsA(isA<ApiException>()));
    });
  });
}

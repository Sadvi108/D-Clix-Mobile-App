import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';

http.Response _ok(Object? data) => http.Response(
    jsonEncode({'status': 200, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late http.Client original;
  late Map<String, dynamic> changeBody;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiService.client;
    changeBody = {};
    final session = UserSession.instance;
    session.authData = {
      'id': 10,
      'userType': 3,
      'accessToken': 'old-token',
      'clubId': 1,
      'clubName': 'North Academy',
      'clubList': [
        {'id': 1, 'value': 'NORTH', 'text': 'North Academy'},
        {'id': 2, 'value': 'SOUTH', 'text': 'South Academy'},
      ],
    };
    session.myInfo = {'name': 'Old Club Student'};
    ApiService.setToken('old-token');
    ApiService.client = MockClient((request) async {
      if (request.url.path == '/Account/ChangeClub') {
        changeBody = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return _ok({
          'id': 10,
          'userType': 3,
          'accessToken': 'south-token',
          'clubId': 2,
          'clubName': 'South Academy',
        });
      }
      if (request.url.path == '/Profile/MyInfo') return _ok({'name': 'South Club Student'});
      return _ok([]);
    });
  });

  tearDown(() {
    ApiService.client = original;
    ApiService.clearToken();
    UserSession.instance.authData = null;
    UserSession.instance.myInfo = null;
    UserSession.instance.stopNotificationPolling();
  });

  test('club switch obtains a club-scoped token and reloads club details', () async {
    final session = UserSession.instance;
    final ok = await session.switchClub(
      clubId: 2,
      clubCode: 'SOUTH',
      username: 'member-10',
      password: 'secret',
    );

    expect(ok, isTrue);
    expect(changeBody, containsPair('clubCode', 'SOUTH'));
    expect(changeBody, containsPair('username', 'member-10'));
    expect(changeBody, containsPair('password', 'secret'));
    expect(session.authData?['accessToken'], 'south-token');
    expect(session.authData?['clubId'], 2);
    expect(session.authData, isNot(contains('password')));
    expect(session.clubDisplayName, 'South Academy');
    expect(session.myInfo?['name'], 'South Club Student');
  });
}

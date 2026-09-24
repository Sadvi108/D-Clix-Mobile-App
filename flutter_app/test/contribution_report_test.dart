// /Reports/Contribution casts reportType to an int server-side, the same quirk documented
// in docs/ARCHITECTURE.md ("Report-route quirks") for /Reports/Reimbursement and
// /Reports/TournamentSummary: a word like 'HQ' or 'BRANCH' 400s —
// {"status":400,"meta":{"code":0,"error":"Error converting data type nvarchar to int."}}
// RnApi.contributionReport must strip it with numericReportType, the same way its siblings
// (reimbursementReport, tournamentSummary) already do.
import 'dart:convert';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/rn_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> sent;

  setUp(() {
    sent = [];
    ApiService.client = MockClient((req) async {
      sent.add(req);
      return http.Response(jsonEncode({'status': 200, 'data': <dynamic>[]}), 200,
          headers: {'content-type': 'application/json'});
    });
  });

  tearDown(() => ApiService.client = http.Client());

  test('posts to /Reports/Contribution with a non-numeric reportType stripped to null', () async {
    await RnApi.contributionReport(
        {'fromDate': '2026-01-01T00:00:00.000Z', 'toDate': '2026-09-01T00:00:00.000Z', 'reportType': 'HQ'});

    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/Reports/Contribution');
    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['reportType'], isNull);
  });

  test('the other literal value (BRANCH) is stripped the same way', () async {
    await RnApi.contributionReport(
        {'fromDate': '2026-01-01T00:00:00.000Z', 'toDate': '2026-09-01T00:00:00.000Z', 'reportType': 'BRANCH'});

    final body = jsonDecode(sent.single.body) as Map<String, dynamic>;
    expect(body['reportType'], isNull);
  });
}

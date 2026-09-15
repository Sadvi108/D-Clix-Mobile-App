// Every endpoint the app calls must exist on the server, with the verb the app uses.
//
// This is a STATIC audit: it scans every .dart file under lib/, pulls out each
// `ApiService.<verb>('<path>')` call, and checks path and verb against
// test/fixtures/club_api_routes.json — the route table taken from the live UAT swagger
// (73 paths, fetched 2026-09-10).
//
// It catches the failure mode no amount of Dart type-checking can: a path typo, a renamed
// route, or a GET against a POST-only endpoint. Those compile perfectly and fail only
// against the real server, usually in someone's hands.
//
// It does NOT check request bodies or that a route behaves correctly — that needs
// live_api_smoke_test.dart, which requires credentials.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One `ApiService.<verb>('<path>')` call found in the source.
class ApiCall {
  final String verb;
  final String path;
  final int line;
  final String file;
  const ApiCall(this.verb, this.path, this.line, this.file);
  @override
  String toString() => '$verb $path ($file:$line)';
}

/// Normalise a Dart endpoint literal into a swagger path.
///
/// `'/Listing/StudentListByTcId/${_enc(id)}'` -> `/Listing/StudentListByTcId/{}`
String normalise(String raw) {
  var s = raw;
  // `_qs(...)` builds a QUERY STRING ("?a=b"), not a path segment. Treating it as a path
  // param turned /Payment/Initiate into /Payment/Initiate{} and reported a live route as
  // missing.
  final qs = s.indexOf(r'${_qs(');
  if (qs >= 0) s = s.substring(0, qs);
  // Remaining interpolations, `${...}` and bare `$name`, are path params.
  s = s.replaceAll(RegExp(r'\$\{[^}]*\}'), '{}');
  s = s.replaceAll(RegExp(r'\$[A-Za-z_][A-Za-z0-9_]*'), '{}');
  final q = s.indexOf('?');
  if (q >= 0) s = s.substring(0, q);
  return s;
}

/// Swagger's `{param}` segments normalised the same way, so the two can be compared.
String normaliseSwagger(String raw) =>
    raw.replaceAll(RegExp(r'\{[^}]*\}'), '{}');

/// Does an app path match a swagger path?
///
/// Segment-wise, because a swagger `{param}` matches ANY single segment — including a
/// value the app hardcodes. `/Listing/StoreVersion/android` is correct wiring against
/// `/Listing/StoreVersion/{platform}`; comparing normalised strings flagged it as a
/// missing route.
bool pathMatches(String appPath, String swaggerPath) {
  final a = appPath.split('/');
  final b = swaggerPath.split('/');
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    // '{}' on either side is a wildcard: a swagger param, or an app interpolation.
    if (b[i] == '{}' || a[i] == '{}') continue;
    if (a[i].toLowerCase() != b[i].toLowerCase()) return false;
  }
  return true;
}

/// The swagger route a call resolves to, or null.
String? resolve(String appPath, Iterable<String> swaggerPaths) {
  final norm = normalise(appPath);
  String? wildcardMatch;
  for (final sp in swaggerPaths) {
    final ns = normaliseSwagger(sp);
    // Prefer an exact literal match over one that had to use a wildcard.
    if (ns == norm) return sp;
    if (pathMatches(norm, ns)) wildcardMatch ??= sp;
  }
  return wildcardMatch;
}

final _callRe = RegExp(
    r"""ApiService\.(get|post|put|delete|postMultipart)\(\s*'([^']+)'""");

/// Scan a whole file at once — `\s*` spans newlines, and plenty of calls in api.dart wrap
/// the path onto the following line. A line-by-line scan missed those silently.
List<ApiCall> parseApiCalls(String source, String file) {
  final calls = <ApiCall>[];
  for (final m in _callRe.allMatches(source)) {
    var verb = m.group(1)!.toUpperCase();
    if (verb == 'POSTMULTIPART') verb = 'POST';
    final line = '\n'.allMatches(source.substring(0, m.start)).length + 1;
    calls.add(ApiCall(verb, m.group(2)!, line, file));
  }
  return calls;
}

/// Every ApiService call anywhere under lib/ — not just api.dart. The Boost calls live in
/// boost_payment.dart and user_session.dart makes its own; scanning one file reported
/// "the Boost calls disappeared" because they were never in scope.
List<ApiCall> scanLib() {
  final calls = <ApiCall>[];
  for (final e in Directory('lib').listSync(recursive: true)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    calls.addAll(parseApiCalls(e.readAsStringSync(), e.uri.pathSegments.last));
  }
  return calls;
}

void main() {
  late Map<String, List<String>> routes;
  late List<ApiCall> calls;

  setUpAll(() {
    routes = (jsonDecode(
                File('test/fixtures/club_api_routes.json').readAsStringSync())
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as List).cast<String>()));
    calls = scanLib();
  });

  test('the audit actually found the API surface', () {
    // Guards the parser: if lib/ is restructured and this stops matching, every other
    // test in the file would report "no problems" over an empty set.
    expect(calls.length, greaterThan(60),
        reason:
            'only found ${calls.length} calls — the parser is probably broken');
    expect(routes.length, 73);
    expect(calls.map((c) => c.file).toSet(), contains('boost_payment.dart'));
  });

  test('normalise handles the shapes the source actually uses', () {
    expect(normalise(r"/Listing/StudentListByTcId/${_enc(id)}"),
        '/Listing/StudentListByTcId/{}');
    expect(normalise(r'/Profile/UpdateNotification2Read${_qs(body)}'),
        '/Profile/UpdateNotification2Read');
    expect(normalise(r'/Bcpg/VerifyPayment/$ref'), '/Bcpg/VerifyPayment/{}');
    expect(normaliseSwagger('/Utilities/QRCode/{width}/{height}/{content}'),
        '/Utilities/QRCode/{}/{}/{}');
  });

  test('pathMatches treats a hardcoded param value as a match', () {
    // /Listing/StoreVersion/android against /Listing/StoreVersion/{platform}.
    expect(
        pathMatches(
            '/Listing/StoreVersion/android', '/Listing/StoreVersion/{}'),
        isTrue);
    expect(pathMatches('/Listing/StoreVersion', '/Listing/StoreVersion/{}'),
        isFalse,
        reason: 'a missing segment is not a match');
    expect(pathMatches('/Listing/Other/android', '/Listing/StoreVersion/{}'),
        isFalse);
  });

  test('every endpoint the app calls exists on the server', () {
    // These four proposed contracts were preserved from Expo; their UI explicitly
    // handles 404 as Awaiting backend. Keep this exception narrow and visible.
    const proposed = {
      '/Reports/OnlineSubmissions',
      '/Reports/OnlineSubmissionDetails/{}',
      '/Account/ApproveStudent',
      '/Account/RejectStudent'
    };
    // Manual attendance reads the route table itself and only calls its proposed route once
    // the server lists it (docs/specs/2026-09-15-manual-attendance.md).
    const manualAttendance = {'/swagger/v1/swagger.json', '/Attendance/MarkByInstructor'};
    final missing = calls
        .where((c) =>
            resolve(c.path, routes.keys) == null &&
            !(c.file == 'online_submissions.dart' &&
                proposed.contains(normalise(c.path))) &&
            !(c.file == 'manual_attendance.dart' && manualAttendance.contains(normalise(c.path))))
        .toList();
    expect(missing, isEmpty,
        reason:
            'these paths are not in the server route table:\n${missing.join('\n')}');
  });

  test('every call uses a verb the server accepts on that path', () {
    // The trap this catches: /PurchaseRequest/FetchProducts reads like a GET and is a
    // POST. The wrong verb returns 405, which surfaces as an empty screen rather than an
    // obvious error.
    final wrong = <String>[];
    for (final c in calls) {
      final route = resolve(c.path, routes.keys);
      if (route == null) continue; // reported by the previous test
      final allowed = routes[route]!;
      if (!allowed.contains(c.verb)) {
        wrong.add('$c uses ${c.verb}; server allows ${allowed.join("/")}');
      }
    }
    expect(wrong, isEmpty, reason: wrong.join('\n'));
  });

  test('only /Bcpg routes are sent to the other host', () {
    // /Bcpg is not deployed to production and is routed to UAT instead. If any other path
    // ever started matching isBoostPath, ordinary traffic would silently cross hosts.
    final boost = calls.where((c) => c.path.startsWith('/Bcpg')).toList();
    expect(boost, isNotEmpty, reason: 'the Boost calls disappeared');
    expect(boost.map((c) => c.file).toSet(), {'boost_payment.dart'},
        reason: 'Boost calls should stay in one place');
  });

  test('reports which server routes the app never calls', () {
    // Not a failure — several routes are server-to-server callbacks or unused by design.
    // Printing the list keeps a genuinely missing feature visible instead of assumed.
    final called = <String>{};
    for (final c in calls) {
      final r = resolve(c.path, routes.keys);
      if (r != null) called.add(r);
    }
    final unused = routes.keys.where((k) => !called.contains(k)).toList()
      ..sort();
    // ignore: avoid_print
    print(
        'Server routes not called by the app (${unused.length}/${routes.length}):\n'
        '  ${unused.join('\n  ')}');

    // These three are the gateway's own server-to-server legs — the browser and the
    // backend hit them, never this app. Anything else appearing here is worth a look.
    expect(unused,
        containsAll(['/Bcpg/Callback', '/Bcpg/Redirect', '/Payment/Callback']));
  });
}

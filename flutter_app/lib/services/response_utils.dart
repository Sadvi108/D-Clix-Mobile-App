// Shared helpers for turning varied API JSON responses into a clean
// list of record maps and reading fields out of them.

/// Unwrap the backend's `{status, meta, data}` envelope.
///
/// `data` is omitted entirely when a route has nothing to return (e.g.
/// `GET /Listing/DropdownListByType/6` -> `{"status":200,"meta":{"code":200}}`), so keying
/// off the presence of `data` alone hands callers the envelope itself where they expected a
/// payload. Anything carrying a `meta` block is an envelope; its absent `data` unwraps to
/// null. Responses without `meta` (e.g. `/Bcpg/VerifyPayment` -> `{status: "NotFound"}`)
/// are returned untouched.
dynamic unwrapData(dynamic resp) {
  if (resp is Map) {
    if (resp.containsKey('data')) return resp['data'];
    if (resp['meta'] is Map) return null;
  }
  return resp;
}

/// Recursively locate the first List of records in an API response.
/// Handles `{data: [...]}`, `{data: {rows: [...]}}`, bare lists, etc.
List<dynamic> findRecordList(dynamic resp) {
  if (resp is List) return resp;
  if (resp is Map) {
    const keys = [
      'data',
      'items',
      'rows',
      'results',
      'value',
      'records',
      'collections',
      'slips',
      'list',
      'payments',
    ];
    for (final k in keys) {
      final v = resp[k];
      if (v is List) return v;
    }
    for (final v in resp.values) {
      if (v is List) return v;
      if (v is Map) {
        final nested = findRecordList(v);
        if (nested.isNotEmpty) return nested;
      }
    }
  }
  return const [];
}

/// Inspect an API response envelope and return a human-readable error
/// message when it signals failure, or null when it looks successful.
///
/// The backend wraps some failures in an HTTP-200 body, e.g. a wrong login
/// returns `{status: 404, meta: {code: 404, error: "Account not found..."}}`.
/// Callers that only check the HTTP status miss these, so this reads the
/// envelope's own `status` / `meta.code` and surfaces `meta.error`
/// (or a top-level `error`/`message`) instead of a generic failure.
String? apiEnvelopeError(dynamic resp) {
  if (resp is! Map) return null;
  final meta = resp['meta'];
  final code = apiEnvelopeErrorCode(resp);
  if (code == null) return null;
  final metaError = (meta is Map)
      ? ((meta['error'] ?? meta['message'])?.toString().trim() ?? '')
      : '';
  if (metaError.isNotEmpty) return friendlyError(metaError);
  final topError = (resp['error'] ?? resp['message'] ?? '').toString().trim();
  if (topError.isNotEmpty && topError != 'null') return friendlyError(topError);
  return 'Request failed (status $code).';
}

/// Both slots must be checked: a report may return status 200 with meta.code 400.
/// String gateway statuses such as "NotFound" are payment data, not HTTP codes.
int? apiEnvelopeErrorCode(dynamic resp) {
  if (resp is! Map) return null;
  final meta = resp['meta'];
  final codes = [resp['status'], if (meta is Map) meta['code']]
      .whereType<num>()
      .where((code) => code >= 400)
      .map((code) => code.toInt())
      .toList();
  if (codes.isNotEmpty) return codes.reduce((a, b) => a > b ? a : b);
  return resp['status'] == false ? 400 : null;
}

/// Turn any error/exception into a short, user-facing message — never show a
/// raw `Exception:` / `ClientException: XMLHttpRequest error` string to users.
/// Maps the common classes (network, auth, server) to friendly text and strips
/// the Dart exception prefix and our `❌` glyph from anything else.
String friendlyError(Object? e) {
  final raw = (e ?? '').toString();
  final lower = raw.toLowerCase();
  // A FormatException quotes the body it could not parse. Over plain HTTP that body can be a
  // Wi-Fi sign-in or proxy page answering in place of the API: raw HTML.
  if (raw.startsWith('FormatException')) {
    return 'Unexpected response from the server. Please try again.';
  }
  if (raw.length > 200 ||
      RegExp(r'nvarchar|varchar|sql|ado\.net|stack trace|System\.|Microsoft\.|Npgsql|ORA-\d|constraint|column name|object reference not set|inner exception|\.cs:line',
              caseSensitive: false)
          .hasMatch(raw)) {
    return 'The club server could not complete that request. Please try again.';
  }
  if (lower.contains('xmlhttprequest') ||
      lower.contains('clientexception') ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection') && lower.contains('refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('timeout')) {
    return 'Network error — please check your connection and try again.';
  }
  if (lower.contains('401') || lower.contains('unauthorized')) {
    return 'Your session has expired. Please log in again.';
  }
  if (RegExp(r'\b5\d\d\b').hasMatch(raw) || lower.contains('internal server')) {
    return 'Server error — please try again in a moment.';
  }
  // Strip "Exception: " prefixes and our error glyph from the remaining text.
  final cleaned = raw
      .replaceAll(RegExp(r'^[A-Za-z]*Exception:\s*'), '')
      .replaceAll('❌', '')
      .trim();
  return cleaned.isEmpty ? 'Something went wrong. Please try again.' : cleaned;
}

/// First non-empty string value across a set of candidate keys.
String pickField(Map row, List<String> keys) {
  for (final k in keys) {
    final v = row[k];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty && s != 'null') return s;
  }
  return '';
}

/// First numeric value across a set of candidate keys.
num pickAmount(Map row, List<String> keys) {
  for (final k in keys) {
    final v = row[k];
    if (v is num) return v;
    if (v is String) {
      final n = num.tryParse(v.replaceAll(RegExp(r'[^\d.\-]'), ''));
      if (n != null) return n;
    }
  }
  return 0;
}

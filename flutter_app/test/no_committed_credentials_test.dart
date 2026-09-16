// No working password may be written into a file in this repository.
//
// The repository is PUBLIC. Live Club.Api accounts leaked through it twice: once through the
// Expo sign-in screen's pre-filled test accounts, and again through api_tests.http, which the
// Flutter import carried over after the first scrub. A request body with a literal password
// looks harmless in a REST-client scratch file and is a working login for anyone who reads it.
// Scratch requests read credentials from the gitignored .env instead ({{$dotenv ...}}).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `"password": "1234"` / `'password': 'x'` — a quoted key with a literal string value.
/// A variable (`'password': password`) or a template (`"{{$dotenv ...}}"`) is not a literal.
final _literalPassword =
    RegExp(r'''["'](?:password|passwd|pwd)["']\s*:\s*["'](?![{$])[^"']+["']''', caseSensitive: false);

const _scanned = {'.http', '.rest', '.json', '.dart', '.md', '.yaml', '.yml', '.env', '.properties'};
const _skippedDirs = {'build', '.dart_tool', 'Pods', '.gradle', 'ephemeral', '.symlinks'};

Iterable<File> _sourceFiles(Directory root) sync* {
  for (final entity in root.listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is Directory) {
      if (!_skippedDirs.contains(name)) yield* _sourceFiles(entity);
    } else if (entity is File && _scanned.any(name.endsWith)) {
      yield entity;
    }
  }
}

void main() {
  test('the scanner matches a literal password and ignores variables and templates', () {
    expect(_literalPassword.hasMatch('"password": "1234",'), isTrue);
    expect(_literalPassword.hasMatch("'password': 'hunter2'"), isTrue);
    expect(_literalPassword.hasMatch("'password': password,"), isFalse);
    expect(_literalPassword.hasMatch(r'"password": "{{$dotenv DCLIX_TEST_PASS}}"'), isFalse);
  });

  test('no file in the app carries a literal password', () {
    final files = _sourceFiles(Directory.current).toList();
    expect(files.length, greaterThan(50), reason: 'the walker must actually find the sources');

    final hits = <String>[
      for (final file in files)
        for (final (i, line) in file.readAsLinesSync().indexed)
          if (_literalPassword.hasMatch(line) && !file.path.endsWith('no_committed_credentials_test.dart'))
            '${file.path.replaceFirst('${Directory.current.path}/', '')}:${i + 1}',
    ];
    expect(hits, isEmpty, reason: 'literal passwords in a public repository: $hits');
  });
}

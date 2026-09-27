// The user guide is instructions a member acts on, so the content is worth asserting.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dclix_app/data/guide_content.dart';

void main() {
  test('all pages are present and distinct', () {
    // 11 ported from Expo + the Auto Pay page this app added.
    expect(kGuideSteps, hasLength(12));
    expect(kGuideSteps.map((s) => s.key).toSet(), hasLength(12),
        reason: 'duplicate keys would mean a page was overwritten');
  });

  test('every page has a title, an intro and numbered steps', () {
    for (final s in kGuideSteps) {
      expect(s.title.trim(), isNotEmpty, reason: '${s.key} has no title');
      expect(s.intro.trim(), isNotEmpty, reason: '${s.key} has no intro');
      expect(s.details, isNotEmpty, reason: '${s.key} has no steps');
      for (final d in s.details) {
        expect(d.title.trim(), isNotEmpty, reason: '${s.key} step ${d.n} has no title');
        expect(d.text.trim(), isNotEmpty, reason: '${s.key} step ${d.n} has no text');
      }
    }
  });

  test('step numbers run 1..n with no gaps or repeats', () {
    for (final s in kGuideSteps) {
      expect(s.details.map((d) => d.n).toList(),
          List.generate(s.details.length, (i) => i + 1),
          reason: '${s.key} is misnumbered');
    }
  });

  String _blob(dynamic s) => [
        s.intro as String,
        s.note as String,
        ...(s.tips as List<String>),
        ...(s.details as List).map((d) => '${d.title} ${d.text}'),
      ].join(' ').toLowerCase();

  test('no page claims fees are paid without the member', () {
    // Only a member who switched on Auto Pay and linked a card or bank on Boost is charged
    // without tapping Pay. A member who believes their fees settle on their own stops
    // checking and falls into arrears, so no page may make that promise in general terms.
    final banned = [
      'settles fees',
      'paid automatically',
      'pays automatically',
      'charged automatically',
      'taken automatically from',
      'deducted automatically',
    ];
    for (final s in kGuideSteps) {
      final blob = _blob(s);
      for (final phrase in banned) {
        expect(blob, isNot(contains(phrase)),
            reason: '${s.key} claims payment happens on its own: "$phrase"');
      }
    }
  });

  test('the Auto Pay page says where card details go and how to stop', () {
    final page = kGuideSteps.firstWhere((s) => s.key == 'autopay');
    final blob = _blob(page);
    expect(blob, contains('boost'));
    expect(blob, contains('never sees'),
        reason: 'the member must know the app does not hold their card or bank login');
    expect(blob, contains('turn auto pay off'));
    expect(page.note.trim(), isNotEmpty);
  });

  test('the sign-in page comes first', () {
    // It is linked from the login screen, so a reader with no account starts there.
    expect(kGuideSteps.first.key, 'signin');
  });

  test('the pages that carry a warning still carry it', () {
    final withNotes = kGuideSteps.where((s) => s.note.trim().isNotEmpty).map((s) => s.key);
    expect(withNotes, containsAll(['checkin', 'payments', 'profile']));
  });

  group('screenshots', () {
    test('every declared shot points at an asset that exists', () {
      // A missing asset renders as nothing (the guide swallows the error rather than
      // blanking the page), so a typo would silently cost a picture.
      final missing = <String>[];
      for (final step in kGuideSteps) {
        if (step.shot.isEmpty) continue;
        if (!File(step.shot).existsSync()) missing.add('${step.key} -> ${step.shot}');
      }
      expect(missing, isEmpty, reason: 'declared but not on disk: $missing');
    });

    test('every shipped asset is referenced by a page', () {
      // The other direction: an orphan PNG is dead weight in the APK.
      final dir = Directory('assets/guide');
      if (!dir.existsSync()) return;
      final referenced = kGuideSteps.map((s) => s.shot).toSet();
      final orphans = dir
          .listSync()
          .whereType<File>()
          .map((f) => 'assets/guide/${f.uri.pathSegments.last}')
          .where((p) => !referenced.contains(p))
          .toList();
      expect(orphans, isEmpty, reason: 'unreferenced assets: $orphans');
    });

    test('the pages a reader most needs a picture of have one', () {
      for (final key in ['signin', 'payments', 'schedule', 'everything']) {
        final step = kGuideSteps.firstWhere((s) => s.key == key);
        expect(step.shot, isNotEmpty, reason: '$key lost its screenshot');
      }
    });
  });
}

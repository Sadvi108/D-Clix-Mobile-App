// The iOS app must never be built for anything below iOS 15.
//
// Xcode 27 refuses deployment targets under 15.0 ("the range of supported deployment target
// versions is 15.0 to 27.0.x"), and several plugin pods still declare 9.0-14.0, so the
// Podfile lifts them. Lowering any of these again breaks the simulator and App Store builds.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _minimum = 15.0;

void main() {
  test('Podfile platform is iOS 15 or later', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    final platform = RegExp(r"^platform :ios, '([\d.]+)'", multiLine: true).firstMatch(podfile);
    expect(platform, isNotNull, reason: 'the platform line must stay uncommented');
    expect(double.parse(platform!.group(1)!), greaterThanOrEqualTo(_minimum));
  });

  test('Podfile raises plugin pods that declare an older target', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    expect(podfile, contains("config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'"));
  });

  test('every Runner build configuration targets iOS 15 or later', () {
    final project = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
        .allMatches(project)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(targets, isNotEmpty);
    expect(targets.where((t) => t < _minimum), isEmpty, reason: 'found targets: $targets');
  });
}

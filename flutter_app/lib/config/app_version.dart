/// The app version shown in the UI.
///
/// Kept in one place and checked against pubspec.yaml by test/app_version_test.dart —
/// the profile screen previously hardcoded "v1.0.0" and had drifted several releases
/// behind, which makes a member's bug report ("I'm on 1.0.0") actively misleading.
const String kAppVersion = '2.13.1';

/// Android versionCode / iOS build number.
const int kAppBuild = 22;

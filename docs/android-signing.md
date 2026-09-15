# Android release signing

Release APKs and app bundles are signed with the D-CLIX **upload key**. Google Play
re-signs installs with its own app signing key (Play App Signing); the upload key
proves uploads come from us.

**Losing the keystore or its passwords blocks future Play uploads until Google resets
the upload key.** Keep the `.jks` file and both passwords in a password manager, plus
one offline backup. Never commit them; `android/.gitignore` excludes `*.jks` and
`key.properties`.

## 1. Create the upload keystore (once)

```bash
keytool -genkeypair -v -keystore ~/dclix-upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

`keytool` asks for the keystore password, your name/organisation and the key password.

## 2. Add GitHub repository secrets

From the repository root, with the GitHub CLI signed in:

```bash
base64 -i ~/dclix-upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS --body upload
gh secret set ANDROID_KEY_PASSWORD
```

The password commands prompt for the value, so it never lands in shell history.

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The `.jks` file, base64-encoded |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias (`upload` above) |
| `ANDROID_KEY_PASSWORD` | Key password |

## 3. Release

Bump `version:` in `flutter_app/pubspec.yaml`, add `docs/releases/flutter-v<version>.md`,
then push a tag:

```bash
git tag -a flutter-v2.14.0 -m "D-CLIX Flutter 2.14.0" && git push origin flutter-v2.14.0
```

The **Build Flutter APK** workflow builds `app-release.apk` (direct install) and
`app-release.aab` (Google Play upload), checks the signature and publishes both with
SHA-256 files as a GitHub Release. A tag with a suffix (`flutter-v2.14.0-beta.1`)
publishes as a pre-release. A tag built without the secrets still publishes, but only as a
pre-release named "(test build)" with a debug-signed APK, never as a full release.

Pushes to `main` and pull requests still build; without the secrets they produce a
debug-signed APK for testing.

## Signing locally (optional)

Create `flutter_app/android/key.properties`:

```properties
storeFile=/Users/you/dclix-upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

`flutter build apk --release` and `flutter build appbundle --release` then use the
upload key. Delete the file to go back to debug signing.

## Switching from debug-signed test builds

Earlier GitHub releases were signed with a debug key. Android refuses to update an app
signed with a different key, so testers must uninstall the old build before installing
the first upload-key build. Local app data is lost on uninstall.

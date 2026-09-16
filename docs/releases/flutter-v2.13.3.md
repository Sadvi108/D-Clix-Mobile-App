D-Clix v2.13.3 (build 24), package `com.dclix.clubapp`.

**Fixed: profile photos and club logos missing on some Android phones**

Student photos, instructor photos and club logos did not appear on some Android phones (reported on devices running Android 7–12); initials or a placeholder showed instead. iPhones and newer Android phones were not affected.

The photos are served from `www.maclubsystem.com`, whose certificate depends on a newer Sectigo root certificate that older Android phones do not have. The app now includes that public root certificate and trusts it for its own connections on Android, so photos load on those phones too. Nothing else about the app's security changes.

For the club's IT team: installing the full certificate chain on `www.maclubsystem.com` (including the cross-signed Sectigo R46 certificate) fixes this for every app and browser.

Everything from v2.13.2 (premium profile and instructor screens) is included.

**Known limits** (unchanged)
- Instructors cannot mark attendance until the backend adds the marking route.
- Students per training time and a real tournament list also need backend routes.
- The app still talks to the server over plain HTTP until the server certificate is fixed.

**Installation:** this is a release-mode **debug-signed test build**, published as a pre-release. Each test build may be signed with a different debug key, so Android can refuse to install it over an earlier download; uninstall the old build first if that happens (local app data is lost). It cannot be uploaded to Google Play. The attached SHA-256 files verify the downloaded bytes.

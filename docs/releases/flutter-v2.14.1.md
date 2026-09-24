D-Clix v2.14.1 (build 26), package `com.dclix.clubapp`.

**Payments reach the gateway**

The payment server uses a certificate phones do not trust, and the app's own network layer refused every call to it — so paying a purchase request never opened the Boost page on any phone. The app now trusts that one certificate, for that one server only, and nothing else about how it checks certificates changes.

Paying **dues** now uses the payment call the club system actually serves for invoices, and the app also recognises the gateway's "payment finished" pages, so it comes back into the app and checks the result instead of leaving you on the last page.

**Dues still cannot be paid.** The club server itself fails when it looks up the amount for an invoice or for advance months, and returns an error instead of a payment link. It fails the same way for an invoice number that does not exist, so it breaks before it ever reads your invoice. The backend team has the exact error. Purchase requests are unaffected and do open the Boost page.

**Also in this build**
- Back now works properly from screens opened through Quick Access and All Features.
- Instructor reports: the Contribution report no longer fails to load, and every instructor screen lists training centres from one source, so the same centres appear everywhere.
- Instructor class lists are ready to show student photos beside names; photos appear as soon as the server sends them, and initials show until then.

**Known limits** (unchanged)
- Paying dues and advance months needs the backend fix above.
- Instructors cannot mark attendance until the backend adds the marking route.
- Students per training time and a real tournament list also need backend routes.
- The app still talks to the server over plain HTTP until the server certificate is fixed.
- Students are signed out after about an hour, because the login token expires and the server has no way to renew it.

**Installation:** this is a release-mode **debug-signed test build**, published as a pre-release. Each test build may be signed with a different debug key, so Android can refuse to install it over an earlier download; uninstall the old build first if that happens (local app data is lost). It cannot be uploaded to Google Play. The attached SHA-256 files verify the downloaded bytes.

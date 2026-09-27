D-Clix v2.15.0 (build 27), package `com.dclix.clubapp`.

**New: Auto Pay with a saved card**

Auto Pay is no longer a monthly reminder. Save a debit or credit card once on Boost's secure page, and your pending invoices are paid from it for you.

- **Payments → Auto Pay**, turn the switch on, and Boost's card page opens inside the app. The app never sees your card number.
- Boost charges **RM 1.00** to check the card and refunds it later.
- When you finish, the app comes back on its own and shows the saved card, for example "Visa •••• 4242, expires 08/28".
- Turning Auto Pay off unlinks the card. To turn it on again, you enter the card again.

The old reminder notifications for Auto Pay are gone, along with the day-of-month setting.

**Paying dues now reaches Boost**

Paying invoices from **Pay Your Dues** or **Payments** now opens Boost's checkout with the right amount, where you can pay by card or online banking (FPX). The server fault that stopped this in v2.14.1 has been fixed on the backend.

The app now also lets the server's "finishing" page load after you pay, so the server can record the result before the app comes back and checks it.

**Also in this build**
- The payment page now opens above the bottom tab bar, so Boost's **Pay** and **Cancel** buttons are no longer hidden behind it.
- The launch animation draws the logo's flash between D and CLIX.

**Known limits**
- Auto Pay and online payments run on the club's test (UAT) server and Boost's **staging** gateway, which record against the live club records. Card and FPX payments here are test transactions.
- Advance payment for months that have no invoice yet has not been re-tested since the backend fix.
- Instructors cannot mark attendance until the backend adds the marking route.
- Students per training time and a real tournament list also need backend routes.
- Students are signed out after about an hour, because the login token expires and the server has no way to renew it.

**Installation:** this is a release-mode **debug-signed test build**, published as a pre-release. Each test build may be signed with a different debug key, so Android can refuse to install it over an earlier download; uninstall the old build first if that happens (local app data is lost). It cannot be uploaded to Google Play. The attached SHA-256 files verify the downloaded bytes.

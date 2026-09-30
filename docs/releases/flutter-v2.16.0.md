D-Clix v2.16.0 (build 28), package `com.dclix.clubapp`.

**Auto Pay: pause, resume and a setup step**

- Turning Auto Pay on now asks how much to take from your card each month. If more than one member of your family trains at the academy, the app lists everyone Auto Pay covers. It always covers the whole family together.
- Once it is on, **Pause** holds payments without removing your card, and **Resume** starts them again. **Disable** removes the card after asking "Remove your card?".
- The Auto Pay screen shows the saved card as "Card •••• 5000" with its expiry, plus the monthly amount and who is covered.

Pausing, resuming and the monthly amount need a backend update that is still in progress. Until it lands, Pause and Resume say "not available yet", and the amount you enter is not applied.

**New**
- **Your info on Home:** registration number, student code, training centre and time, exam centre, instructor, current grade with its belt colour, last grading date, and your next tournament with a countdown.
- **Forgot password** is back on the sign-in screen.
- **Edit Profile** now covers school, class, t-shirt size, height, weight, blood type, food type and health status, and lets you change your password.
- **Requests in Notifications:** accept or reject a request from the club right on the notification.
- Every tab has a back button, including when you open it from Home or All Features.

**Fixed**
- All Features: Training, Today's Classes, Timetable, My Trainer, Fees Due, Payment History, Advance Payment, Progress Report and Profile opened a blank page.
- **Pay in Advance** now reaches the payment gateway and bills the months you chose, online and by Bank-In.
- Paying invoices for two children in one payment billed only one of them. The app now asks you to pay for one child at a time.
- Payment History shows a sibling's payments, and one child picker now drives both Pay and History.
- Pay Your Dues: the transaction-type filter now narrows the list.
- Schedule shows approved class bookings on their date.
- Booking a class books for the child on screen and respects your package's quota.
- A child picked on one account no longer carries over after signing out or into another account.
- Fees & Payments: the pay bar no longer floats above the tab bar with a gap.
- Home's trainer matches your class schedule, and a picked child's details refresh when you switch.
- The launch animation's lettering now matches the logo.

**For instructors**
- Grading Schedule and Grade Completed show only your club's exams. They listed every club's.
- The QR scanner records instructor self check-in and scanning a student correctly, with a Self / Students switch.

**Club settings**
- Features the club has switched off (class booking, attendance, online payment, reports, collections) are now hidden instead of shown.

**Removed**
- Home's Featured Offers carousel. The Offers screen is still in All Features.
- The "Contact your academy" line under sign-in.

**Known limits**
- Auto Pay and online payments run on the club's test (UAT) server and Boost's **staging** gateway, which record against the live club records. Card and FPX payments here are test transactions.
- On Boost's staging gateway some test cards are rejected by the card issuer before any OTP appears. Use the card the test flow uses.
- Paying a month that has no invoice yet (Pay in Advance) has not been checked end to end with a live account.
- Instructors cannot mark attendance until the backend adds the marking route.
- Students are signed out after about an hour, because the login token expires and the server has no way to renew it.

**Installation:** this is a release-mode **debug-signed test build**, published as a pre-release. Each test build may be signed with a different debug key, so Android can refuse to install it over an earlier download; uninstall the old build first if that happens (local app data is lost). It cannot be uploaded to Google Play. The attached SHA-256 files verify the downloaded bytes.

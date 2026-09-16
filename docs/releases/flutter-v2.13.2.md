D-Clix v2.13.2 (build 23), package `com.dclix.clubapp`.

A design release: the profile and the main instructor screens get the new premium look.

**Students**
- **Profile** has a compact header with your status and grade, a dark **Member ID** card, quick actions (Check In, My Details, Purchases, Help Desk), grouped details and settings, and a clear Log out button.
- Tap your registration number or phone number to **copy** it. Tap the QR to show it **full screen** at the counter.
- Dark mode can be switched from the profile header or the settings list.
- Switch-student and switch-club sheets now open above the tab bar.

**Instructors**
- **Profile** shows a **Staff ID** card, quick actions (Check-In, Reports, Collections, Help Desk), club figures as coloured tiles and your branches.
- **Home**: dark Outstanding Dues card, Quick Access grouped into *Classes & students* and *Payments & records*, and a *Club at a glance* section.
- **Collections**: a summary of records to review with the Update Collection button, and each payment type with its count.
- **Reports**: search box and reports grouped into three sections.

**Known limits** (unchanged from v2.13.1)
- Instructors cannot mark attendance until the backend adds the marking route.
- Students per training time and a real tournament list also need backend routes.
- The app still talks to the server over plain HTTP until the server certificate is fixed.

**Installation:** this is a release-mode **debug-signed test build**, published as a pre-release. Each test build may be signed with a different debug key, so Android can refuse to install it over an earlier download; uninstall the old build first if that happens (local app data is lost). It cannot be uploaded to Google Play. The attached SHA-256 files verify the downloaded bytes.

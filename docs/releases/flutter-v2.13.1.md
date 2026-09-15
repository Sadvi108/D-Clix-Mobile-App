D-Clix v2.13.1 (build 22), package `com.dclix.clubapp`.

**Students**
- **Progress Report** and **Belt / Rank** are separate screens. Progress Report shows your attendance rate for 30, 90 or 365 days (Present and Absent only), classes this month, your weekly streak, your last class and a six-month chart. Belt / Rank shows your grade exactly as your academy recorded it, including sub-ranks such as "Green 2".
- The Grading tile is removed: the grading schedule returned no entries for student accounts.
- **Competition is now Tournament.** It shows your medal and player totals. The Upcoming / Past tabs are gone because the club system has no tournament dates yet.
- Home: rounded shortcut cards, fully rounded headers and a new Fees Due card.
- Notification Settings no longer shows the technical "How delivery works" notes.

**Instructors**
- **Training Schedule** lists every class at all your centres, grouped by day, with centre and day filters. Tap a class to see and search that centre's students.
- **Student List** no longer spins forever when centres fail to load, and names any centre whose students could not be loaded.
- "Tournaments (Past)" and "Upcoming Tournaments" are merged into one **Tournament Summary**.
- **Class Check-In** has a tick-and-save register that switches on automatically once the club server supports instructor marking. Until then, students check in by scanning the centre QR.

**Platform**
- iOS builds now require iOS 15 or later.

**Known limits**
- Instructors cannot mark attendance until the backend adds the marking route.
- Students per training time and a real tournament list also need backend routes.
- The app still talks to the server over plain HTTP until the server certificate is fixed.

**Installation:** this is a release-mode **debug-signed test build**, published as a pre-release. Each test build may be signed with a different debug key, so Android can refuse to install it over an earlier download; uninstall the old build first if that happens (local app data is lost). It cannot be uploaded to Google Play. The attached SHA-256 files verify the downloaded bytes.

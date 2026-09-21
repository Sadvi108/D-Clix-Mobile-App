D-Clix v2.14.0 (build 25), package `com.dclix.clubapp`.

**New: karate launch animation**

When the app opens, a karate figure bows, drops into stance, punches and throws a high roundhouse kick; its belt ranks up from yellow to brown with each move. The figure's own lines then morph into the **D/CLIX** wordmark, and the orange kick trail becomes the slash. The slash sends out a ring that bursts into the D-Clix badge above the word, and rings ripple from the badge while the app checks your saved sign-in.

- Signed out: the badge and the word glide up into the Sign In screen's header.
- Signed in: the logo zooms away into your Home screen.
- With **Reduce Motion** / **Remove animations** turned on in the phone's settings, the app shows the finished logo and skips the animation.

About 3.5 seconds from launch to the Sign In screen. The app still waits for your saved sign-in to load, as before.

Everything from v2.13.3 (photos and club logos on older Android phones) is included. v2.13.3 was published with the version number of v2.13.2 inside the app; this build reports its own version (2.14.0, build 25).

**Known limits** (unchanged)
- Instructors cannot mark attendance until the backend adds the marking route.
- Students per training time and a real tournament list also need backend routes.
- The app still talks to the server over plain HTTP until the server certificate is fixed.

**Installation:** this is a release-mode **debug-signed test build**, published as a pre-release. Each test build may be signed with a different debug key, so Android can refuse to install it over an earlier download; uninstall the old build first if that happens (local app data is lost). It cannot be uploaded to Google Play. The attached SHA-256 files verify the downloaded bytes.

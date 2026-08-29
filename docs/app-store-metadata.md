# App Store and TestFlight metadata draft

The shipping identity is final. Replace the marked support inbox before
creating external TestFlight groups or submitting the public app:

- App name: `Replay Caddie`
- Support and feedback email: `{{SUPPORT_EMAIL}}`

Use bundle identifier `com.peterargany.replaycaddie`. The bundle identifier
is the permanent identity selected for the App Store Connect record.

## App information

- Platform: iOS
- Primary language: English (U.S.)
- SKU: `replay-caddie-ios`
- Primary category: Sports
- Secondary category: Health & Fitness
- Price: Free
- Subtitle: `Golf Swing Video Coach`
- Privacy policy URL: `https://petetheheat.github.io/golf-swing-analyzer/privacy/`
- Support URL: `https://petetheheat.github.io/golf-swing-analyzer/support/`
- App privacy response: Data Not Collected
- Content rights response for the current build: No third-party content is
  included. Revisit this answer before adding licensed reference footage.
- Export compliance: The app uses no non-exempt encryption.
- Sign-in: No account or demo credentials are required.

### Promotional text

See the frame. Fix the swing. Find swings in a longer video, inspect evidence
frame by frame, and turn one practice clip into focused work for the range.

### Description

Replay Caddie turns a golf-swing video into private, frame-by-frame practice
feedback. See the frame. Fix the swing.

Choose a video with Apple's Photos picker. The app finds complete swings in the
footage, lets you refine the exact clip, and analyzes the selected range on your
iPhone. Review address, top, impact, and finish with a body-pose overlay and
evidence at the exact moment behind each finding.

The analysis can highlight measurable patterns such as head movement, posture
change, knee spacing, tempo, and projected hand path when the camera view makes
that measurement appropriate. Each result states its confidence and the limits
of a single 2D camera view.

Save swings to a private library and compare matching moments with another
saved swing or a private reference. Videos and analysis stay on the device.
There is no account, cloud upload, advertising, analytics, or tracking.

This app is a practice aid. It does not replace instruction from a qualified
golf coach and does not measure clubface, ball flight, force, or true 3D motion.

### Keywords

`golf,swing,analysis,coach,tempo,posture,driver,practice,video,pose`

## TestFlight information

### Beta app description

Private, on-device golf swing analysis with automatic swing discovery, manual
trim, body-pose overlays, evidence-based findings, and saved-swing comparison.

### What to test

1. Choose a portrait or landscape golf video from Photos.
2. Confirm that automatic discovery offers each complete swing in a longer
   video and that manual trim remains available.
3. Refine one clip, select camera view, handedness, and club, then analyze it.
4. Scrub the review and open each finding to confirm its evidence frame, guide,
   measurement, confidence, and caveat.
5. Save the swing, reopen it from Library, and compare it with a compatible
   saved swing or private reference.
6. Delete the saved swing and confirm that it disappears from Library.

- Feedback email: `{{SUPPORT_EMAIL}}`
- Sign-in required: No
- Network connection required after an iCloud video has downloaded: No

## App Review notes

All analysis runs on the device with Apple Vision. The app uses the system
Photos picker and receives only the video selected by the reviewer, so no photo
library permission prompt appears. No account, purchase, subscription, or
external hardware is required.

Provide App Review with a rights-cleared golf-swing video and concise import
steps. Do not attach a user's private source video without explicit permission.
For a down-the-line test, the golfer should be fully visible with a stable
camera for several seconds before and after the swing.

The current build contains no distributed professional-golfer footage. Do not
claim that bundled pro comparison is available until a licensed asset has been
added and its rights metadata has been verified.

## Screenshot plan

Create an opaque 6.9-inch iPhone set with the Replay Caddie identity:

1. Import from Photos
2. Automatic swing candidates and manual trim fallback
3. Frame-accurate trim and golfer context
4. Analysis result with evidence overlay
5. Freeze-frame finding with measurement and caveat
6. Same-phase comparison
7. Saved swing Library

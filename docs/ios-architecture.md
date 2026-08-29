# SwingLab iOS architecture

## Platform

- SwiftUI application, iPhone, iOS 17 or later.
- Swift 6 strict concurrency.
- SwiftData for metadata; files for videos, thumbnails, and pose tracks.
- AVFoundation for decode, timestamps, audio, seeking, and frame extraction.
- Vision for on-device body pose.
- SwiftUI Canvas for pose and measurement overlays.
- No runtime third-party dependencies in the first build.

## Modules

```text
ios/SwingLab
  App              composition and navigation
  Design           colors, typography, reusable components
  Persistence      SwiftData models and owned-file lifecycle
  Core/Media       import, storage, playback, thumbnails, trimming
  Core/Pose        Vision extraction, smoothing, coordinate transforms
  Core/Swing       event detection, metrics, findings, scoring
  Core/Reference   reference catalog and phase alignment
  Features/ImportTrim
  Features/Analysis
  Features/Compare
  Features/Flow
```

The app shell currently keeps the small Library and Settings views in `App`.

## Pipeline

```text
PhotosPicker file
  -> private Application Support copy
  -> user-selected CMTimeRange
  -> AVAssetReader timestamped frames
  -> Vision pose frames
  -> smoothing and quality gate
  -> address/top/impact/finish
  -> measurements and findings
  -> SwiftData session + encoded analysis and pose track
  -> synchronized review and comparison
```

The pipeline is a cancellable actor. It reports progress for import, pose,
events, metrics, and persistence. It preserves the imported video if analysis
fails. On the next launch, an interrupted session becomes a removable failed
entry instead of pretending that analysis completed.

## Python relationship

The existing Python program remains a desktop research tool and regression
oracle. The iOS runtime does not embed Python, FFmpeg, OpenCV, NumPy, or the
Python MediaPipe package. Geometry, event logic, metrics, and cautious critique
rules are ported to Swift and tested against exported fixtures.

## TestFlight boundary

Source builds and simulator tests do not require signing. TestFlight requires a
paid Apple Developer team, a bundle identifier, an App Store Connect app record,
an Apple Distribution certificate or automatic signing, a provisioning profile,
an archived Release build, and completed beta metadata. Team identifiers and
credentials must never be committed.

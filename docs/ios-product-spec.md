# SwingLab iOS product specification

## Product promise

SwingLab turns a phone video into a small number of evidence-backed golf swing
observations. The app keeps source video and pose analysis on the device. It
shows the exact frame behind each observation and separates measured evidence
from a coaching hypothesis.

SwingLab is an original product. Sparrow informed the capture-to-coaching
workflow, but SwingLab does not use Sparrow branding, copy, scoring, models,
assets, drills, or professional-golfer footage.

## First TestFlight journey

1. The golfer opens a local swing library.
2. The golfer selects a video from the system Photos picker.
3. SwingLab copies the selected file into its private application storage.
4. SwingLab scans the full imported source on-device and offers each
   complete detected swing as a nondestructive clip range. The golfer can
   cancel, retry, or use manual trim at any time.
5. The golfer chooses a detected clip and refines its frame-snapped in/out
   points, or trims one swing manually.
6. The golfer selects camera view, handedness, and club.
7. SwingLab analyzes only the selected range and shows progress.
8. The review screen plays the swing with a body overlay and event markers.
9. Selecting a finding seeks to and freezes its evidence frame.
10. The comparison screen aligns that phase with one of the golfer's own saved
   "Best Swing" clips or a locally imported private reference. Private imports
   remain visibly unverified. The same boundary can accept verified catalog
   footage later.
11. The completed analysis remains in the local library.

## Required screens

- Library: previous swings, status, import action, and confirmed deletion.
- Import: Photos picker progress, automatic multi-swing discovery, detected
  clip selection, cancellation, manual fallback, and actionable errors.
- Trim: video preview, filmstrip, playhead, draggable range, context fields.
- Processing: cancellable progress for decode, pose, events, and coaching.
- Review: video, pose overlay, event scrubber, score, findings, metrics.
- Finding cards: evidence frame, measurement, hypothesis, and confidence.
- Compare: vertically stacked, phase-synchronized user and reference frames.
- Settings: privacy explanation, methodology, and version. Per-swing deletion
  is available in the Library.

## Analysis contract

Every finding contains:

- a stable identifier and short title;
- an evidence timestamp and swing event;
- the measured observation and units;
- a coaching hypothesis that does not overstate the camera evidence;
- confidence and severity;
- the body points and thresholds used;
- the camera views for which the finding is valid.

The first model supports projected torso inclination, shoulder and hip lines,
knee and elbow geometry, normalized head and pelvis movement, hand path relative
to the torso, phase timing, and repeatability. It may label loss of posture,
hands moving inside, or an over-the-top pattern only when the camera view and
pose evidence support that language.

SwingLab does not claim clubface angle, attack angle, dynamic loft, ball flight,
pressure, exact club path, or a reconstructed second camera view from a single
ordinary phone video.

## Reference comparison

Reference matching uses view, handedness, club, and normalized swing phase.
The app preserves the original user and reference frames. It does not warp a
golfer into a fake view.

Only footage with explicit distribution rights can ship in the application.
The current interaction supports the local Best Swing feature and private
user-imported references. Private imports are stored locally, labeled
unverified, and never treated as distribution-ready. Future distributed
reference media must have a source, license, attribution, allowed-use record,
and an internally verified rights status.

## Privacy

- PhotosPicker grants access only to the selected item.
- Videos, thumbnails, dense pose tracks, and analyses stay in app storage.
- No account is required for the first TestFlight build.
- No analytics or advertising SDK is included.
- Deleting a swing removes its database record and owned files.
- Any future network upload must be a separate, explicit opt-in feature.

## Acceptance status

- Complete: 63 native tests cover trim invariants, automatic multi-swing
  discovery, noise and duplicate rejection, geometry, event ordering, scoring,
  confidence, critique thresholds, persistence, and media ownership.
- Complete: the real Photos picker, import, trim, clip-position, and analysis
  entry flow were visually checked in the simulator with the supplied videos.
- Complete: simulator and generic-device Release builds pass, and a signed
  development archive validates against Apple's certificate chain.
- Pending: run Vision pose extraction with a supplied video on a physical
  iPhone; the installed simulator runtime lacks its body-pose model weights.
- Pending: visually verify the complete saved-review and comparison journey on
  a physical iPhone.
- Complete: an Apple development team and managed signing profile are selected
  in the local Xcode project; no signing credential is committed.
- Pending: enable Developer Mode on the paired iPhone, validate the full flow on
  that device, choose the shipping name, upload the archive, wait for processing,
  and install through TestFlight.

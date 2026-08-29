# Golf Swing Analyzer

A local-first command-line tool that finds complete swings in ordinary phone
video, measures body pose at key events, and creates an evidence-linked HTML
report with annotated freeze frames.

The first version is deliberately conservative. It measures what a single
camera can support and labels every angle as a 2D projection. It does not invent
club or ball data when the video cannot provide it.

## Native iPhone app: SwingLab

The repository now also contains a native SwiftUI app in [`ios/`](ios/). It is
an original, local-first product for iOS 17 and newer. The current app can:

- choose one video through Apple's limited Photos picker;
- copy only that video into private app storage;
- move and trim a frame-snapped swing window;
- collect camera view, handedness, and club context;
- extract 2D body pose on-device with Apple Vision;
- identify address, top, impact, and finish from the selected motion;
- calculate tempo, posture, joint, head, pelvis, and projected hand-path checks;
- create a transparent 0–100 score with confidence-gated coaching notes;
- scrub an annotated review timeline and step frame by frame;
- preserve completed reviews in a local SwiftData history;
- delete a saved swing and its uniquely owned local media;
- phase-match two saved swings in a synchronized Best Swing comparison.

The app has no account, backend, analytics SDK, or CloudKit sync. User video and
analysis stay on the iPhone. A reference catalog can support licensed coach or
professional footage later, but no third-party golfer footage ships in this
repository.

Generate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate --spec ios/project.yml
open ios/SwingLab.xcodeproj
```

Apple's simulator runtime can omit the model weights required by
`VNDetectHumanBodyPoseRequest`, so final pose validation must run on a physical
iPhone. The simulator still supports deterministic, explicitly labeled UI QA;
see [`ios/README.md`](ios/README.md).

## What it produces

For each detected swing:

- address, top, impact, and finish freeze frames;
- body skeletons, reference lines, and projected joint angles;
- backswing and downswing timing;
- normalized head and hip movement;
- stance, knee, elbow, torso, shoulder-line, and hip-line measurements;
- evidence-linked coaching hypotheses with confidence labels;
- raw image and model-estimated world pose tracks in a compressed NumPy file;
- one self-contained HTML report and one JSON manifest.

Raw video, downloaded model weights, and generated reports are ignored by Git.
This prevents accidental publication of personal media and avoids GitHub's
normal 100 MB per-file limit.

## Quick start

Requirements:

- macOS or Linux;
- Python 3.10–3.12 (3.12 recommended);
- [FFmpeg](https://ffmpeg.org/), including `ffprobe`.

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install -e '.[dev]'

golf-swing probe input_media
golf-swing analyze input_media --view down-the-line --handedness right
```

The first analysis run downloads the MediaPipe Pose Landmarker Full model to
`~/.cache/golf-swing-analyzer`. To avoid a runtime download, supply an existing
model:

```bash
golf-swing analyze video.mov --model /path/to/pose_landmarker.task
```

The command prints the path to `output/index.html`. Open that file in a browser.

### Apple Silicon note

The project pins MediaPipe `0.10.20`. Newer wheels tested in August 2026 crashed
while creating the Pose Landmarker graph on the current Apple Silicon/macOS
runtime. Keep the pin unless a newer release passes an end-to-end video run.

### Manual impact correction

At 30 fps, impact often falls between frames. The analyzer fuses the golfer's
pose sequence with a short audio transient. You can replace the inferred impact
times for one video:

```bash
golf-swing analyze video.mov --impact 12.345 --impact 28.901
```

## Measurement boundary

Useful from a fixed single camera:

- event sequence and tempo;
- visible body geometry and projected joint angles;
- normalized image-plane head and hip movement;
- setup and swing-to-swing repeatability.

Not defensible from an uncalibrated 30 fps single-camera video:

- clubface angle, club path, attack angle, or dynamic loft;
- clubhead speed or ball flight;
- pressure or weight shift;
- true 3D torso, pelvis, or joint angles;
- a real view from another camera angle.

The reports call observations "coaching hypotheses." Confirm them with strike
location, ball flight, and a qualified instructor before changing the swing.

## Why this stack

The implementation uses:

- [MediaPipe Pose Landmarker](https://developers.google.com/edge/mediapipe/solutions/vision/pose_landmarker/python)
  for 33 body landmarks in video mode;
- [FFmpeg](https://ffmpeg.org/ffmpeg.html) for rotation-aware phone-video
  decoding, audio extraction, and exact source-frame export;
- [OpenCV](https://docs.opencv.org/4.x/) and NumPy for drawing and measurements.

Other current projects informed the design but are not core dependencies:

- [Sports2D](https://github.com/davidpagnon/Sports2D) is a strong reference for
  pose-derived sports angles and explicitly warns about out-of-plane movement.
- [GolfDB/SwingNet](https://github.com/wmcnally/golfdb) defines eight useful
  golf events, but its model expects one trimmed swing and uses a noncommercial
  data/license path.
- [GolfPose](https://github.com/MingHanLee/GolfPose) adds golfer and club
  keypoints, but its dataset/checkpoint access and legacy model stack make it a
  phase-two option.
- [RTMLib](https://github.com/Tau-J/rtmlib) is a practical optional pose
  cross-check through ONNX Runtime.

According to the current MediaPipe package privacy notice, image/video inputs
are processed on the device and are not sent to Google, but MediaPipe Tasks may
send API performance and utilization metrics. See the
[MediaPipe package page](https://pypi.org/project/mediapipe/) for the current
notice. After the model and packages are present, this project's own code makes
no network calls during analysis.

## Current roadmap

1. Validate Vision analysis and performance on a physical iPhone, then ship the
   first internal TestFlight build.
2. Add manual phase correction and an exported annotated slow-motion clip.
3. Add optional, confidence-gated clubhead point tracking.
4. Add rights-cleared instructor or professional reference footage.
5. Support synchronized face-on and down-the-line videos for calibrated 3D
   work, rather than fabricating another view from one camera.

## Development

```bash
pytest
ruff check .
```

The project is MIT licensed. Model and dataset licenses remain their own.

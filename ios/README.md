# SwingLab for iOS

SwingLab is a native SwiftUI app for selecting a golf swing video, trimming the swing, running local pose analysis, and reviewing frame-specific feedback. The visual system is original: dark charcoal surfaces, warm cream type, and a coral analysis accent.

`SwingLab` is a working development name. Multiple golf apps already use that
name in the App Store, so choose a distinct product name before creating the
App Store Connect record. The code and bundle identifier can be renamed before
the first upload.

## Requirements

- macOS with Xcode 16 or newer
- iOS 17 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Generate and run

```sh
cd ios
xcodegen generate
open SwingLab.xcodeproj
```

Automatic signing is enabled, but the Apple team identifier is intentionally not committed. Select your development team for the `SwingLab` target in Xcode so that Xcode sets `DEVELOPMENT_TEAM` locally. Then select an iPhone simulator or connected iPhone and run the `SwingLab` scheme. The bundle identifier is `com.peterargany.SwingLab`.

`project.yml` is the source of truth. Do not hand-edit the generated Xcode project.

## Architecture

- `App` contains the SwiftUI entry point and three-tab shell.
- `Design` contains shared colors, typography, cards, pills, score treatment, and buttons.
- `Persistence` contains the local-only SwiftData schema and repository.
- `Core` is reserved for media, pose, and analysis services.
- `Features` is reserved for import/trim, analysis review, library detail, and settings flows.

`SwingSession` is the durable integration boundary. It stores the selected video's relative local path, capture context, trim range, analysis lifecycle, score, encoded analysis result, and optional reference-swing identifier. Feature code can encode any `Codable` result with `setAnalysis(_:)` and recover it with `analysis(as:)`.

The SwiftData configuration explicitly disables CloudKit. Videos should be copied into the app sandbox and referenced by relative path; do not store external photo-library URLs.

## Photo privacy

Video import uses SwiftUI `PhotosPicker`, which gives the app access only to the item the golfer selects. Apple does not require `NSPhotoLibraryUsageDescription` for this limited picker flow, so the generated Info.plist intentionally has no full-library permission key. Add a photo-library usage description only if a future feature directly reads the entire library through `PHPhotoLibrary`.

`PrivacyInfo.xcprivacy` declares no tracking, collected data, tracking domains, or required-reason API use. Review it before shipping any analytics, account, cloud, or SDK feature.

## TestFlight checklist

1. Choose a distinct shipping name and create its App Store Connect record.
2. Set the development team and confirm signing in Xcode.
3. Test Photos import and Vision analysis on a physical iPhone.
4. Run the `SwingLabTests` scheme tests.
5. Archive with the `SwingLab` scheme.
6. Validate the archive's privacy report, then upload it to App Store Connect.

## Simulator pose fixture

Apple's simulator runtime can omit the body-pose model weights used by
`VNDetectHumanBodyPoseRequest`. Device builds never use a replacement model.
For simulator-only review and comparison UI QA, launch a Debug build with:

```bash
SIMCTL_CHILD_SWINGLAB_USE_SIMULATOR_POSE_FIXTURE=1 \
  xcrun simctl launch <device-id> com.peterargany.SwingLab
```

Fixture results are capped at 50% confidence and state that their pose evidence
is synthetic. The code is excluded from physical-device and TestFlight builds.

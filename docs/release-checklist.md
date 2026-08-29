# iOS release and TestFlight checklist

This checklist keeps signing credentials and developer-team identifiers out of
the public repository. `ios/project.yml` remains the Xcode project source of
truth. `ios/ExportOptions.plist` creates a local App Store package; it does not
upload one.

## 1. Confirm the shipping identity

- App Store and display name: `Replay Caddie`
- Bundle identifier: `com.peterargany.replaycaddie`
- Subtitle: `Golf Swing Video Coach`
- Tagline: `See the frame. Fix the swing.`
- Keep the internal Xcode project, target, module, and product name `SwingLab`.
- Confirm that all visible app copy uses the shipping name.
- Keep internal persistence names stable unless a data migration is planned.
- Generate the Xcode project with `xcodegen generate` from `ios/`.
- Select the Apple development team locally in Xcode or pass it as a build
  setting. Do not commit local signing changes.

## 2. Prepare App Store Connect

- Confirm that the Apple Developer Program membership is active.
- Have the Account Holder accept the current agreements.
- Create the explicit App ID and App Store Connect app record with the final
  bundle identifier.
- Complete the app privacy response, content-rights response, age rating,
  category, availability, and TestFlight contact information.
- Publish the privacy and support pages from `docs/` with GitHub Pages.

## 3. Prepare the build

- Increment `CURRENT_PROJECT_VERSION` for every upload.
- Keep `MARKETING_VERSION` aligned with the App Store version.
- Confirm that `ITSAppUsesNonExemptEncryption` remains `NO` unless encryption
  behavior changes.
- Confirm that no private video, device report, signing file, or licensed asset
  without distribution rights is present in the target.

## 4. Verify

From the repository root:

```sh
.venv/bin/ruff check .
.venv/bin/python -m pytest -q
SIMULATOR_ID="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
xcodebuild \
  -project ios/SwingLab.xcodeproj \
  -scheme SwingLab \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  CODE_SIGNING_ALLOWED=NO \
  test
```

On a physical iPhone, verify Photos import, automatic discovery, manual trim,
analysis, evidence scrubbing, save/reopen, comparison, and deletion.

## 5. Archive and export

Only use `-allowProvisioningUpdates` after the final App ID and App Store record
exist. It can create or update signing assets in the developer account.

```sh
xcodebuild \
  -project ios/SwingLab.xcodeproj \
  -scheme SwingLab \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath .build/AppStore.xcarchive \
  DEVELOPMENT_TEAM='<your-team-id>' \
  -allowProvisioningUpdates \
  archive

xcodebuild \
  -exportArchive \
  -archivePath .build/AppStore.xcarchive \
  -exportPath .build/AppStoreExport \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates
```

Inspect the exported app's icon, Info.plist, privacy manifest, entitlements,
architectures, and dSYM before upload. The exported distribution app must not
contain `get-task-allow=true`.

## 6. Upload and test

- Upload the validated package with Xcode Organizer only after an explicit
  release decision.
- Wait for App Store Connect processing and resolve all warnings.
- Answer export-compliance questions if App Store Connect still requests them.
- Add the processed build to an internal TestFlight group first.
- For external testing, add the beta description, feedback email, review notes,
  and a rights-cleared test video, then submit the first build for beta review.
- Build opaque 6.9-inch screenshots before public App Store submission.

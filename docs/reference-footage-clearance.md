# Reference footage clearance

Replay Caddie may bundle a golfer's video only after both the recording rights
and the golfer's name-and-likeness rights are documented. An open-content label
by itself is not enough when the uploader's authority cannot be verified.

## Current candidate

The strongest technical candidate is the Wikimedia Commons file
[Suvichaya Vinijchaitham Golf Swing Slow Mo 2026](https://commons.wikimedia.org/wiki/File:Suvichaya_Vinijchaitham_Golf_Swing_Slow_Mo_2026.webm).
The original is a 1080-by-1920, 30 fps video with face-on and down-the-line iron
and driver sequences. Its inspected SHA-256 is
`7b748b86b794790bd079b629fb124b71e446d228aeabf12ddfe11b46a1406c44`.

Suvichaya's official LPGA profile establishes that she is a professional
golfer. The Commons file is marked as the uploader's own work under CC0, but
the uploader's identity and authority have not been independently verified.
The file is therefore **not distribution-ready** and must not be added to the
app target, screenshots, App Store listing, or public test data yet.

## Clearance required

Before changing the catalog entry to `verified`, retain a signed document that:

- identifies the recording by title and hash;
- identifies the copyright owner and confirms authority to grant the license;
- confirms the depicted golfer's consent to commercial use of their name,
  image, likeness, voice, and golf performance;
- permits editing, cropping, transcoding, still extraction, pose overlays,
  annotations, phase alignment, in-app distribution, TestFlight distribution,
  App Store distribution, and truthful screenshots of the feature;
- is worldwide, perpetual, non-exclusive, irrevocable, sublicensable to the
  technical services needed to distribute the app, and fully paid-up or states
  the agreed compensation;
- states the exact required credit and permitted golfer label; and
- disclaims any implied affiliation or endorsement.

If a representative signs, the document must state that the representative is
authorized to bind the copyright owner or golfer. Store the signed release
privately. Never commit signatures, addresses, private contact details, or
payment terms to this repository.

## Media preparation after clearance

Create separate face-on and down-the-line assets for each supported club. Then:

1. remove the audio track and all location/device metadata;
2. obscure visible third-party branding unless it is separately cleared;
3. retain the original file and hash in the private rights record;
4. analyze each clip with the same production pipeline used for user swings;
5. verify address, top, impact, and finish frame by frame;
6. populate the bundled-reference manifest with source, license, allowed-use,
   attribution, golfer, club, camera view, handedness, media, and analysis
   metadata; and
7. run the fail-closed catalog tests plus a physical-device comparison check.

Until these steps are complete, use a saved personal swing or a locally
imported private reference to test comparison behavior. Never describe a stock
performer or unverified private import as a professional golfer.

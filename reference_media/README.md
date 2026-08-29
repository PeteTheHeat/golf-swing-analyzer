# Replay Caddie reference media

The media in this directory is distributed separately from the Replay Caddie
application binary. The app downloads it over HTTPS and verifies its SHA-256
digest before playback. This keeps the Creative Commons media available
without App Store bundle DRM.

## Dirk Oosterveer historical iron swing

`dirk-oosterveer-1939-cc-by-sa-3.0-nl.mp4` is adapted from the exact Open
Beelden file preserved by Wikimedia Commons under the Creative Commons
Attribution-ShareAlike 3.0 Netherlands license.

- Work: “Dirk Oosterveer demonstreert staaltjes van golftechniek” (1939)
- Producer: Polygoon-Profilti
- Manager and attributed author: Nederlands Instituut voor Beeld en Geluid
- [Source record](https://commons.wikimedia.org/wiki/File:Dirk_Oosterveer_demonstreert_staaltjes_van_golftechniek_Weeknummer_39-16_-_Open_Beelden_-_30179.ogv)
- [Original archive record](https://www.openbeelden.nl/media/30179/Dirk_Oosterveer_demonstreert_staaltjes_van_golftechniek)
- [CC BY-SA 3.0 Netherlands license](https://creativecommons.org/licenses/by-sa/3.0/nl/deed.en)

Replay Caddie trimmed the source to 00:12.500–00:15.800, removed the audio,
transcoded the Theora video to H.264, added fast-start metadata, and removed
container metadata. The adapted clip remains licensed under CC BY-SA 3.0
Netherlands. Its exact provenance and hashes are recorded in
`dirk-oosterveer-1939.metadata.json`.

This is a historical, rear-oblique iron-swing reference. It is not a calibrated
modern driver benchmark. Dirk Oosterveer, his estate, Polygoon-Profilti,
Wikimedia Commons, and the Netherlands Institute for Sound and Vision do not
endorse Replay Caddie.

# Changelog

## Unreleased

- Rename the project to YouDash, with the descriptor “Native YouTube for Apple CarPlay.” Update canonical repository links, README branding, future app display names, and release-kit branding; retain existing runtime identifiers and historical asset filenames.

- YouMod settings: add Sehind Hemzani attribution with a GitHub profile link and the actual YouTube version (with the reported compatibility version distinguished), above the original YouMod version row.

- Fullscreen: route both native entry and exit guards to the active CarPlay window; retain weak display ownership while watch views are temporarily detached, preserving split-layout geometry through transitions. Native transition guards remain intact. Module compilation verified; device visual confirmation pending.
- CarPlay seek bar: a minimum 6-point visible track, larger scrubber thumb, and 44-point touch region, adjusted for canvas scaling. Phone styling and playback settings are preserved.

## 0.1.0 — Native CarPlay preview

- Native controller handoff between phone and CarPlay.
- Responsive Home grid and small-screen density scaling.
- Split video/details and recommendation/queue layouts on landscape displays.
- English/Arabic on-screen keyboard with native field integration.
- Header safe-area, scroll-collapse, search viewport, and mini-player adjustments.
- Reversible reported-version compatibility override with actual-version metadata preserved.
- Standalone source distribution, credited YouMod snapshot, unsigned packaging, and privacy auditing.

Experimental preview. Compatibility limitations are documented rather than implied to be solved universally.

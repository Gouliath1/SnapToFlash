# UX Task Plan

Based on the UX requirements captured in `MVP_SPEC.md` ("UX v2 requirements").

## Requirement Checklist

- [x] **1) Bottom thumb-friendly actions**
  - Implemented pinned bottom bar with flow order: `Load` -> `Gen. Cards` -> `Validate` -> `Export`.
  - Buttons are icon-first and disabled when not valid for the current step.

- [x] **2) Sample pages for testing only**
  - Sample loading is available only in `#if DEBUG` path inside the `Load` chooser.

- [ ] **3) Image thumbnails open fullscreen on tap**
  - Thumbnails are shown, but fullscreen inspect/zoom on tap is not implemented yet.

- [x] **4) Compress images before backend/LLM**
  - Images are preprocessed before upload via the existing `ImagePreprocessor` pipeline.

- [ ] **5) More compact cards + group by image**
  - Compactness improved and image name shown per card.
  - Strong visual grouping/divider by image source is still pending.

- [ ] **6) Editable card text + AI translation suggestion after edit**
  - Not implemented yet.

- [ ] **7) Review bulk actions (`Accept all pending`, `Clear pending`)**
  - Moved into bottom `Validate` flow, but UX wording/interaction still needs final review.

- [ ] **8) Branding header improvements**
  - Pending: title should be `Snap To Flash` + subtitle + improved visual header/icon.

- [ ] **9) App icon**
  - Pending.

- [ ] **10) App description copy**
  - Pending.

## Additional Completed UX Work

- [x] `Export` now provides both choices: `Anki` and `CSV`.
- [x] `Anki` export option remains visible and disabled when Anki is unavailable.
- [x] Bottom scroll content padding adjusted so final card is not hidden behind action bar.
- [x] Per-card source image label and card counters added.
- [x] Card ordering preserves image order + reading-order best effort.
- [x] Pull-down gesture on main screen refreshes backend connectivity status (no app restart needed).

## Next Implementation Order

1. Implement fullscreen image inspection (tap thumbnail -> fullscreen, with dismiss and zoom).
2. Add clear card grouping/dividers by source image.
3. Add editable card fields and "suggest translation" action.
4. Finalize validation flow wording/interaction for bulk actions.
5. Apply branding pass (title/subtitle/header visuals), then app icon and app description copy.

## Delivery & Integration Tasks

- [ ] **1) Run app on physical iPhone for testing**
  - Set up signing/provisioning and install to device.
  - Verify camera, photo import, and export flows on real hardware.

- [ ] **2) Validate CSV generation end-to-end**
  - CSV export now creates and shares an actual `.csv` file URL.
  - Confirm CSV export action creates expected rows/columns.
  - Spot-check generated CSV in a spreadsheet and in Anki import preview.

- [ ] **3) Connect and validate Anki integration**
  - Enable AnkiConnect on desktop and verify connectivity.
  - Test `Export -> Anki` with success and unavailable/error states.

- [ ] **4) Decide deck save strategy**
  - Define behavior: create a new deck per source set, append to existing deck, or prompt user each export.
  - Document default rule and UX for overriding it.

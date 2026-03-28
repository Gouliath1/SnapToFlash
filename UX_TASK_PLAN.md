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

- [x] **11) Dark mode readability + theme support**
  - Implemented adaptive light/dark styles for app background, section cards, card rows, and bottom action buttons.
  - Primary/secondary text contrast now remains legible in both light and dark appearances.

- [ ] **12) OCR accuracy + confidence calibration**
  - Improve extraction reliability on difficult photos (angle, blur, low contrast, mixed handwriting/print).
  - Replace or calibrate displayed OCR confidence so the percentage matches observed quality.
  - Execution document: `OCR_VISION_IMPLEMENTATION_PLAN.md`.

- [ ] **13) Native in-app flashcards (no Anki dependency)**
  - Add local deck/card storage and in-app spaced repetition study flow.
  - Keep CSV interoperability while making study fully usable without desktop/mobile Anki.
  - Execution document: `IN_APP_FLASHCARDS_SPEC.md`.

## Additional Completed UX Work

- [x] `Export` now provides both choices: `Anki` and `CSV`.
- [x] `Anki Import File` export option remains available without AnkiConnect/desktop reachability.
- [x] Bottom scroll content padding adjusted so final card is not hidden behind action bar.
- [x] Per-card source image label and card counters added.
- [x] Card ordering preserves image order + reading-order best effort.
- [x] Pull-down gesture on main screen refreshes backend connectivity status (no app restart needed).
- [x] Added adaptive dark-mode styling for core surfaces and controls to prevent unreadable text.

## Next Implementation Order

1. Improve OCR extraction quality and calibrate confidence scoring against real sample pages (execute `OCR_VISION_IMPLEMENTATION_PLAN.md`).
2. Implement native in-app flashcards and study engine (execute `IN_APP_FLASHCARDS_SPEC.md`).
3. Implement fullscreen image inspection (tap thumbnail -> fullscreen, with dismiss and zoom).
4. Add clear card grouping/dividers by source image.
5. Add editable card fields and "suggest translation" action.
6. Finalize validation flow wording/interaction for bulk actions.
7. Apply branding pass (title/subtitle/header visuals), then app icon and app description copy.

## Delivery & Integration Tasks

- [ ] **1) Run app on physical iPhone for testing**
  - Set up signing/provisioning and install to device.
  - Verify camera, photo import, and export flows on real hardware.

- [ ] **2) Validate CSV generation end-to-end**
  - CSV export now creates and shares an actual `.csv` file URL.
  - Confirm CSV export action creates expected rows/columns.
  - Spot-check generated CSV in a spreadsheet and in Anki import preview.

- [ ] **3) Validate Anki file import flow**
  - Generate `Anki Import File` export and verify import in Anki Desktop.
  - Verify import behavior on AnkiMobile (open/share file into app).
  - Confirm deck naming and field mapping during import.

- [ ] **4) Decide deck save strategy**
  - Define behavior: create a new deck per source set, append to existing deck, or prompt user each export.
  - Document default rule and UX for overriding it.

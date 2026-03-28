# Apple Vision OCR Implementation Plan

## Goal
Improve OCR accuracy on real textbook/notebook photos and make the displayed OCR confidence trustworthy.

## Why this is needed
Current `OCR xx%` is model-estimated (`conf_ocr`) from backend LLM output, not a calibrated OCR engine score. This can report high confidence on bad reads.

## Scope
This plan covers OCR extraction, confidence calibration, backend contract updates, and rollout. It does not change deck/export features.

## Step-by-step execution

### 1. Establish baseline and test set
1. Build a fixed benchmark set of 50-100 real photos (clean, blurry, angled, low light, mixed handwriting/print).
2. Record expected text snippets and expected card outputs for each sample.
3. Add a repeatable evaluation command that reports:
   - line-level OCR error (CER/WER),
   - card extraction precision/recall,
   - false-high-confidence count (cases where OCR score >= 0.85 but output is wrong).
4. Freeze this set as the acceptance benchmark for all OCR changes.

### 2. Add on-device Apple Vision OCR service
1. Add `VisionOCRService` in iOS (`VNRecognizeTextRequest`).
2. Configure:
   - `recognitionLevel = .accurate`
   - `recognitionLanguages = ["ja-JP"]`
   - `usesLanguageCorrection = true`
3. Return structured OCR payload per line/token:
   - text,
   - bounding box,
   - confidence,
   - source image id.
4. Add unit tests for payload shape and confidence bounds.

### 3. Upgrade image preprocessing for OCR
1. Keep current resize/compression, then add:
   - orientation normalization,
   - perspective correction (when page edges can be detected),
   - contrast enhancement and denoise.
2. Generate two OCR candidates (natural + enhanced) and choose best by aggregate OCR confidence and script sanity checks.
3. Keep upload image quality high enough for LLM context (do not over-compress text regions).

### 4. Update backend contract and prompting
1. Extend `/analyze-page` to accept optional client OCR payload.
2. In the prompt, instruct model to use OCR payload as primary text evidence and only infer missing parts from image context.
3. Preserve backward compatibility: if OCR payload is absent, run existing path.

### 5. Replace confidence logic with calibrated scoring
1. Compute deterministic `conf_ocr` from Vision confidences, weighted by:
   - token confidence,
   - coverage of expected text zones,
   - penalties for suspicious tokens (garbled characters, script mismatches).
2. Keep `conf_match` separate for notebook-to-book alignment quality.
3. Mark `needs_review = true` when:
   - `conf_ocr` below threshold,
   - strong OCR/translation mismatch,
   - ambiguity warnings present.
4. Temporarily label UI value as estimate until benchmark calibration target is met.

### 6. Add quality safeguards
1. Add script and language sanity checks (kana/kanji balance, obvious noise tokens).
2. Add warning reasons per card (low OCR confidence, weak page match, ambiguous mapping).
3. Reject impossible values and clamp all confidence outputs to `[0, 1]`.

### 7. Update UI to reflect confidence honestly
1. Replace raw `OCR xx%` display with calibrated OCR confidence.
2. Show short diagnostic hint on low-confidence cards (for example: "Retake photo: blur/angle detected").
3. Keep validation-first flow for low-confidence cards.

### 8. Roll out safely
1. Add feature flag for Vision OCR path.
2. Enable in debug builds first, then staged release.
3. Compare benchmark and production telemetry before full rollout.

## Definition of done
1. OCR benchmark improves by agreed target (set after baseline capture).
2. False-high-confidence rate drops significantly versus baseline.
3. At least 90% of benchmark samples with calibrated OCR >= 0.85 are subjectively readable/correct.
4. No regression in card export flow or app responsiveness on iPhone 15 Pro.

## Initial file targets
1. `/Users/goul/Development/SnapToFlash/SnapToFlash/Services/ImagePreprocessor.swift`
2. `/Users/goul/Development/SnapToFlash/SnapToFlash/ViewModels/AppViewModel.swift`
3. `/Users/goul/Development/SnapToFlash/backend/main.py`
4. `/Users/goul/Development/SnapToFlash/SnapToFlash/Views/ContentView.swift`

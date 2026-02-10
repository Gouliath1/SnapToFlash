# MVP Specification: Annotated Japanese Textbook → Anki Flashcards

## Goal and non-goals
**Goal:** Build an extremely simple MVP that turns one or more photos/scans of Japanese textbook pages with user annotations into Anki-ready flashcards, then sends them to Anki with minimal friction (2–3 taps). The system must detect user annotations (any mark type/color), infer the referenced printed Japanese text when possible, and generate flashcards with corrected meanings using surrounding sentence context.

**Non-goals:**
- No complex, classical CV pipelines (use GenAI vision-first extraction for MVP).
- No multi-page document management, account system, or advanced study analytics.
- No advanced editor workflow (inline card edits are allowed, but no full rich-text editing UI).

## User flow (minimal screens and actions)
1. **Import/Scan**: User takes one or more photos or imports multiple images of Japanese textbook pages with annotations.
2. **Generate**: App uploads images → receives flashcards.
3. **Send to Anki**: Primary action. User chooses new card set or existing one. If AnkiConnect not reachable, auto-offer CSV export.

Screens (minimal):
- **Screen 1: Capture/Import** (single CTA)
- **Screen 2: Results** (list of cards + “Send to Anki” primary CTA + optional edit/delete + “Open Anki” button)

## What counts as annotation
Any user mark of any color or medium, including but not limited to:
- Handwriting (notes, translations, glosses)
- Underlines/overlines
- Highlights
- Circles/boxes
- Arrows
- Margin notes
- Strike-throughs

## Flashcard model
Fields (Anki note fields):
- **ExpressionOrWord** (required)
- **Reading** (required if available; kana)
- **Meaning** (required; corrected meaning based on context)
- **Example** (optional)

**Dedupe rules:**
- Deduplicate by normalized **ExpressionOrWord + Reading** (kana normalization + whitespace trim).
- If same ExpressionOrWord appears with different correct senses, keep both only if context differs and meanings are distinct.

## GenAI pipeline (one call per page)
- **Input:** One or more images (preprocessed), analyzed as one call per page image.
- **Output:** Strict JSON payload (schema below) containing detected annotations, inferred target text, and generated Anki notes.
- **Guardrails:**
  - Always include confidence (0..1) and needs_review.
  - Max **40 cards per page** to prevent runaway output.
  - Flag low-confidence items for review; only prompt user edits for these.
  - Model must correct wrong user translations and choose the right meaning using surrounding sentence context.

## API / infra options
**Option A: direct client-to-OpenAI**
- Pros: fast, minimal backend.
- Cons: key exposure risk, harder to enforce rate limiting and caching.

**Option B: thin backend proxy (recommended)**
- Hides API key.
- Caching by image hash to reduce cost.
- Rate limiting and request logs.

**Endpoint**
- `POST /analyze-page`
- Body: image (binary or base64), metadata (optional page id)
- Response: JSON payload (schema below)
- For multiple screenshots, call once per image and merge results client-side before sending to Anki.

## Output JSON contract
- Model returns **strict JSON only** (no prose).
- Always include `anki_notes` array (may be empty).
- Always include `confidence` (0..1) and `needs_review` (boolean).
- Always include `annotations` array describing detected marks and inferred targets.
- Include `warnings` array for low-confidence or ambiguous cases.

Example JSON:
```json
{
  "page_id": "page_12_photo_1",
  "confidence": 0.72,
  "needs_review": true,
  "warnings": [
    "Ambiguous reference for circled text near paragraph 2.",
    "Low confidence reading for 手続き."
  ],
  "annotations": [
    {
      "type": "underline",
      "color": "yellow",
      "bounding_box": [120, 340, 520, 380],
      "annotation_text": null,
      "target_text": "手続き",
      "target_context": "この手続きは明日までに必要です。",
      "confidence": 0.64
    },
    {
      "type": "margin_note",
      "color": "blue",
      "bounding_box": [30, 210, 140, 280],
      "annotation_text": "= application",
      "target_text": "申請",
      "target_context": "申請書を提出してください。",
      "confidence": 0.79
    }
  ],
  "anki_notes": [
    {
      "ExpressionOrWord": "申請",
      "Reading": "しんせい",
      "Meaning": "application; request (formal)",
      "Example": "申請書を提出してください。",
      "confidence": 0.81,
      "needs_review": false
    },
    {
      "ExpressionOrWord": "手続き",
      "Reading": "てつづき",
      "Meaning": "procedure; formal process",
      "Example": "この手続きは明日までに必要です。",
      "confidence": 0.62,
      "needs_review": true
    }
  ]
}
```

## Vision prompt (notebook + highlighted book pages)
Use this prompt verbatim for the multimodal call that extracts flashcards from mixed notebook + textbook photos and prepares them for user validation.

```
You are an assistant that extracts study flashcards from photos and prepares them for user validation before Anki export.

Inputs:
- One or more photos that may show: (a) a printed book page with highlights/underlines, (b) my handwritten notebook with vocab lines in this pattern: kanji (if any) → hiragana → translation/meaning. Phrases may also appear with translations.
Goal: propose flashcards that map what I wrote to the closest corresponding word/phrase on the book page. If no translation exists, use the highlighted book text itself.

Rules:
1) OCR:
   - Transcribe all handwritten lines; keep reading order (top→bottom, left→right).
2) Identify vocab units:
   - Notebook: each contiguous line-set = one entry: [kanji (optional), hiragana, translation/comment]. If kanji missing, use hiragana as headword.
   - Book: find highlighted/underlined text; each highlight is a separate candidate.
3) Matching:
   - For each notebook entry, search book text for the best match (ignore inflection; allow partial). If none, leave book_match empty.
4) Translation cross-check:
   - If a notebook translation/comment exists, generate the model’s own translation.
   - If model translation differs materially from the handwritten one, include both and mark needs_review=true; otherwise keep only the handwritten translation.
5) Card building:
   - Prefer notebook translation when present; if none and a highlighted book phrase exists, use the highlight as front and leave back empty.
   - Preserve phrases; do not split into single words.
   - Keep script distinctions: store kanji and kana separately when both exist.
6) Quality:
   - Include confidence 0–1 for OCR and for the match.
   - Do not invent translations; leave back empty if unknown.
7) Output only JSON.

Output JSON array:
[
  {
    "front": "kanji or highlighted word/phrase (or hiragana if no kanji)",
    "back": "translation/meaning (may be empty)",
    "hiragana": "reading if available",
    "kanji": "kanji form if available, else empty",
    "source": "notebook|book",
    "book_match": "matched book phrase or ''",
    "hand_translation": "handwritten translation/comment or ''",
    "ai_translation": "model translation or ''",
    "needs_review": true/false,   // true when hand vs AI differ meaningfully
    "conf_ocr": 0.0-1.0,
    "conf_match": 0.0-1.0,
    "notes": "ambiguity, alternatives, or why needs_review=true"
  }
]

Post-processing expectations (handled downstream):
- Show each card for user validation; allow bulk accept. Only validated cards are exported to Anki.
- If needs_review=false and no differences, no extra confirmation is required beyond the normal validation step.
- If multiple photos are given, combine results and deduplicate exact duplicates.
```

**Additional requirements for the flow**
- During review, if the handwritten translation/comment and the model translation differ, surface both and let the user choose; otherwise skip the diff step to keep flow fast.
- The Anki deck is created only after user validation (per-card or bulk accept). Unapproved cards are excluded from the export.

## Image preprocessing recommendations
- Resize to max long edge 1600–2048 px.
- Compress to JPEG quality ~0.7–0.85.
- Auto-crop to page bounds if reliably detectable.
- Preserve color for annotation detection (do not grayscale).

## Anki integration requirements
**Preferred: AnkiConnect (Anki Desktop plugin)**
- Detect reachable endpoint (default `http://127.0.0.1:8765`).
- If reachable, auto-create deck/model if missing.
- Add notes using fields: ExpressionOrWord, Reading, Meaning, Example.
- Allow user to attach new words to a **new** card set or an **existing** one.
- Provide an **“Open Anki”** button after send to make review immediate.

**Fallback: CSV export via share sheet**
- Provide CSV with columns:

```csv
ExpressionOrWord,Reading,Meaning,Example
```

**UX rule:** Primary button is **“Send to Anki”**. If AnkiConnect not reachable, automatically offer CSV export.

## Error handling and privacy defaults
- If model call fails, show retry and allow manual export of the original image.
- If no annotations detected, show “No marks found” with a retry option.
- Default to no data retention; cache by image hash only if user consents or in on-device cache.
- Log only minimal metadata (timestamp, success/failure) in proxy option.

## UX v2 requirements (next iteration)
These items are approved for the next implementation pass.

1. **Bottom pinned action bar (thumb-friendly flow)**
   - Keep the primary flow actions always visible and pinned at the bottom.
   - Button order: `Load image(s)` -> `Generate cards` -> `Validate cards` -> `Send to Anki`.
   - `Load image(s)` opens a source chooser: import from library, load sample pages, or take picture.
   - `Validate cards` surfaces bulk validation actions (accept all pending, clear pending).
   - Use clear icons + short labels and a 1-2 word description per action.
   - Buttons must visually show disabled state when unavailable for the current step.
   - Rationale: bottom placement is preferred for one-hand/thumb reach on phones.

2. **Sample pages handling**
   - Bundled sample pages remain available for test/debug only.
   - Do not expose sample-loading controls in normal production UX.
   - If needed, keep sample controls behind debug-only gates.

3. **Image strip + fullscreen inspection**
   - Show selected/captured images in a horizontal strip above results.
   - Tapping an image opens fullscreen preview (zoom/pan and dismiss).

4. **Pre-upload compression (required)**
   - Compress images before sending to backend/LLM.
   - Keep quality high enough for handwriting/OCR while reducing payload size.
   - Default target: max long edge 1600-2048 px and JPEG quality about 0.7-0.85.

5. **Compact card layout + image grouping**
   - Make card rows denser (less vertical whitespace, fewer repeated lines).
   - Show image name near top of card metadata.
   - Add a strong visual divider between groups of cards from different images.

6. **Card text editing + re-translation assist**
   - Card text fields must be editable before final export.
   - After user edits front/back text, offer an AI-assisted "improve translation" suggestion.
   - User remains final authority on accepted text.

7. **Pending actions UX review**
   - Bulk pending actions are accessed from the bottom `Validate cards` action.
   - Keep behavior explicit: accept all pending vs clear pending.
   - Continue refining wording if users find the distinction ambiguous.

8. **Branding in header**
   - App title should be `Snap To Flash` (with spaces).
   - Add subtitle under/near title.
   - Improve top branding with a cleaner visual treatment and icon.

9. **App icon**
   - Create a clearer, recognizable app icon that communicates photo -> flashcard intent.
   - Provide light/dark-safe contrast and legibility at small sizes.

10. **App description copy**
   - Create app store/product description copy (short + long variants).
   - Messaging should highlight: photo capture/import, AI extraction, review, and Anki export.

### UX acceptance checks for v2
- Core action buttons remain visible at the bottom regardless of list length.
- User can complete capture/import -> generate -> review -> send without scrolling to find actions.
- User can open `Load image(s)` and choose import/sample/camera from one place.
- Every card clearly indicates originating image(s).
- Card list is visually compact and still readable.
- Edited cards can request AI translation suggestions before final approval/export.

## Acceptance criteria (end-to-end)
- User can go from photo → Anki add in **2–3 taps**.
- User can ingest multiple screenshots and generate a single combined set of new words.
- User can attach new words to a **new** card set or an **existing** one.
- Annotations of any type/color are detected and linked to printed Japanese text when possible.
- Output JSON strictly matches contract and caps at **≤ 40 cards per page**.
- Low-confidence items are flagged and require user confirmation/edit before export.
- AnkiConnect flow works when reachable; otherwise CSV export is offered automatically.
- Dedupe prevents repeated cards for the same ExpressionOrWord+Reading unless meanings differ by context.

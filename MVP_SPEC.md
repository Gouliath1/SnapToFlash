# MVP Specification: Annotated Japanese Textbook → Anki Flashcards

## Goal and non-goals
**Goal:** Build an extremely simple MVP that turns one or more photos/scans of Japanese textbook pages with user annotations into Anki-ready flashcards, then sends them to Anki with minimal friction (2–3 taps). The system must detect user annotations (any mark type/color), infer the referenced printed Japanese text when possible, and generate flashcards with corrected meanings using surrounding sentence context.

**Non-goals:**
- No complex, classical CV pipelines (use GenAI vision-first extraction for MVP).
- No multi-page document management, account system, or advanced study analytics.
- No deep editing UI beyond confirm/edit/delete for low-confidence cards.

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

## Acceptance criteria (end-to-end)
- User can go from photo → Anki add in **2–3 taps**.
- User can ingest multiple screenshots and generate a single combined set of new words.
- User can attach new words to a **new** card set or an **existing** one.
- Annotations of any type/color are detected and linked to printed Japanese text when possible.
- Output JSON strictly matches contract and caps at **≤ 40 cards per page**.
- Low-confidence items are flagged and require user confirmation/edit before export.
- AnkiConnect flow works when reachable; otherwise CSV export is offered automatically.
- Dedupe prevents repeated cards for the same ExpressionOrWord+Reading unless meanings differ by context.

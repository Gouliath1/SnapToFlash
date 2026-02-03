# Solution Design

## Scope note
This document focuses on implementation decisions and responsibilities. UX flow and product rules are defined in MVP_SPEC.md.

## Client responsibilities
- Image preprocessing: resize long edge 1600–2048 px, JPEG quality ~0.7–0.85, preserve color.
- Hash images for caching and to skip re-uploads.
- Merge results across multiple screenshots into a single card set.
- Dedupe by ExpressionOrWord+Reading (normalized).
- Apply low-confidence review UI (confirm/edit/delete only when flagged).

## Backend responsibilities
- `POST /analyze-page` accepts image + optional page_id.
- Cache by image hash; return cached result if present.
- Forward request to OpenAI vision-capable model with strict JSON response format.
- Apply rate limiting and minimal logging (timestamp + success/failure only).

## Anki integration
- Detect AnkiConnect at `http://127.0.0.1:8765`.
- Ensure deck/model exists (create if missing).
- Add notes with fields: ExpressionOrWord, Reading, Meaning, Example.
- Fallback CSV export: `ExpressionOrWord,Reading,Meaning,Example`.

## Minimal error handling
- Model failure → retry option.
- No annotations found → “No marks found” + retry.
- AnkiConnect unreachable → auto-offer CSV export.

## Privacy defaults
- No retention by default.
- Cache by image hash only with user consent or on-device caching.

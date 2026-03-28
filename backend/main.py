from uuid import uuid4
from typing import Optional, List, Dict, Any
import base64
import os
import json
import re
import logging
import time

from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from openai import OpenAI, OpenAIError

app = FastAPI()

OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
logging.basicConfig(level=LOG_LEVEL, format="[%(asctime)s] %(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("snaptoflash.backend")
logger.info(
    "starting | model=%s | api_key_prefix=%s",
    OPENAI_MODEL,
    (OPENAI_API_KEY[:8] + "...") if OPENAI_API_KEY else "None",
)
REVIEW_COMBINED_THRESHOLD = 0.75


@app.middleware("http")
async def log_http_requests(request, call_next):
    request_id = uuid4().hex[:8]
    start = time.perf_counter()
    client_host = request.client.host if request.client else "unknown"
    content_length = request.headers.get("content-length", "unknown")

    logger.info(
        "http start | id=%s | method=%s | path=%s | client=%s | content_length=%s",
        request_id,
        request.method,
        request.url.path,
        client_host,
        content_length,
    )

    try:
        response = await call_next(request)
    except Exception as exc:  # noqa: BLE001
        elapsed_ms = (time.perf_counter() - start) * 1000
        logger.exception(
            "http error | id=%s | method=%s | path=%s | duration_ms=%.1f | error=%s",
            request_id,
            request.method,
            request.url.path,
            elapsed_ms,
            exc,
        )
        raise

    elapsed_ms = (time.perf_counter() - start) * 1000
    logger.info(
        "http done | id=%s | method=%s | path=%s | status=%s | duration_ms=%.1f",
        request_id,
        request.method,
        request.url.path,
        response.status_code,
        elapsed_ms,
    )
    return response


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/analyze-page")
async def analyze_page(
    image: UploadFile = File(...),
    page_id: Optional[str] = Form(None),
    ocr_payload: Optional[str] = Form(None),
) -> JSONResponse:
    """
    Receives an annotated page image, sends it to the LLM to produce Anki notes,
    and returns the PageAnalysisResponse shape the iOS client expects.
    """
    image_bytes = await image.read()
    pid = page_id or image.filename or "page"
    parsed_ocr_payload = _parse_client_ocr_payload(ocr_payload, pid)
    logger.info(
        "analyze_page start | page_id=%s | filename=%s | image_bytes=%d | ocr_lines=%d",
        pid,
        image.filename,
        len(image_bytes),
        len(parsed_ocr_payload.get("lines", [])) if parsed_ocr_payload else 0,
    )

    try:
        if client:
            payload = await generate_notes_with_llm(image_bytes, pid, parsed_ocr_payload)
        else:
            payload = stub_payload(pid, warning="OPENAI_API_KEY not set; using stub.")
    except Exception as exc:  # noqa: BLE001
        # Fail soft with a stub response so the app flow keeps working.
        logger.exception("analyze_page failed | page_id=%s | error=%s", pid, exc)
        payload = stub_payload(pid, warning=f"LLM failure ({exc}); returning stub.")

    logger.info(
        "analyze_page done | page_id=%s | notes=%d | warnings=%d | needs_review=%s",
        pid,
        len(payload.get("anki_notes", [])),
        len(payload.get("warnings", [])),
        payload.get("needs_review"),
    )
    return JSONResponse(payload)


# ------------------------
# Helpers
# ------------------------

async def generate_notes_with_llm(
    image_bytes: bytes,
    page_id: str,
    ocr_payload: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    """
    Call OpenAI multimodal model to extract flashcards.
    """
    if not client:
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY missing")

    image_b64 = base64.b64encode(image_bytes).decode("utf-8")
    logger.info("llm request | page_id=%s | encoded_image_chars=%d", page_id, len(image_b64))

    system_prompt = (
        "You extract Japanese study flashcards from one page image and return strict JSON only. "
        "When on-device OCR payload is provided, treat it as primary evidence. "
        "Use image reading only to recover missing or ambiguous OCR parts. "
        "Do not invent text that is not supported by OCR or image evidence. "
        "Preserve reading order (top-to-bottom, left-to-right)."
    )

    ocr_context = _build_ocr_context(ocr_payload)
    user_text = (
        "Analyze this page and return a JSON object that follows schema PageAnalysis.\n"
        "Return every valid flashcard detected on this page (no arbitrary count cap).\n"
        "Scoring rubric per card:\n"
        "- conf_ocr: confidence the surface text was read correctly (0.0 to 1.0).\n"
        "- conf_match: confidence the mapped meaning/translation/match is correct (0.0 to 1.0), and it must not exceed conf_ocr.\n"
        "- warnings: include only concrete uncertainty reasons (ambiguous handwriting, conflicting readings, missing translation).\n\n"
        f"{ocr_context}"
    )

    try:
        schema = {
            "type": "json_schema",
            "json_schema": {
                "name": "PageAnalysis",
                "schema": {
                    "type": "object",
                    "additionalProperties": False,
                    "properties": {
                        "page_id": {"type": "string"},
                        "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                        "warnings": {"type": "array", "items": {"type": "string"}},
                        "anki_notes": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "additionalProperties": False,
                                "properties": {
                                    "id": {"type": "string"},
                                    "front": {"type": "string"},
                                    "back": {"type": "string"},
                                    "hiragana": {"type": "string"},
                                    "kanji": {"type": "string"},
                                    "source": {"type": "string"},
                                    "book_match": {"type": "string"},
                                    "hand_translation": {"type": "string"},
                                    "ai_translation": {"type": "string"},
                                    "conf_ocr": {"type": "number", "minimum": 0, "maximum": 1},
                                    "conf_match": {"type": "number", "minimum": 0, "maximum": 1},
                                    "notes": {"type": "string"},
                                },
                                "required": [
                                    "id",
                                    "front",
                                    "back",
                                    "hiragana",
                                    "kanji",
                                    "source",
                                    "book_match",
                                    "hand_translation",
                                    "ai_translation",
                                    "conf_ocr",
                                    "conf_match",
                                    "notes",
                                ],
                            },
                        },
                    },
                    "required": ["page_id", "confidence", "warnings", "anki_notes"],
                },
                "strict": True,
            },
        }

        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": user_text},
                        {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
                    ],
                },
            ],
            temperature=0,
            max_tokens=2000,
            response_format=schema,
            timeout=90,
        )
        content = response.choices[0].message.content

        parsed = _safe_json_loads(content)
        logger.info(
            "llm response parsed | page_id=%s | content_chars=%d | notes=%d",
            page_id,
            len(content or ""),
            len(parsed.get("anki_notes", [])),
        )
    except OpenAIError as exc:
        logger.exception("llm request failed | page_id=%s | error=%s", page_id, exc)
        raise HTTPException(status_code=502, detail=f"LLM error: {exc}") from exc

    # Normalize output and fill defaults to match app expectations.
    # Review flag is derived server-side from combined confidence to keep semantics deterministic.
    anki_notes = []
    warnings = _normalize_warnings(parsed.get("warnings", []))
    normalized_match_over_ocr_count = 0

    for note in parsed.get("anki_notes", []):
        raw_conf_ocr = _clamp01(_safe_float(note.get("conf_ocr"), default=0.5))
        raw_conf_match = _clamp01(_safe_float(note.get("conf_match"), default=0.5))
        if raw_conf_match > raw_conf_ocr:
            normalized_match_over_ocr_count += 1
        conf_match = min(raw_conf_match, raw_conf_ocr)
        combined_conf = min(raw_conf_ocr, conf_match)
        note_needs_review = combined_conf < REVIEW_COMBINED_THRESHOLD

        anki_notes.append(
            {
                "id": note.get("id") or str(uuid4()),
                "front": note.get("front", "").strip() or "Unknown",
                "back": note.get("back", "").strip(),
                "hiragana": note.get("hiragana", ""),
                "kanji": note.get("kanji", ""),
                "source": note.get("source", ""),
                "book_match": note.get("book_match", ""),
                "hand_translation": note.get("hand_translation", ""),
                "ai_translation": note.get("ai_translation", ""),
                "needs_review": note_needs_review,
                "conf_ocr": raw_conf_ocr,
                "conf_match": conf_match,
                "notes": note.get("notes", ""),
            }
        )

    if normalized_match_over_ocr_count > 0:
        warnings.append(
            f"Normalized conf_match to be <= conf_ocr on {normalized_match_over_ocr_count} card(s)."
        )
    warnings = _dedupe_strings(warnings)

    final_notes = anki_notes or stub_payload(page_id)["anki_notes"]
    page_confidence = sum(min(note["conf_ocr"], note["conf_match"]) for note in final_notes) / len(final_notes)
    page_needs_review = any(note["needs_review"] for note in final_notes)

    payload = {
        "page_id": parsed.get("page_id", page_id),
        "confidence": page_confidence,
        "needs_review": page_needs_review,
        "warnings": warnings,
        "annotations": [],
        "anki_notes": final_notes,
    }
    return payload


def stub_payload(page_id: str, warning: Optional[str] = None) -> Dict[str, Any]:
    warnings: List[str] = []
    if warning:
        warnings.append(warning)
    return {
        "page_id": page_id,
        "confidence": 0.5,
        "needs_review": True,
        "warnings": warnings,
        "annotations": [],
        "anki_notes": [
            {
                "id": str(uuid4()),
                "front": "example",
                "back": "Sample card (stub response).",
                "hiragana": "",
                "kanji": "",
                "source": "stub",
                "book_match": "",
                "hand_translation": "",
                "ai_translation": "",
                "needs_review": True,
                "conf_ocr": 0.5,
                "conf_match": 0.5,
                "notes": "Replace with real output once LLM is configured.",
            }
        ],
    }


def _safe_json_loads(content: str) -> Dict[str, Any]:
    """Attempt to parse strict JSON; if it fails, try to salvage the first JSON object."""
    try:
        return json.loads(content)
    except json.JSONDecodeError:
        logger.warning("json decode failed; trying salvage | raw_starts=%s", (content or "")[:200])
        # Attempt to extract the first {...} block
        match = re.search(r"{[\s\S]*}", content)
        if match:
            try:
                return json.loads(match.group(0))
            except json.JSONDecodeError:
                logger.exception("json salvage failed")
                pass
        logger.error("json decode failed hard | raw_starts=%s", (content or "")[:200])
        raise HTTPException(status_code=502, detail=f"LLM JSON decode error; raw starts: {content[:200]}")


def _parse_client_ocr_payload(raw_payload: Optional[str], page_id: str) -> Optional[Dict[str, Any]]:
    if not raw_payload:
        return None

    try:
        parsed = json.loads(raw_payload)
        if isinstance(parsed, dict) is False:
            logger.warning("ocr payload is not an object | page_id=%s", page_id)
            return None
        return parsed
    except json.JSONDecodeError:
        logger.warning("ocr payload json decode failed | page_id=%s", page_id)
        return None


def _build_ocr_context(ocr_payload: Optional[Dict[str, Any]]) -> str:
    if not ocr_payload:
        return "On-device OCR payload: not provided."

    lines = ocr_payload.get("lines", [])
    if isinstance(lines, list) is False:
        lines = []

    selected_variant = str(ocr_payload.get("selectedVariant", "unknown"))
    aggregate_conf = _safe_float(ocr_payload.get("aggregateConfidence"), default=0.0)
    quality_score = _safe_float(ocr_payload.get("qualityScore"), default=0.0)
    language_code = str(ocr_payload.get("languageCode", "unknown"))

    rendered_lines: List[str] = []
    for idx, item in enumerate(lines[:120]):
        if not isinstance(item, dict):
            continue
        text = str(item.get("text", "")).strip()
        if not text:
            continue
        text = re.sub(r"\s+", " ", text)
        line_conf = _safe_float(item.get("confidence"), default=0.0)
        rendered_lines.append(f"{idx + 1:03d}. [{line_conf:.2f}] {text[:220]}")

    if not rendered_lines:
        rendered_lines.append("(no OCR lines)")

    return (
        "On-device OCR payload summary:\n"
        f"- variant: {selected_variant}\n"
        f"- language: {language_code}\n"
        f"- aggregate_confidence: {aggregate_conf:.2f}\n"
        f"- quality_score: {quality_score:.2f}\n"
        "- lines (reading order):\n"
        + "\n".join(rendered_lines)
    )


def _safe_float(value: Any, default: float) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def _normalize_warnings(raw_warnings: Any) -> List[str]:
    if isinstance(raw_warnings, list) is False:
        return []

    out: List[str] = []
    for item in raw_warnings:
        text = str(item).strip()
        if text:
            out.append(text)
    return out


def _dedupe_strings(values: List[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        out.append(value)
    return out

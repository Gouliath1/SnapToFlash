from uuid import uuid4
from typing import Optional, List, Dict, Any
import base64
import os
import json
import re
import logging

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


@app.get("/health")
async def health() -> dict:
    return {"status": "ok"}


@app.post("/analyze-page")
async def analyze_page(
    image: UploadFile = File(...), page_id: Optional[str] = Form(None)
) -> JSONResponse:
    """
    Receives an annotated page image, sends it to the LLM to produce Anki notes,
    and returns the PageAnalysisResponse shape the iOS client expects.
    """
    image_bytes = await image.read()
    pid = page_id or image.filename or "page"
    logger.info("analyze_page start | page_id=%s | filename=%s | image_bytes=%d", pid, image.filename, len(image_bytes))

    try:
        if client:
            payload = await generate_notes_with_llm(image_bytes, pid)
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

async def generate_notes_with_llm(image_bytes: bytes, page_id: str) -> Dict[str, Any]:
    """
    Call OpenAI multimodal model to extract flashcards.
    """
    if not client:
        raise HTTPException(status_code=500, detail="OPENAI_API_KEY missing")

    image_b64 = base64.b64encode(image_bytes).decode("utf-8")
    logger.info("llm request | page_id=%s | encoded_image_chars=%d", page_id, len(image_b64))

    system_prompt = (
        "You are an assistant that extracts study flashcards from photos and prepares them for user validation before Anki export. "
        "Inputs can include: (a) a printed book page with highlights/underlines, (b) a handwritten notebook with vocab lines "
        "kanji→hiragana→translation/comment (phrases allowed). Goal: map notebook entries to the closest matching word/phrase on the book page. "
        "If no translation exists, use the highlighted book text itself. "
        "Order the anki_notes array in reading order from this single image: top-to-bottom, and left-to-right for ties. "
        "Follow the rules and output only valid JSON matching the provided schema."
    )

    user_text = (
        "Analyze this page and return a JSON object that follows the schema named PageAnalysis. "
        "Combine all detected cards into anki_notes (max 40), already sorted by reading order (top-to-bottom, left-to-right)."
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
                        "confidence": {"type": "number"},
                        "needs_review": {"type": "boolean"},
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
                                    "needs_review": {"type": "boolean"},
                                    "conf_ocr": {"type": "number"},
                                    "conf_match": {"type": "number"},
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
                                    "needs_review",
                                    "conf_ocr",
                                    "conf_match",
                                    "notes",
                                ],
                            },
                        },
                    },
                    "required": ["page_id", "confidence", "needs_review", "warnings", "anki_notes"],
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

    # Normalize output and fill defaults to match app expectations
    anki_notes = []
    for note in parsed.get("anki_notes", []):
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
                "needs_review": bool(note.get("needs_review", False)),
                "conf_ocr": float(note.get("conf_ocr", 0.5)),
                "conf_match": float(note.get("conf_match", 0.5)),
                "notes": note.get("notes", ""),
            }
        )

    payload = {
        "page_id": parsed.get("page_id", page_id),
        "confidence": float(parsed.get("confidence", 0.7)),
        "needs_review": bool(parsed.get("needs_review", False)),
        "warnings": parsed.get("warnings", []),
        "annotations": [],
        "anki_notes": anki_notes or stub_payload(page_id)["anki_notes"],
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

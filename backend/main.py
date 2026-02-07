from uuid import uuid4
from typing import Optional, List, Dict, Any
import base64
import os
import json

from fastapi import FastAPI, File, Form, UploadFile, HTTPException
from fastapi.responses import JSONResponse
from openai import OpenAI, OpenAIError

app = FastAPI()

OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4o-mini")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
client = OpenAI(api_key=OPENAI_API_KEY) if OPENAI_API_KEY else None


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

    try:
        if client:
            payload = await generate_notes_with_llm(image_bytes, pid)
        else:
            payload = stub_payload(pid, warning="OPENAI_API_KEY not set; using stub.")
    except Exception as exc:  # noqa: BLE001
        # Fail soft with a stub response so the app flow keeps working.
        payload = stub_payload(pid, warning=f"LLM failure ({exc}); returning stub.")

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

    system_prompt = (
        "You are an assistant that extracts flashcards from annotated textbook pages. "
        "Return a JSON object with keys: page_id, confidence (0-1), needs_review (bool), "
        "warnings (list), annotations (empty list if none), anki_notes (list of notes). "
        "Each note must have: id (uuid), expression_or_word, reading, meaning, example, "
        "confidence (0-1), needs_review (bool). Keep values concise and safe."
    )

    user_text = (
        "Analyze this page and propose 1-5 high-quality Anki notes. "
        "Use the source text; avoid hallucinating. If unsure, mark needs_review=true."
    )

    try:
        response = client.chat.completions.create(
            model=OPENAI_MODEL,
            messages=[
                {"role": "system", "content": system_prompt},
                {
                    "role": "user",
                    "content": [
                        {"type": "text", "text": user_text},
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"},
                        },
                    ],
                },
            ],
            max_tokens=500,
            response_format={"type": "json_object"},
        )
        content = response.choices[0].message.content
        parsed = json.loads(content)
    except (OpenAIError, json.JSONDecodeError, KeyError) as exc:
        raise HTTPException(status_code=502, detail=f"LLM error: {exc}") from exc

    # Normalize output and fill defaults
    anki_notes = []
    for note in parsed.get("anki_notes", []):
        anki_notes.append(
            {
                "id": note.get("id") or str(uuid4()),
                "expression_or_word": note.get("expression_or_word", "").strip() or "Unknown",
                "reading": note.get("reading") or "",
                "meaning": note.get("meaning", "").strip() or "To fill",
                "example": note.get("example") or "",
                "confidence": float(note.get("confidence", 0.5)),
                "needs_review": bool(note.get("needs_review", False)),
            }
        )

    payload = {
        "page_id": parsed.get("page_id", page_id),
        "confidence": float(parsed.get("confidence", 0.7)),
        "needs_review": bool(parsed.get("needs_review", False)),
        "warnings": parsed.get("warnings", []),
        "annotations": parsed.get("annotations", []),
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
                "expression_or_word": "example",
                "reading": "",
                "meaning": "Sample card (stub response).",
                "example": "Replace with real output once LLM is configured.",
                "confidence": 0.5,
                "needs_review": True,
            }
        ],
    }

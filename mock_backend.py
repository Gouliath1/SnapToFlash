from fastapi import FastAPI, UploadFile, File, Form
from fastapi.responses import JSONResponse
app = FastAPI()
@app.post("/analyze-page")
async def analyze_page(image: UploadFile = File(...), page_id: str | None = Form(None)):
    return JSONResponse({
        "page_id": page_id or image.filename,
        "confidence": 0.9,
        "needs_review": False,
        "warnings": [],
        "annotations": [],
        "anki_notes": [{
            "id": "00000000-0000-0000-0000-000000000000",
            "expression_or_word": "example",
            "reading": "ex-am-ple",
            "meaning": "sample card",
            "example": "This is an example sentence.",
            "confidence": 0.9,
            "needs_review": False
        }]
    })

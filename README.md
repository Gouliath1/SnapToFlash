# SnapToFlash

SwiftUI iOS app that turns annotated textbook photos into Anki flashcards. A FastAPI backend processes images (stub or OpenAI multimodal) and returns card data.

## Repo structure
- `SnapToFlash/` – iOS app sources.
- `backend/` – FastAPI server.
- `scripts/run_backend.sh` – one-shot local backend runner.
- `ARCHITECTURE.md` – short architecture overview.

## Quick start (local backend)
1) From repo root:
   ```bash
   cp .env.example .env   # fill in OPENAI_API_KEY
   bash scripts/run_backend.sh
   ```
2) Ensure `SnapToFlash/Info.plist` has `BackendBaseURL` = `http://127.0.0.1:8787`.
3) Run the app in the simulator; “Generate flashcards” should hit the local server.

## Deploy backend to Fly.io (summary)
```bash
flyctl auth login
flyctl secrets set OPENAI_API_KEY=sk-... OPENAI_MODEL=gpt-4o-mini -a snaptoflash-backend
flyctl deploy -a snaptoflash-backend
```
Then set `BackendBaseURL` in `SnapToFlash/Info.plist` to `https://<your-app>.fly.dev` and rebuild.

## Environment variables
- `OPENAI_API_KEY` (required for real LLM output; otherwise stub response)
- `OPENAI_MODEL` (optional; default `gpt-4o-mini`)
- `PORT` (optional; default `8787` for local server)

## Notes
- `.env` is ignored by git; use `.env.example` as a template.
- The backend falls back to a stub response if the API key is missing or the LLM call fails.

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
   bash scripts/run_backend.sh local
   ```
2) Script automatically sets app backend URL keys in `SnapToFlash/Info.plist`.
   - `local` mode defaults to `BackendBaseURLDebug`
   - `fly` mode defaults to `BackendBaseURLRelease`
3) Run the app in the simulator; “Generate flashcards” should hit the local server.

## Deploy backend to Fly.io (summary)
```bash
flyctl auth login
bash scripts/run_backend.sh fly
```
The script deploys to Fly and updates `SnapToFlash/Info.plist` with `https://<app>.fly.dev`.

### Script modes
```bash
scripts/run_backend.sh local                      # run local backend + point app to local URL
scripts/run_backend.sh fly                        # deploy Fly backend + point app to Fly URL
scripts/run_backend.sh --mode fly --app <name>   # explicit Fly app name override
scripts/run_backend.sh local --config debug       # update debug URL key only
scripts/run_backend.sh fly --config release       # update release URL key only
scripts/run_backend.sh --mode local --config all  # update both debug + release keys
scripts/run_backend.sh --no-configure-app local  # do not modify Info.plist
```

## Environment variables
- `OPENAI_API_KEY` (required for real LLM output; otherwise stub response)
- `OPENAI_MODEL` (optional; default `gpt-4o-mini`)
- `PORT` (optional; default `8787` for local server)

## Notes
- App URL resolution order:
  - DEBUG build: `BackendBaseURLDebug` -> `BackendBaseURL` -> `http://127.0.0.1:8787`
  - RELEASE build: `BackendBaseURLRelease` -> `BackendBaseURL` -> `http://127.0.0.1:8787`
- `.env` is ignored by git; use `.env.example` as a template.
- The backend falls back to a stub response if the API key is missing or the LLM call fails.

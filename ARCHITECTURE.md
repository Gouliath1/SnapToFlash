# SnapToFlash: Architecture Overview

## 1) Current architecture
- **iOS app (SwiftUI)**: Captures annotated photos, sends them to a server, and displays generated Anki cards.
- **Backend server (FastAPI, Python)**: Simple stub endpoint that receives a photo and returns sample card data.
- **Config**: The app reads `BackendBaseURL` from `Info.plist` (defaults to `http://localhost:8787`).

## 2) Why this architecture
- The phone handles UI and photo capture.
- The server handles heavier work (OCR/LLM/card generation) so the app stays light, fast, and easy to update without shipping a new app build.

## 3) Why these tools
- **SwiftUI**: Modern, quick to build iOS UI.
- **FastAPI**: Lightweight Python web framework that’s great for JSON APIs.
- **Docker**: Packages the backend and its dependencies into one portable image—runs the same locally and in the cloud.
- **Fly.io**: Simple hosting that runs Docker containers close to users and gives you a public URL with minimal setup.

## 4) How Docker and Fly.io work (plain version)
- **Docker**: “Zip” your app + dependencies into an image; run it anywhere with `docker run`.
- **Fly.io**: You give Fly a Docker image; Fly runs it on their servers and gives you a public URL. Steps are: log in (`flyctl auth login`), create an app, set the internal port (8787), deploy.

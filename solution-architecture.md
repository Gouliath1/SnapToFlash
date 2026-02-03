# Solution Architecture

## Overview
A minimal client + thin backend proxy + AnkiConnect integration. This document covers system components and their boundaries only; UX flow and detailed behaviors are defined in solution-design.md and MVP_SPEC.md.

## Components
- **Client app**
  - Capture/import images.
  - Communicates with backend and AnkiConnect.

- **Backend proxy (recommended)**
  - Single analysis endpoint (`POST /analyze-page`).
  - Forwards requests to OpenAI vision-capable API.
  - Optional caching and rate limiting.

- **Anki integration**
  - **Preferred:** AnkiConnect (local desktop service).
  - **Fallback:** CSV export.

## Interfaces
- Client → Backend: image + optional page_id → JSON response.
- Client → AnkiConnect: add notes to a selected deck/model.

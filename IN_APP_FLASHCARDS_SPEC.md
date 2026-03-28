# In-App Flashcards Specification (No Anki Dependency)

## 1) Purpose
Build a full study loop directly inside SnapToFlash so users can capture, review, and retain cards without Anki Desktop or AnkiMobile.

This spec defines the product and technical requirements for a local-first flashcard system integrated with the current OCR -> card generation flow.

## 2) Product Goals
1. Let users study cards entirely in-app on iPhone.
2. Preserve the current fast capture -> generate -> validate flow.
3. Add spaced repetition scheduling with predictable, explainable behavior.
4. Keep interoperability via CSV export/import so users are never locked in.

## 3) Non-Goals (Phase 1)
1. No account system or cloud sync.
2. No collaborative deck sharing.
3. No advanced template scripting like desktop Anki.
4. No AI-based scheduler tuning in first release.

## 4) Experience Principles (Inspired by Proven Flashcard Apps)
1. Queue clarity (Anki pattern): separate New, Learning, Review counts and due dates.
2. Daily momentum (RemNote pattern): daily goals, streak, and simple progress feedback.
3. Local-first speed (Mochi pattern): fast edits, immediate state changes, no network dependency for study.

## 5) User Flows
### 5.1 Create cards from photos
1. User imports/captures pages.
2. App generates candidate cards.
3. User validates/rejects cards.
4. Accepted cards are saved into an in-app deck.

### 5.2 Study due cards
1. User opens deck and taps `Study`.
2. App shows next due card.
3. User flips card and selects one rating:
   - Again
   - Hard
   - Good
   - Easy
4. App reschedules card and continues until queue complete.

### 5.3 Manage decks/cards
1. Create/rename/archive deck.
2. Edit card content and tags.
3. Suspend/unsuspend card.
4. Search/filter cards by text, tag, deck, due status.

## 6) Functional Scope (Phase 1 MVP)
1. In-app decks and cards with local persistence.
2. Spaced repetition scheduler (SM-2 style baseline).
3. Study session UI with card flip and 4-grade review actions.
4. Daily queue planning (new cap + review cap).
5. Basic stats: due count, reviewed today, streak.
6. CSV import/export compatibility.

## 7) Data Model
### 7.1 Entities
1. `Deck`
   - `id`, `name`, `createdAt`, `archivedAt?`
2. `Card`
   - `id`, `deckID`, `front`, `reading?`, `back`, `example?`, `sourcePage?`, `tags[]`, `createdAt`, `updatedAt`
3. `ReviewState`
   - `cardID`, `status` (`new|learning|review|relearning|suspended`), `dueAt`, `intervalDays`, `easeFactor`, `lapses`, `reps`
4. `ReviewLog`
   - `id`, `cardID`, `reviewedAt`, `grade` (`again|hard|good|easy`), `previousInterval`, `newInterval`, `durationMs`
5. `StudySettings`
   - `deckID`, `maxNewPerDay`, `maxReviewsPerDay`, `learningStepsMinutes[]`, `graduatingIntervalDays`, `easyIntervalDays`

### 7.2 Initial defaults
1. `maxNewPerDay = 20`
2. `maxReviewsPerDay = 200`
3. `learningStepsMinutes = [1, 10]`
4. `graduatingIntervalDays = 1`
5. `easyIntervalDays = 4`

## 8) Scheduling Rules (Phase 1)
1. New card enters `learning` after first study.
2. `Again`:
   - move to first learning step, increment lapses if card was in review.
3. `Hard`:
   - short interval increase; do not leap aggressively.
4. `Good`:
   - normal progression to next step or review interval.
5. `Easy`:
   - larger interval jump and slight ease increase.
6. Review interval math follows SM-2-style factors with caps to avoid unstable jumps.
7. All due times stored in UTC.

## 9) Queue Construction
1. Build queue in this order:
   - due learning/relearning
   - due reviews
   - new cards (up to daily cap)
2. Respect deck filters and suspension state.
3. Persist queue state so interrupted sessions can resume.

## 10) UX Requirements
### 10.1 Deck screen
1. Show due counts: `Learning`, `Review`, `New`.
2. Show `Study` CTA and quick stats.

### 10.2 Study screen
1. Front side first, tap to reveal back.
2. After reveal, show four answer buttons.
3. Show next-interval hint on each button (for transparency).
4. Large tap targets and one-hand layout.

### 10.3 Card editor
1. Editable fields: front, reading, back, example, tags.
2. Save changes instantly.
3. Optional `Suggest translation` action can remain AI-backed.

## 11) Integration With Existing Pipeline
1. Existing `pendingNotes` validation remains unchanged.
2. On acceptance, map `AnkiNote` -> in-app `Card` + initial `ReviewState`.
3. Keep existing CSV export path operational.
4. Keep Anki export optional and decoupled from in-app study.

## 12) Technical Architecture
1. Add a local store layer (SwiftData preferred for this codebase).
2. Add `StudyEngine` service for queue and scheduling decisions.
3. Add `DeckRepository` and `CardRepository` for persistence operations.
4. Keep scheduling logic pure and testable (no UI dependencies).

## 13) Observability and Safety
1. Log scheduling decisions in debug mode.
2. Add invariant checks:
   - no negative intervals
   - no missing due date for active cards
3. Add migration-safe schema evolution plan before ship.

## 14) Acceptance Criteria
1. User can complete end-to-end flow without Anki:
   - capture -> generate -> validate -> study
2. App correctly surfaces due queue on next launch.
3. Scheduler updates card due dates deterministically for each grade.
4. CSV import/export roundtrip preserves key card fields.
5. Study actions remain responsive (<100ms local state update target).

## 15) Implementation Phases
### Phase A: Foundation
1. Add persistence schema (`Deck`, `Card`, `ReviewState`, `ReviewLog`, `StudySettings`).
2. Migrate accepted cards into deck storage.
3. Build deck list and deck detail screens.

### Phase B: Study Engine
1. Implement queue builder and SM-2-style scheduler.
2. Implement study session UI and grading actions.
3. Add interruption/resume behavior.

### Phase C: Management and Stats
1. Card editor, tags, search/filter.
2. Daily stats and streak.
3. CSV import/export hardening.

### Phase D: Post-MVP Enhancements
1. Optional FSRS-compatible scheduler upgrade.
2. Smart daily goals and retention predictions.
3. Optional cloud backup/sync.

## 16) Open Decisions
1. Keep one default deck or require deck selection on first save.
2. Whether cards generated from one scan batch should be auto-grouped by source set.
3. Whether to keep Anki export visible by default once in-app study is enabled.

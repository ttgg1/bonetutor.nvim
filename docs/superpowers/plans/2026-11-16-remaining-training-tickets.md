# Remaining Training Tickets Implementation Plan

> **For agentic workers:** Execute inline, one task at a time. Use TDD and run the headless suite after each ticket.

**Goal:** Complete BT-06 through BT-09: adaptive practice, Bone layout hints, daily/session feedback, and a documented disposition for optional enhancements.

**Architecture:** Keep scheduler/composition logic pure Lua, progress persistence in `progress.lua`, and Neovim session/window lifecycle in `init.lua`. Add layout metadata in its own module. Reuse the dependency-free two-pane tutor.

**Tech Stack:** Neovim Lua APIs and the existing headless test harness.

**Spec:** `docs/tickets.md`, BT-06 through BT-09; constraints in `AGENTS.md`.

## Global Constraints

- Preserve default Vim keybindings; install no global or buffer-local mappings.
- Keep the plugin dependency-free and compatible with the current command-driven LazyVim setup.
- Isolate headless state with `XDG_STATE_HOME`.
- Persist no raw keystrokes or user code.
- Standard Bone is the no-configuration default; do not assume physical modifier placement.
- Do not intercept OS keyboard events; Neovim observes logical input only.

## Review Focus

- Existing/malformed progress and malformed skill records remain safe after schema expansion (Task 1 tests migration and sanitization).
- Scheduled callbacks cannot mutate replaced or closed adaptive/daily sessions (Tasks 1 and 3 exercise reset, restart, and quit).
- Layout hints represent logical keys, not physical key identities (Task 2 tests mappings and documents the distinction).
- Empty/due/prerequisite-constrained scheduler inputs still produce a usable deterministic daily sequence (Task 3 tests fallback behavior).
- Optional enhancements remain dependency-free and opt-in; tests continue asserting global mappings and clipboard options are unchanged (Task 4 keeps existing assertions).

---

### Task 1: BT-06 — Persist outcomes and expose adaptive practice

**Files:**
- Modify: `lua/bonetutor/progress.lua`
- Modify: `lua/bonetutor/scheduler.lua`
- Modify: `lua/bonetutor/init.lua`
- Modify: `plugin/bonetutor.lua`
- Modify: `tests/run.lua`
- Modify: `README.md`, `docs/tickets.md`

**Interfaces:**
- Add `progress.record_attempt(state, skill, exercise_id, outcome, metadata, now) -> state`. `outcome` is `"success"` or `"failure"`; metadata has `hint_used` and `duration_seconds`. Keep only the latest 20 entries in a skill’s `recent` array.
- Add `:BoneTutorPractice` which chooses the next catalog item with `scheduler.next(...)`; keep `:BoneTutor[ number]` as guided mode.
- `scheduler.next(state, exercises, now, seed)` remains the selection seam.

- [x] **Step 1: Write failing tests** for skill-state update, bounded history, invalid-record sanitization, adaptive command registration, recorded success/failure/hint/duration, and guided behavior preservation.
- [x] **Step 2: Run the headless suite and confirm** the new assertions fail because these interfaces/behaviors are absent.
- [x] **Step 3: Implement** version-2-compatible skill state updates, migration-safe sanitization, adaptive session selection, and session outcome recording. Never store input text or keystrokes.
- [x] **Step 4: Run the headless suite and smoke command.** Verify the passing session still checks real buffer/cursor state and installs no mappings or option changes.
- [x] **Step 5: Update** BT-06 status and user documentation; commit as `feat: add adaptive practice tracking`.

### Task 2: BT-07 — Render accurate Bone logical-key hints

**Files:**
- Create: `lua/bonetutor/layouts.lua`
- Modify: `lua/bonetutor/lessons.lua`
- Modify: `lua/bonetutor/init.lua`
- Modify: `tests/run.lua`
- Modify: `README.md`, `docs/tickets.md`

**Interfaces:**
- `layouts.standard` contains layer rows and logical-key locations; `layouts.describe(keys, layout)` returns displayable location/layer data.
- Lessons may supply a `keys` string for the command being taught; old lesson records without it remain valid.
- The UI highlights logical keys on the existing optional keyboard panel; standard Bone is the default.

- [x] **Step 1: Write failing tests** for the authoritative standard Bone letter rows, symbol-layer metadata used by current exercises, key lookup/highlighting, and absent/unknown keys.
- [x] **Step 2: Run the suite and confirm** layout-module tests fail before its implementation.
- [x] **Step 3: Implement** declarative logical layout data and current-exercise highlighting, without claiming physical key detection or assuming modifier positions.
- [x] **Step 4: Run the headless suite** and verify toggling hints leaves maps/options unchanged.
- [x] **Step 5: Update** layout documentation and BT-07 status; commit as `feat: show Bone command key positions`.

### Task 3: BT-08 — Add deterministic daily sessions and summaries

**Files:**
- Modify: `lua/bonetutor/scheduler.lua`
- Modify: `lua/bonetutor/init.lua`
- Modify: `plugin/bonetutor.lua`
- Modify: `tests/run.lua`
- Modify: `README.md`, `docs/tickets.md`

**Interfaces:**
- Add `scheduler.daily(state, exercises, now, seed, limit) -> exercises`, returning a stable sequence of up to `limit` due reviews and no more than two eligible new skills.
- Add `:BoneTutorDaily`; use the existing tutor panes and no UI dependency.
- Daily completion/quit presents a concise result summary derived from session-local counts and persisted skill outcomes.

- [x] **Step 1: Write failing tests** for stable composition at fixed state/time/seed, review-first selection, at most two new skills, empty-candidate fallback, summary counts, and teardown after quit/restart.
- [x] **Step 2: Run the suite and confirm** composition/command/summary behavior is missing.
- [x] **Step 3: Implement** daily sequence selection and safe session progression/summary. Scheduled callbacks must validate the session generation and current exercise before updating.
- [x] **Step 4: Run the suite and smoke command.** Confirm no callback mutates a closed/replaced session and no mappings/options are changed.
- [x] **Step 5: Update** daily-session documentation and BT-08 status; commit as `feat: add daily training sessions`.

### Task 4: BT-09 — Record optional-feature decisions

**Files:**
- Modify: `docs/tickets.md`
- Modify: `README.md` only if a user-facing behavior is accepted
- Modify: tests only if an opt-in behavior is implemented

**Interfaces:** No new runtime interface unless an enhancement is explicitly implemented.

- [ ] **Step 1: Evaluate** dashboard, free practice, alternate Bone variants, QWERTZ comparison, and `hjkl`-reduced drills against dependencies, learning value, and test cost.
- [ ] **Step 2: Record** each choice as accepted/deferred with a concise rationale; retain physical-key interception as out of scope.
- [ ] **Step 3: If accepting an enhancement**, first add a failing headless test, then implement it as dependency-free and disabled by default.
- [ ] **Step 4: Run** the full suite and `git diff --check`; mark BT-09 complete with its decisions and commit as `docs: close optional training enhancement ticket`.

# BoneTutor.nvim implementation tickets

These tickets implement the adaptive-training plan incrementally. Preserve normal
Vim keybindings, avoid global mappings/options, and keep the plugin dependency-free.
Run the headless Neovim test suite after each ticket.

## BT-01 — Add a headless lesson test harness (P0)

**Scope:** Add `tests/run.lua` and reusable helpers to load the plugin in headless
Neovim and inspect real buffers, cursor positions, and modes.

**Acceptance criteria**

- Every lesson definition is checked for required fields and valid source/start/target
  coordinates.
- Harness can execute real Normal-mode commands and inspect resulting state.
- Document the full-suite command in `README.md`.
- No production behavior changes in this ticket.

**Verification**

```sh
nvim --headless -u NONE --cmd 'set runtimepath^=.' +"lua dofile('tests/run.lua')" +qa
```

## BT-02 — Verify lesson behavior and session lifecycle (P0)

**Depends on:** BT-01

**Scope:** Add actual behavior tests for all existing movement and edit lessons,
including operators, text objects, insert/escape, yank/paste, and cursor checks.
Exercise scheduled validation around reset, next, buffer wipe, and tab close.

**Acceptance criteria**

- Every existing lesson has a verified native Vim outcome.
- Regressions found by tests are fixed minimally in `lua/bonetutor/init.lua` or
  `lua/bonetutor/lessons.lua`.
- Clipboard/register settings and global mappings/options are unchanged by session
  start/quit.
- Session cleanup is safe after a queued watcher callback.

**Verification:** Run the suite from BT-01 and the documented start/quit smoke command.

## BT-03 — Introduce versioned progress storage (P0)

**Depends on:** BT-01

**Scope:** Add `lua/bonetutor/progress.lua` to own state loading, validation,
migration, and persistence; preserve `stdpath("state")/bonetutor.json`.

**Acceptance criteria**

- Migrate `{ completed = n }` to a versioned state without losing sequential progress.
- Missing, malformed, unsupported, and out-of-range state values fail safely.
- Write failures produce a warning and do not abort the session.
- Tests use an isolated state path and cover all migration/error cases.

## BT-04 — Add stable skill IDs and exercise variants (P1)

**Depends on:** BT-01

**Scope:** Add `lua/bonetutor/exercises.lua`; annotate existing guided lessons with
stable skill IDs and introduce a small set of distinct fixtures for common weak skills.

**Acceptance criteria**

- Existing guided lesson order, prompts, and commands remain available.
- Variants for word motion, delete-word, and change-inside-word have distinct fixtures
  and deterministic targets.
- Exercise data has no executable validation payloads and persists no user content.

## BT-05 — Implement deterministic adaptive scheduling (P1)

**Depends on:** BT-03, BT-04

**Scope:** Add `lua/bonetutor/scheduler.lua` with
`scheduler.next(state, exercises, now, seed) -> selection`.

**Acceptance criteria**

- Weak and due skills are prioritized; prerequisite skills gate compound exercises.
- Repeated attempts smooth proficiency; one success cannot immediately mark mastery.
- Mastered skills remain eligible for later review.
- A fixed state/time/seed produces the same selection and avoids immediately repeating
  the same variant when alternatives exist.
- Tests cover due reviews, weak-skill priority, prerequisites, deterministic selection,
  variant diversity, and no-eligible-exercise behavior.

## BT-06 — Record outcomes and expose adaptive practice (P1)

**Depends on:** BT-02, BT-03, BT-04, BT-05

**Scope:** Wire success/failure/reset, hint usage, and elapsed time into progress state.
Add a dedicated adaptive-practice command while preserving `:BoneTutor` guided/resume.

**Acceptance criteria**

- Attempts, results, hint counts, elapsed duration, recent bounded history, and
  timestamps are recorded without raw keystrokes.
- Guided lessons and numeric lesson selection retain current behavior.
- Adaptive sessions use the scheduler and can be quit/restarted safely.
- No key mappings or global option changes are installed.

## BT-07 — Improve Bone layout hints (P2)

**Depends on:** BT-04

**Scope:** Add `lua/bonetutor/layouts.lua` with standard Bone logical key positions,
relevant modifier-layer labels, and current-command highlighting.

**Acceptance criteria**

- Layout data is checked against the documented authoritative Bone layout.
- Hints can be toggled; baseline behavior works with no user configuration.
- Variant and QWERTZ comparison options remain opt-in.
- Documentation clearly distinguishes logical keys received by Neovim from physical
  key detection; no keyboard interception is added.

## BT-08 — Add session feedback and daily challenge (P2)

**Depends on:** BT-05, BT-06

**Scope:** Add compact session progress, success feedback, session summary, and a
5–10-minute daily sequence using due reviews and at most two eligible new challenges.

**Acceptance criteria**

- Challenge composition is deterministic for a fixed date and state.
- Teardown persists results and displays a concise summary.
- Basic operation has no UI-library dependency.

## BT-09 — Evaluate optional practice enhancements (P3)

**Depends on:** BT-07, BT-08

**Scope:** Separately assess dashboard, free practice, alternate Bone variants,
QWERTZ comparison, `hjkl`-reduced drills, and realistic language snippets.

**Acceptance criteria**

- Each accepted enhancement is opt-in, independently testable, and dependency-free.
- Physical-key tracking and invasive interception remain explicitly out of scope.
- Avoid adding features without demonstrated learning value.

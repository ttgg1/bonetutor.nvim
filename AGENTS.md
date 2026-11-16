# Agent notes

- Run commands from this plugin root; the headless suite is `nvim --headless -u NONE --cmd 'set runtimepath^=.' +"lua dofile('tests/run.lua')" +qa`. The README's start/quit smoke command is a separate quick integration check.
- `lua/bonetutor/lessons.lua` is the guided lesson source; `exercises.lua` assigns stable skill IDs and variants, and `scheduler.lua` selects from definitions without Neovim UI dependencies.
- `lua/bonetutor/init.lua` owns the tutor tab/session and validates native buffer/cursor state. `plugin/bonetutor.lua` registers commands. Keep training isolated: add no global or buffer-local key mappings.
- Preserve default Vim behavior: exercises should be completed with native motions/operators/text objects, and validation should check resulting editor state rather than remapping input.
- Tests create isolated `XDG_STATE_HOME` before starting sessions; preserve this so test runs do not alter the user's `stdpath("state")/bonetutor.json`.
- Progress is stored in `stdpath("state")/bonetutor.json`; `lua/bonetutor/progress.lua` owns schema versioning and migration from legacy `{completed = n}` data.
- Editing drills use real registers; when users have clipboard integration enabled, normal Vim register side effects may reach the system clipboard. Do not silently alter `clipboard` or register settings.
- No external dependencies, lint/typecheck scripts, or CI workflows are configured; use the README's headless commands for verification.

# BoneTutor.nvim

A tiny, dependency-free, interactive Neovim tutor for the **standard Bone keyboard layout** (a Neo variant), with **unaltered Vim keybindings**. Designed for people moving from QWERTZ to Bone, particularly when using LazyVim.

It opens a separate tab with a read-only goal panel above a real practice buffer. You carry out an exercise using normal Vim movements and editing commands; the tutor checks the resulting **cursor position or buffer content**. Nothing is remapped. Progress is saved between sessions.

## Install in LazyVim

1. Extract the archive so that the plugin lives at:

   `~/.config/nvim/local/bonetutor.nvim/`

   That directory must contain `plugin/bonetutor.lua` and `lua/bonetutor/init.lua`.

2. Copy `examples/lazyvim.lua` to `~/.config/nvim/lua/plugins/bonetutor.lua`, **or** create that file with:

   ```lua
   return {
     {
       dir = vim.fn.stdpath("config") .. "/local/bonetutor.nvim",
       name = "bonetutor.nvim",
       cmd = {
         "BoneTutor", "BoneTutorNext", "BoneTutorPrev", "BoneTutorReset",
         "BoneTutorHint", "BoneTutorKeys", "BoneTutorQuit",
       },
     },
   }
   ```

3. Restart Neovim and enter `:BoneTutor`.

If you use plain Neovim instead of LazyVim, you can put the unpacked plugin at `~/.local/share/nvim/site/pack/bone/start/bonetutor.nvim/` and restart.

## Commands

| Command | Action |
| --- | --- |
| `:BoneTutor` | Start or resume the first unfinished lesson. Focus an existing tutor if it is already open. |
| `:BoneTutor 5` | Jump to lesson 5. |
| `:BoneTutorHint` | Show/hide the Bone-specific key position hint. |
| `:BoneTutorKeys` | Show/hide the standard Bone layer-1 letter rows. |
| `:BoneTutorNext` | Advance manually; passing a lesson also advances automatically after a brief success message. |
| `:BoneTutorPrev` | Go to the previous lesson. |
| `:BoneTutorReset` | Reset the current lesson. |
| `:BoneTutorQuit` | Close the tutorial tab. |

No mappings (even buffer-local) are installed, so this does not collide with LazyVim's mappings. Commands and practice operate inside the tutor tab only.

## Exercises

26 short lessons progress through:

- single-step `h/j/k/l` movements, using the actual Bone key locations;
- `w/b/e`, `3w`, `0/$`, `gg/G`;
- `f`, `t`, `/`, `%`, including Bone's symbol layer;
- `dw`, `diw`, `ciw`, `dd`, `x`;
- `o`, `A`, `yy` + `p`, `d$`, `ci"`.

The prompts state the **intent**, so you learn *what you want to do → Vim command → Bone finger position*, instead of translating through QWERTZ. Use `:BoneTutorHint` when you need the spelling or physical position.

The reference rows are the standard Bone arrangement:

```
j d u a x  |  p h l m w q
c t i e o  |  b n r s g ß
f v ü ä ö  |  y z , . k
```

Bone's layers 3 and 4 retain the Neo layer arrangements. Commands involving punctuation mention the symbol layer in their hints.

## Important details

- **Native Vim is intentionally used:** the check verifies the final state, not how you got there. For meaningful practice, don't use arrow keys for the `hjkl` lessons. Plugins that intercept a native command may need to be disabled for the affected lesson.
- As in VimTutor, edits use real Vim operators and registers. If your configuration maps the unnamed register to the system clipboard, `d`, `x`, and `yy` may change your clipboard. Practice in the isolated tutor buffer, but consider temporarily changing your clipboard option if this matters to you.
- A goal involving insertion passes after you press Escape and the resulting buffer matches the target.
- On pass, the tutor briefly shows success, then automatically loads the next lesson. Passing the final lesson shows the completion message.
- Session progress lives at `stdpath("state")/bonetutor.json` in a versioned format. Existing `{"completed": n}` progress is migrated automatically; delete **that specific file** to restart from lesson 1, or jump to any exercise with `:BoneTutor <number>`.
- The layout map assumes standard Bone; a custom Bone/Q/ß variant may differ in those letter positions. Nothing in the tutor changes the OS layout.

## Developing or testing

This intentionally avoids external dependencies. From the plugin's directory, if `nvim` is installed, run:

```sh
nvim --headless -u NONE --cmd 'set runtimepath^=.' \
  +"lua dofile('tests/run.lua')" +qa

nvim --headless -u NONE --cmd 'set runtimepath^=.' \
  +"lua require('bonetutor').start('1')" \
  +"lua assert(require('bonetutor').lesson_count() == 26)" \
  +"lua require('bonetutor').quit()" +qa
```

Then test the interactive flow in a regular Neovim session (including `:BoneTutorHint`, completing a motion, and `:BoneTutorNext`).

Layout reference: [official Bone page](https://www.neo-layout.org/Layouts/bone/).

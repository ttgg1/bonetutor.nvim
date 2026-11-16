vim.env.XDG_STATE_HOME = vim.fn.tempname()
vim.fn.mkdir(vim.env.XDG_STATE_HOME, "p")

local lessons = require("bonetutor.lessons")
local failures = 0
local keymaps_before = {
  n = vim.api.nvim_get_keymap("n"),
  i = vim.api.nvim_get_keymap("i"),
  v = vim.api.nvim_get_keymap("v"),
}
local clipboard_before = vim.o.clipboard
local function check(condition, message)
  if not condition then
    failures = failures + 1
    io.stderr:write("FAIL: " .. message .. "\n")
  end
end
local function position_is_valid(position, lines)
  return type(position) == "table"
    and type(position[1]) == "number"
    and type(position[2]) == "number"
    and lines[position[1]] ~= nil
    and position[2] >= 1
    and position[2] <= #lines[position[1]]
end

local progress = require("bonetutor.progress")
local scheduler = require("bonetutor.scheduler")
local exercise_catalog = require("bonetutor.exercises")
local progress_file = vim.fn.tempname()
local migrated = progress.load(progress_file, #lessons)
check(migrated.version == 2 and migrated.guided_completed == 0, "missing progress starts at version 2")
vim.fn.writefile({ vim.json.encode({ completed = 7 }) }, progress_file)
migrated = progress.load(progress_file, #lessons)
check(migrated.version == 2 and migrated.guided_completed == 7, "legacy progress migrates")
vim.fn.writefile({ "{not-json" }, progress_file)
migrated = progress.load(progress_file, #lessons)
check(migrated.version == 2 and migrated.guided_completed == 0, "malformed progress falls back safely")
vim.fn.writefile({ vim.json.encode({ version = 99 }) }, progress_file)
migrated = progress.load(progress_file, #lessons)
check(migrated.guided_completed == 0, "unsupported progress version falls back safely")
vim.fn.writefile({ vim.json.encode({ version = 2, guided_completed = 1000, skills = {} }) }, progress_file)
migrated = progress.load(progress_file, #lessons)
check(migrated.guided_completed == #lessons, "guided progress is clamped")
local saved = { version = 2, guided_completed = 4, skills = {} }
check(progress.save(progress_file, saved), "progress saves to the requested path")
check(progress.load(progress_file, #lessons).guided_completed == 4, "saved progress reloads")
check(not progress.save("/proc/bonetutor/progress.json", saved), "progress reports an unwritable destination")
local exercises = {
  { id = "word-a", skill = "word", prerequisites = {} },
  { id = "word-b", skill = "word", prerequisites = {} },
  { id = "compound", skill = "compound", prerequisites = { "word" } },
}
local selection = scheduler.next({
  skills = {
    word = { proficiency = 0.2, due_at = 10, last_variant = "word-a" },
    compound = { proficiency = 0.9, due_at = 10 },
  },
}, exercises, 20, 1)
check(selection and selection.skill == "word", "scheduler prioritizes weak skills")
check(selection and selection.id == "word-b", "scheduler avoids the last variant when possible")
selection = scheduler.next({
  skills = { word = { proficiency = 0.9, due_at = 10 } },
}, exercises, 20, 1)
check(selection and selection.skill == "word", "scheduler can select a due review")
selection = scheduler.next({ skills = { word = { proficiency = 0.8, due_at = 10 } } }, exercises, 20, 1)
check(selection and selection.skill == "word", "scheduler blocks compounds without prerequisite mastery")
selection = scheduler.next({
  skills = { word = { proficiency = 0.9, due_at = 100, mastered = true } },
}, exercises, 20, 1)
check(selection and selection.skill == "compound", "scheduler unlocks compounds after mastery")
local catalog = exercise_catalog.list()
check(#catalog >= #lessons, "exercise catalog includes every guided lesson")
local by_id = {}
for _, exercise in ipairs(catalog) do
  by_id[exercise.id] = exercise
  check(type(exercise.skill) == "string", exercise.id .. " has a stable skill")
  check(position_is_valid(exercise.start, exercise.lines), exercise.id .. " has a valid start position")
end
check(by_id.word_forward_variant_02 ~= nil, "word motion has a distinct exercise variant")
local deterministic_a = scheduler.next({ skills = {} }, exercises, 20, 7)
local deterministic_b = scheduler.next({ skills = {} }, exercises, 20, 7)
check(deterministic_a.id == deterministic_b.id, "scheduler selection is deterministic for a seed")
check(
  scheduler.next({ skills = { word = { due_at = 100 } } }, { exercises[1] }, 20, 0) == nil,
  "scheduler returns no exercise when all are not due"
)

check(#lessons == 26, ("expected 26 lessons, got %d"):format(#lessons))

for index, lesson in ipairs(lessons) do
  local label = ("lesson %d (%s)"):format(index, tostring(lesson.title))
  check(type(lesson.group) == "string", label .. " has a group")
  check(type(lesson.title) == "string", label .. " has a title")
  check(type(lesson.goal) == "string", label .. " has a goal")
  check(type(lesson.hint) == "string", label .. " has a hint")
  check(type(lesson.lines) == "table" and #lesson.lines > 0, label .. " has lines")
  check(position_is_valid(lesson.start, lesson.lines), label .. " has a valid start")

  local target = lesson.target
  check(type(target) == "table", label .. " has a target")
  if target and target.cursor then
    check(position_is_valid(target.cursor, lesson.lines), label .. " has a valid cursor target")
  end
  if target and target.lines then
    check(type(target.lines) == "table" and #target.lines > 0, label .. " has target lines")
    for line_index, line in ipairs(target.lines) do
      check(type(line) == "string", ("%s target line %d is a string"):format(label, line_index))
    end
  end
  check(target and (target.cursor or target.lines), label .. " has a cursor or line target")
end

local keys = {
  "h", "l", "j", "k", "w", "b", "e", "3w", "0", "$", "gg", "G",
  "fx", "t:", "/comet<CR>", "%", "dw", "diw", "ciwnew<Esc>", "dd",
  "x", "obeta<Esc>", "A!<Esc>", "yyp", "d$", 'ci"new<Esc>',
}

local function inspect_exercise(index)
  require("bonetutor").start(tostring(index))
  local tab = vim.api.nvim_get_current_tabpage()
  local exercise_win
  local info_buf
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "bonetutor" and not vim.bo[buf].modifiable then
      info_buf = buf
    else
      exercise_win = win
    end
  end
  return exercise_win, info_buf
end

for index, lesson in ipairs(lessons) do
  local exercise_win, info_buf = inspect_exercise(index)
  check(exercise_win ~= nil, ("lesson %d opens an exercise window"):format(index))
  if exercise_win then
    local input = vim.api.nvim_replace_termcodes(keys[index], true, false, true)
    vim.api.nvim_feedkeys(input, "xt", false)
    local actual_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(exercise_win), 0, -1, false)
    local actual_cursor = vim.api.nvim_win_get_cursor(exercise_win)
    check(
      vim.deep_equal(actual_lines, lesson.target.lines or lesson.lines),
      ("lesson %d produces expected buffer contents"):format(index)
    )
    if lesson.target.cursor then
      check(
        actual_cursor[1] == lesson.target.cursor[1] and actual_cursor[2] + 1 == lesson.target.cursor[2],
        ("lesson %d produces expected cursor"):format(index)
      )
    end
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_win_get_buf(exercise_win) })
    vim.wait(1000, function()
      local lines = vim.api.nvim_buf_get_lines(info_buf, 0, -1, false)
      local content = table.concat(lines, "\n")
      return content:find((" %02d/26 "):format(index + 1), 1, true) ~= nil
        or (index == #lessons and content:find("ALL DONE!", 1, true) ~= nil)
    end, 5)
    local panel = table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n")
    if index < #lessons then
      check(
        panel:find((" %02d/26 "):format(index + 1), 1, true) ~= nil,
        ("lesson %d automatically advances after passing"):format(index)
      )
    else
      check(
        panel:find((" %02d/26 "):format(1), 1, true) ~= nil,
        "final lesson automatically wraps to lesson 1"
      )
    end
  end
end
local tutor = require("bonetutor")
tutor.quit()
vim.wait(50)

tutor.start("1")
local tab = vim.api.nvim_get_current_tabpage()
local exercise_buf
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].modifiable then
    exercise_buf = buf
  end
end
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = exercise_buf })
tutor.start("2")
vim.wait(50)
local _, info_buf
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if not vim.bo[buf].modifiable then
    info_buf = buf
  end
end
check(
  not table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n"):find("PASS!", 1, true),
  "queued validation from an earlier lesson cannot pass the next lesson"
)
tutor.start("1")
exercise_buf = nil
info_buf = nil
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].modifiable then
    exercise_buf = buf
  else
    info_buf = buf
  end
end
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = exercise_buf })
tutor.reset()
vim.wait(50)
check(not table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n"):find("PASS!", 1, true),
  "queued validation cannot pass after reset")
check(
  vim.deep_equal(vim.api.nvim_buf_get_lines(exercise_buf, 0, -1, false), lessons[1].lines),
  "reset restores the current lesson's source text"
)
local initial_cursor = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())
check(initial_cursor[1] == lessons[1].start[1] and initial_cursor[2] + 1 == lessons[1].start[2],
  "reset restores the current lesson's starting cursor")
tutor.start(tostring(#lessons))
exercise_buf = nil
info_buf = nil
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].modifiable then
    exercise_buf = buf
  else
    info_buf = buf
  end
end
check(exercise_buf ~= nil and info_buf ~= nil, "final lesson has exercise and info buffers")
local last_key = vim.api.nvim_replace_termcodes(keys[#lessons], true, false, true)
vim.api.nvim_feedkeys(last_key, "xt", false)
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = exercise_buf })
vim.wait(1000, function()
  return table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n"):find("ALL DONE!", 1, true) ~= nil
end, 5)
vim.wait(700)
check(table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n"):find("01/26", 1, true) ~= nil,
  "final lesson returns to lesson 1")
check(vim.deep_equal(vim.api.nvim_buf_get_lines(exercise_buf, 0, -1, false), lessons[1].lines),
  "completing the final lesson wraps around to lesson 1")
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = exercise_buf })
tutor.reset()
vim.wait(50)
check(vim.deep_equal(vim.api.nvim_buf_get_lines(exercise_buf, 0, -1, false), lessons[1].lines),
  "reset after completing the final lesson restores lesson 1")
tutor.quit()
vim.wait(50)
check(not vim.api.nvim_tabpage_is_valid(tab), "quit closes the tutor tab")
check(vim.deep_equal(keymaps_before.n, vim.api.nvim_get_keymap("n")), "normal mappings are unchanged")
check(vim.deep_equal(keymaps_before.i, vim.api.nvim_get_keymap("i")), "insert mappings are unchanged")
check(vim.deep_equal(keymaps_before.v, vim.api.nvim_get_keymap("v")), "visual mappings are unchanged")
check(vim.o.clipboard == clipboard_before, "clipboard option is unchanged")

tutor.start("1")
tab = vim.api.nvim_get_current_tabpage()
exercise_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_delete(exercise_buf, { force = true })
vim.wait(50)
tutor.start("1")
check(vim.api.nvim_get_current_tabpage() ~= tab, "wiping exercise buffer tears down its session")
tutor.quit()

if failures > 0 then
  error(("%d lesson definition check(s) failed"):format(failures))
end

print(("PASS: validated %d lesson definitions"):format(#lessons))

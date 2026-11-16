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
local layouts = require("bonetutor.layouts")
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
check(type(progress.record_attempt) == "function", "progress exposes skill outcome recording")
if progress.record_attempt then
  local tracked = progress.record_attempt(saved, "word_forward", "guided_05", "success", {
    hint_used = true,
    duration_seconds = 17,
  }, 1000)
  local word_record = tracked.skills.word_forward
  check(word_record.attempts == 1 and word_record.successes == 1, "success outcome increments skill counters")
  check(word_record.failures == 0 and word_record.hints == 1, "outcome records failure and hint counters")
  check(word_record.last_practiced == 1000 and word_record.last_variant == "guided_05", "outcome records timestamp and variant")
  check(word_record.recent[1].duration_seconds == 17, "outcome records elapsed duration")
  check(word_record.recent[1].outcome == "success", "outcome history stores the result")
  for attempt = 1, 25 do
    progress.record_attempt(tracked, "word_forward", "guided_05", "failure", {}, 1000 + attempt)
  end
  check(#tracked.skills.word_forward.recent == 20, "skill outcome history is bounded to 20 entries")
end
vim.fn.writefile({ vim.json.encode({
  version = 2,
  guided_completed = 3,
  skills = {
    valid = { attempts = 3, successes = 2, failures = 1, proficiency = 0.6 },
    malformed = "not a skill record",
  },
}) }, progress_file)
migrated = progress.load(progress_file, #lessons)
check(migrated.skills.valid and migrated.skills.valid.attempts == 3, "valid skill records load")
check(migrated.skills.malformed == nil, "malformed skill records are discarded")
dofile("plugin/bonetutor.lua")
check(vim.fn.exists(":BoneTutorPractice") == 2, "adaptive practice command is registered")
check(vim.fn.exists(":BoneTutorDaily") == 2, "daily challenge command is registered")
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
check(type(scheduler.daily) == "function", "scheduler exposes daily sequence selection")
if scheduler.daily then
  local daily_exercises = {
    { id = "review_word", skill = "word", prerequisites = {} },
    { id = "review_line", skill = "line", prerequisites = {} },
    { id = "new_alpha", skill = "alpha", prerequisites = {} },
    { id = "new_beta", skill = "beta", prerequisites = {} },
    { id = "new_gamma", skill = "gamma", prerequisites = {} },
    { id = "locked", skill = "locked", prerequisites = { "missing" } },
  }
  local daily_state = {
    skills = {
      word = { proficiency = 0.4, due_at = 10 },
      line = { proficiency = 0.7, due_at = 20 },
    },
  }
  local daily_a = scheduler.daily(daily_state, daily_exercises, 30, 11, 5)
  local daily_b = scheduler.daily(daily_state, daily_exercises, 30, 11, 5)
  local function exercise_ids(sequence)
    return vim.tbl_map(function(exercise)
      return exercise.id
    end, sequence)
  end
  check(
    vim.deep_equal(exercise_ids(daily_a), exercise_ids(daily_b)),
    "daily selection is stable for the same state, time, seed, and limit"
  )
  check(daily_a[1] and daily_a[1].skill == "word", "daily selection puts due reviews first")
  local new_skills = {}
  for _, exercise in ipairs(daily_a) do
    if not daily_state.skills[exercise.skill] then
      new_skills[exercise.skill] = true
    end
  end
  check(vim.tbl_count(new_skills) <= 2, "daily selection includes at most two new skills")
  check(#daily_a <= 5, "daily selection respects its exercise limit")
  local future = scheduler.daily(
    { skills = { later = { proficiency = 0.8, due_at = 200 } } },
    { { id = "later_review", skill = "later", prerequisites = {} } },
    100,
    1,
    5
  )
  check(future[1] and future[1].id == "later_review",
    "daily selection falls back to the earliest future review when nothing is due")
  check(
    #scheduler.daily(
      { skills = {} },
      { { id = "locked", skill = "locked", prerequisites = { "unknown" } } },
      100,
      1,
      5
    ) == 0,
    "daily selection returns an empty sequence when every exercise is prerequisite-locked"
  )
end
local catalog = exercise_catalog.list()
check(
  vim.deep_equal(layouts.standard.layers[1].rows, {
    { "j", "d", "u", "a", "x" },
    { "p", "h", "l", "m", "w", "q" },
    { "c", "t", "i", "e", "o" },
    { "b", "n", "r", "s", "g", "ß" },
    { "f", "v", "ü", "ä", "ö" },
    { "y", "z", ",", ".", "k" },
  }),
  "standard Bone layer 1 exposes the documented left/right letter rows"
)
local symbol_locations = {}
for _, location in ipairs(layouts.describe({ "h", "$", "/", ":", "%" }, layouts.standard)) do
  symbol_locations[location.key] = location
end
check(symbol_locations.h and symbol_locations.h.layer == 1, "letter lookup identifies layer 1")
check(symbol_locations["$"] and symbol_locations["$"].layer == 3, "dollar lookup identifies Mod3")
check(symbol_locations["/"] and symbol_locations["/"].layer == 3, "slash lookup identifies Mod3")
check(symbol_locations[":"] and symbol_locations[":"].layer == 3, "colon lookup identifies Mod3")
check(symbol_locations["%"] and symbol_locations["%"].layer == 3, "percent lookup identifies Mod3")
check(#layouts.describe({}, layouts.standard) == 0, "empty key list has no highlights")
check(#layouts.describe({ "unknown-key" }, layouts.standard) == 0, "unknown key has no highlight")
local displayed_locations = {}
for _, location in ipairs(layouts.describe({ "h", "$" }, layouts.standard)) do
  displayed_locations[location.key] = location
end
check(
  displayed_locations.h.row == 1
    and displayed_locations.h.hand == "right"
    and displayed_locations.h.column == 2,
  "top-row h lookup includes its layer-1 hand and location"
)
check(displayed_locations["$"].modifier == "Mod3",
  "symbol lookup names the logical modifier layer")
check(#catalog >= #lessons, "exercise catalog includes every guided lesson")
local by_id = {}
for _, exercise in ipairs(catalog) do
  by_id[exercise.id] = exercise
  check(type(exercise.skill) == "string", exercise.id .. " has a stable skill")
  check(position_is_valid(exercise.start, exercise.lines), exercise.id .. " has a valid start position")
  if exercise.id == "guided_10" then
    check(vim.deep_equal(exercise.keys, { "$" }), "end-of-line exercise declares the symbol key it teaches")
  end
end
check(by_id.word_forward_variant_02 ~= nil, "word motion has a distinct exercise variant")
check(
  #catalog > #lessons,
  "exercise catalog includes additional challenges beyond the guided lessons"
)
local language_exercises = {}
for _, exercise in ipairs(catalog) do
  if exercise.language == "rust" or exercise.language == "python" then
    language_exercises[exercise.language] = language_exercises[exercise.language] or {}
    table.insert(language_exercises[exercise.language], exercise)
  end
end
check(language_exercises.rust and #language_exercises.rust >= 2, "catalog includes multiple Rust exercises")
check(language_exercises.python and #language_exercises.python >= 2, "catalog includes multiple Python exercises")
for language, language_catalog in pairs(language_exercises) do
  for _, exercise in ipairs(language_catalog) do
    check(exercise.target and exercise.target.lines, exercise.id .. " has deterministic buffer validation")
    check(exercise.prompt and exercise.prompt ~= "", exercise.id .. " has a task prompt")
    check(exercise.hint and exercise.hint ~= "", exercise.id .. " has a command hint")
    check(
      #exercise.target.lines == #exercise.lines,
      exercise.id .. " preserves the snippet's line count"
    )
    local commands = {
      guided_27 = "ciwsum<Esc>j0f=wciwsum<Esc>",
      guided_28 = "dawx",
      guided_29 = "ciwusername<Esc>j0f{wciwusername<Esc>",
      guided_30 = "ciwconfig_path<Esc>",
    }
    local command = commands[exercise.id]
    check(command ~= nil, exercise.id .. " has an executable command test")
    if command then
      vim.cmd("enew!")
      vim.bo.buftype = "nofile"
      vim.bo.bufhidden = "wipe"
      vim.api.nvim_buf_set_lines(0, 0, -1, false, exercise.lines)
      vim.api.nvim_win_set_cursor(0, { exercise.start[1], exercise.start[2] - 1 })
      local input = vim.api.nvim_replace_termcodes(command, true, false, true)
      vim.api.nvim_feedkeys(input, "xt", false)
      check(
        vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), exercise.target.lines),
        exercise.id .. " reaches its target using real Vim commands"
      )
      vim.bo.modified = false
    end
  end
end
local deterministic_a = scheduler.next({ skills = {} }, exercises, 20, 7)
local deterministic_b = scheduler.next({ skills = {} }, exercises, 20, 7)
check(deterministic_a.id == deterministic_b.id, "scheduler selection is deterministic for a seed")
check(
  scheduler.next({ skills = { word = { due_at = 100 } } }, { exercises[1] }, 20, 0) == nil,
  "scheduler returns no exercise when all are not due"
)

check(#lessons == 30, ("expected 30 lessons, got %d"):format(#lessons))
local guided_languages = {}
for _, lesson in ipairs(lessons) do
  if lesson.language then
    guided_languages[lesson.language] = (guided_languages[lesson.language] or 0) + 1
  end
end
check(guided_languages.rust and guided_languages.rust >= 2, "guided sequence contains multiple Rust exercises")
check(guided_languages.python and guided_languages.python >= 2, "guided sequence contains multiple Python exercises")

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
  "ciwsum<Esc>j0f=wciwsum<Esc>", "dawx",
  "ciwusername<Esc>j0f{wciwusername<Esc>", "ciwconfig_path<Esc>",
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
      return content:find((" %02d/%02d "):format(index + 1, #lessons), 1, true) ~= nil
        or (index == #lessons and content:find("ALL DONE!", 1, true) ~= nil)
    end, 5)
    local panel = table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n")
    if index < #lessons then
      check(
        panel:find((" %02d/%02d "):format(index + 1, #lessons), 1, true) ~= nil,
        ("lesson %d automatically advances after passing"):format(index)
      )
    else
      check(
        panel:find((" %02d/%02d "):format(1, #lessons), 1, true) ~= nil,
        "final lesson automatically wraps to lesson 1"
      )
    end
  end
end
local tutor = require("bonetutor")
tutor.quit()
vim.wait(50)

tutor.start("10")
tutor.keys()
local _, key_panel_buf = inspect_exercise(10)
local key_panel = table.concat(vim.api.nvim_buf_get_lines(key_panel_buf, 0, -1, false), "\n")
check(key_panel:find("Mod3", 1, true) ~= nil, "keyboard panel identifies the logical symbol layer")
check(key_panel:find("[$]", 1, true) ~= nil, "keyboard panel highlights keys used in the current command")
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
  return table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n")
    :find(("01/%02d"):format(#lessons), 1, true) ~= nil
end, 5)
check(table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n"):find(("01/%02d"):format(#lessons), 1, true) ~= nil,
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

if vim.fn.exists(":BoneTutorPractice") == 2 then
vim.cmd("BoneTutorPractice")
local adaptive_tab = vim.api.nvim_get_current_tabpage()
exercise_buf = nil
info_buf = nil
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(adaptive_tab)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].modifiable then
    exercise_buf = buf
  else
    info_buf = buf
  end
end
check(exercise_buf ~= nil and info_buf ~= nil, "adaptive command opens the practice session")
local adaptive_panel = table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n")
local adaptive_id = adaptive_panel:match("Adaptive Practice  ·  ([%w_%-]+)")
local adaptive_exercise = by_id[adaptive_id]
check(adaptive_exercise ~= nil, "adaptive session displays its selected exercise")
if adaptive_exercise then
  tutor.reset()
  local stored_path = vim.fn.stdpath("state") .. "/bonetutor.json"
  local after_reset = progress.load(stored_path, #lessons)
  local after_reset_record = after_reset.skills[adaptive_exercise.skill]
  check(
    after_reset_record and after_reset_record.failures >= 1,
    "resetting an adaptive exercise records a failed attempt"
  )
  local previous_successes = after_reset_record and after_reset_record.successes or 0
  local previous_hints = after_reset_record and after_reset_record.hints or 0
  tutor.hint()
  vim.api.nvim_buf_set_lines(exercise_buf, 0, -1, false, adaptive_exercise.target.lines or adaptive_exercise.lines)
  if adaptive_exercise.target.cursor then
    vim.api.nvim_win_set_cursor(0, {
      adaptive_exercise.target.cursor[1],
      adaptive_exercise.target.cursor[2] - 1,
    })
  end
  vim.api.nvim_exec_autocmds("TextChanged", { buffer = exercise_buf })
  vim.wait(1000, function()
    local current = progress.load(stored_path, #lessons).skills[adaptive_exercise.skill]
    return current and current.successes > previous_successes
  end, 5)
  local after_success = progress.load(stored_path, #lessons).skills[adaptive_exercise.skill]
  check(after_success and after_success.successes > previous_successes, "passing an adaptive exercise records success")
  check(after_success and after_success.hints > previous_hints, "adaptive attempt records hint usage")
  check(
    after_success and after_success.recent[#after_success.recent].duration_seconds >= 0,
    "adaptive attempt records elapsed time"
  )
  check(
    after_success and after_success.recent[#after_success.recent].raw_keystrokes == nil,
    "adaptive history stores no raw keystrokes"
  )
end
tutor.quit()
vim.wait(50)
end

local daily_state = { version = 2, guided_completed = 0, skills = {} }
for _, exercise in ipairs(catalog) do
  if not daily_state.skills[exercise.skill] then
    daily_state.skills[exercise.skill] = {
      attempts = 1,
      successes = 1,
      failures = 0,
      proficiency = 0.9,
      due_at = os.time() + 100000000,
    }
  end
end
daily_state.skills.move_left.due_at = 0
progress.save(vim.fn.stdpath("state") .. "/bonetutor.json", daily_state)

local original_notify = vim.notify
local daily_notification
vim.notify = function(message, level, opts)
  if tostring(message):find("Daily", 1, true) then
    daily_notification = tostring(message)
    return
  end
  return original_notify(message, level, opts)
end
if vim.fn.exists(":BoneTutorDaily") == 2 then
  vim.cmd("BoneTutorDaily")
  local daily_tab = vim.api.nvim_get_current_tabpage()
  exercise_buf = nil
  info_buf = nil
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(daily_tab)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].modifiable then
      exercise_buf = buf
    else
      info_buf = buf
    end
  end
  check(exercise_buf ~= nil and info_buf ~= nil, "daily command opens the existing tutor panes")
  local initial_daily_panel = table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n")
  check(initial_daily_panel:find("Daily Challenge", 1, true) ~= nil, "daily session identifies its mode")
  vim.api.nvim_win_set_cursor(0, { 1, lessons[1].target.cursor[2] - 1 })
  vim.api.nvim_exec_autocmds("CursorMoved", { buffer = exercise_buf })
  vim.wait(1000, function()
    return table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n")
      :find("Daily complete", 1, true) ~= nil
  end, 5)
  local completion_panel = table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n")
  check(completion_panel:find("1 passed", 1, true) ~= nil, "daily completion summary reports passes")
  check(completion_panel:find("0 failed", 1, true) ~= nil, "daily completion summary reports failures")
  tutor.quit()
  check(
    daily_notification and daily_notification:find("1 passed", 1, true) ~= nil,
    "quitting a daily session reports its session summary"
  )
  vim.wait(50)
end

local interruption_state = { version = 2, guided_completed = 0, skills = {} }
for _, exercise in ipairs(catalog) do
  if not interruption_state.skills[exercise.skill] then
    interruption_state.skills[exercise.skill] = {
      attempts = 1,
      successes = 1,
      failures = 0,
      proficiency = 0.9,
      due_at = os.time() + 100000000,
    }
  end
end
interruption_state.skills.move_left.due_at = 0
progress.save(vim.fn.stdpath("state") .. "/bonetutor.json", interruption_state)
tutor.practice()
tutor.daily()
local interruption_tab = vim.api.nvim_get_current_tabpage()
exercise_buf = nil
info_buf = nil
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(interruption_tab)) do
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].modifiable then
    exercise_buf = buf
  else
    info_buf = buf
  end
end
vim.api.nvim_win_set_cursor(0, { 1, lessons[1].target.cursor[2] - 1 })
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = exercise_buf })
vim.wait(1000, function()
  local panel = table.concat(vim.api.nvim_buf_get_lines(info_buf, 0, -1, false), "\n")
  return panel:find("Daily complete", 1, true) ~= nil
end, 5)
local recorded_interruption = progress.load(vim.fn.stdpath("state") .. "/bonetutor.json", #lessons)
check(
  recorded_interruption.skills.move_left.failures == 1,
  "starting a daily challenge preserves the abandoned practice failure after a pass"
)
tutor.quit()
vim.wait(50)
vim.notify = original_notify

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

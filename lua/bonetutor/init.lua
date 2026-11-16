local M = {}
local lessons = require("bonetutor.lessons")
local progress = require("bonetutor.progress")
local catalog = require("bonetutor.exercises").list()
local scheduler = require("bonetutor.scheduler")
local layouts = require("bonetutor.layouts")
local session

local function progress_path()
  return vim.fn.stdpath("state") .. "/bonetutor.json"
end

local function read_state()
  return progress.load(progress_path(), #lessons)
end

local function save_progress(n)
  session.state.guided_completed = n
  local ok = progress.save(progress_path(), session.state)
  if not ok then
    vim.notify("BoneTutor: could not save progress", vim.log.levels.WARN)
  end
end

local function save_state()
  if not progress.save(progress_path(), session.state) then
    vim.notify("BoneTutor: could not save progress", vim.log.levels.WARN)
  end
end

local function valid()
  return session
    and vim.api.nvim_tabpage_is_valid(session.tab)
    and vim.api.nvim_win_is_valid(session.exercise_win)
    and vim.api.nvim_win_is_valid(session.info_win)
    and vim.api.nvim_buf_is_valid(session.exercise_buf)
    and vim.api.nvim_buf_is_valid(session.info_buf)
end

local function render()
  if not valid() then
    return
  end

  local lesson = session.current_lesson
  local status
  if session.finished then
    status = "ALL DONE!  :BoneTutorQuit closes the training tab."
  elseif session.passed then
    status = "PASS!  Continue with :BoneTutorNext"
  else
    status = "Try it below using normal Vim keys. Then check the result here."
  end

  local heading
  if session.mode == "practice" then
    heading = ("BoneTutor Adaptive Practice  ·  %s"):format(session.exercise.id)
  else
    heading = ("BoneTutor  %02d/%02d   [completed: %02d/%02d]"):format(
      session.index,
      #lessons,
      session.completed,
      #lessons
    )
  end
  local lines = {
    heading,
    lesson.group .. "  /  " .. lesson.title,
    "Goal: " .. lesson.goal,
    status,
    "",
    "Commands: :BoneTutorHint  :BoneTutorReset  :BoneTutorNext  :BoneTutorQuit",
    "          :BoneTutorKeys  :BoneTutorPrev  :BoneTutor <number>",
  }
  if session.hint then
    lines[#lines + 1] = "Hint: " .. lesson.hint
  end
  if session.show_keys then
    local highlighted = {}
    for _, location in ipairs(layouts.describe(lesson.keys, layouts.standard)) do
      highlighted[location.key] = true
    end
    local function row(keys)
      local cells = {}
      for _, key in ipairs(keys) do
        cells[#cells + 1] = highlighted[key] and ("[" .. key .. "]") or key
      end
      return table.concat(cells, " ")
    end
    vim.list_extend(lines, { "", "Bone layer 1 (logical keys; NOT QWERTZ):" })
    for index = 1, #layouts.standard.layers[1].rows, 2 do
      lines[#lines + 1] = "  " .. row(layouts.standard.layers[1].rows[index])
        .. "  |  " .. row(layouts.standard.layers[1].rows[index + 1])
    end
    lines[#lines + 1] = "Mod3 symbols (logical layer; physical modifier placement varies):"
    for _, symbol_row in ipairs(layouts.standard.layers[3].rows) do
      lines[#lines + 1] = "  " .. row(symbol_row)
    end
  end

  vim.bo[session.info_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.info_buf, 0, -1, false, lines)
  vim.bo[session.info_buf].modified = false
  vim.bo[session.info_buf].modifiable = false
  local desired_height = math.min(#lines, math.max(5, vim.o.lines - 8))
  pcall(vim.api.nvim_win_set_height, session.info_win, desired_height)
end

local function matches(lesson)
  if vim.api.nvim_get_mode().mode:sub(1, 1) ~= "n" then
    return false
  end
  local target = lesson.target
  if target.cursor then
    local position = vim.api.nvim_win_get_cursor(session.exercise_win)
    if position[1] ~= target.cursor[1] or position[2] + 1 ~= target.cursor[2] then
      return false
    end
  end
  if target.lines then
    local lines = vim.api.nvim_buf_get_lines(session.exercise_buf, 0, -1, false)
    if not vim.deep_equal(lines, target.lines) then
      return false
    end
  end
  return true
end

local load_lesson
local load_practice

local function record_attempt(outcome)
  if not session or session.attempt_recorded or not session.skill then
    return
  end
  session.state = progress.record_attempt(
    session.state,
    session.skill,
    session.exercise.id,
    outcome,
    {
      hint_used = session.hints_used > 0,
      duration_seconds = math.max(0, os.time() - session.started_at),
    },
    os.time()
  )
  session.attempt_recorded = true
  save_state()
end

local function choose_practice()
  session.selection_count = session.selection_count + 1
  local now = os.time()
  local seed = session.selection_count
  local selected = scheduler.next(session.state, catalog, now, seed)
  if not selected then
    -- Reviews that are not due yet are still usable when there are no due tasks.
    selected = scheduler.next(session.state, catalog, math.huge, seed)
  end
  if not selected then
    -- Keep practice available even when every compound skill is still locked.
    for _, exercise in ipairs(catalog) do
      if #(exercise.prerequisites or {}) == 0 then
        selected = exercise
        break
      end
    end
  end
  return selected or catalog[1]
end

local function check(generation)
  if not valid() or session.generation ~= generation or session.finished then
    return
  end
  if vim.api.nvim_get_current_buf() ~= session.exercise_buf then
    return
  end

  local passed = matches(session.current_lesson)
  if passed then
    record_attempt("success")
    if session.mode == "guided" and session.index == session.completed + 1 then
      -- Track the completed PREFIX, not the highest arbitrary lesson jump.
      session.completed = session.index
      save_progress(session.completed)
    end
  end
  if passed ~= session.passed then
    session.passed = passed
    render()
    if passed then
      local completed_index = session.index
      vim.defer_fn(function()
        if not valid()
          or session.generation ~= generation
          or session.index ~= completed_index
          or not session.passed
        then
          return
        end
        if session.mode == "practice" then
          load_practice(choose_practice())
        else
          load_lesson(completed_index % #lessons + 1)
        end
      end, 600)
    end
  end
end

local function install_watcher()
  session.augroup = vim.api.nvim_create_augroup("BoneTutor", { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = session.augroup,
    buffer = session.exercise_buf,
    callback = function()
      local generation = session and session.generation
      if generation then
        vim.schedule(function()
          check(generation)
        end)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = session.augroup,
    buffer = session.exercise_buf,
    callback = function()
      -- This also handles a manually closed tutorial tab.
      local closing = session
      vim.schedule(function()
        if session == closing then
          session = nil
          pcall(vim.api.nvim_del_augroup_by_name, "BoneTutor")
        end
      end)
    end,
  })
end

local function setup_buffer(buf, writable)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "bonetutor"
  vim.bo[buf].modifiable = writable
end

local function setup_window(win, is_info)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = not is_info
  if is_info then
    vim.wo[win].winfixheight = true
  end
end

load_lesson = function(index)
  session.mode = "guided"
  session.index = index
  session.exercise = catalog[index]
  session.current_lesson = lessons[index]
  session.skill = session.exercise.skill
  session.passed = false
  session.finished = false
  session.hint = false
  session.hints_used = 0
  session.started_at = os.time()
  session.attempt_recorded = false
  session.generation = session.generation + 1

  local lesson = lessons[index]
  vim.bo[session.exercise_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.exercise_buf, 0, -1, false, lesson.lines)
  vim.bo[session.exercise_buf].modified = false
  vim.api.nvim_set_current_win(session.exercise_win)
  vim.api.nvim_win_set_cursor(session.exercise_win, { lesson.start[1], lesson.start[2] - 1 })
  render()
end

load_practice = function(exercise)
  session.mode = "practice"
  session.exercise = exercise
  session.index = session.selection_count
  session.skill = exercise.skill
  session.current_lesson = {
    group = "Adaptive practice",
    title = exercise.id,
    goal = exercise.prompt,
    hint = exercise.hint,
    lines = exercise.lines,
    start = exercise.start,
    target = exercise.target,
    keys = exercise.keys,
  }
  session.passed = false
  session.finished = false
  session.hint = false
  session.hints_used = 0
  session.started_at = os.time()
  session.attempt_recorded = false
  session.generation = session.generation + 1
  vim.bo[session.exercise_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.exercise_buf, 0, -1, false, exercise.lines)
  vim.bo[session.exercise_buf].modified = false
  vim.api.nvim_set_current_win(session.exercise_win)
  vim.api.nvim_win_set_cursor(session.exercise_win, { exercise.start[1], exercise.start[2] - 1 })
  render()
end

local function open_session()
  local state = read_state()
  vim.cmd("tabnew")
  local tab = vim.api.nvim_get_current_tabpage()
  local exercise_win = vim.api.nvim_get_current_win()
  local exercise_buf = vim.api.nvim_get_current_buf()
  setup_buffer(exercise_buf, true)
  setup_window(exercise_win, false)

  vim.cmd("topleft 8new")
  local info_win = vim.api.nvim_get_current_win()
  local info_buf = vim.api.nvim_get_current_buf()
  setup_buffer(info_buf, false)
  setup_window(info_win, true)

  session = {
    tab = tab,
    exercise_buf = exercise_buf,
    exercise_win = exercise_win,
    info_buf = info_buf,
    info_win = info_win,
    index = 1,
    completed = state.guided_completed,
    state = state,
    selection_count = 0,
    generation = 0,
    passed = false,
    hint = false,
    hints_used = 0,
    show_keys = false,
    finished = false,
    started_at = os.time(),
  }
  install_watcher()
end

function M.start(argument)
  local number
  if argument and argument ~= "" then
    number = tonumber(argument)
    if not number or number % 1 ~= 0 or number < 1 or number > #lessons then
      vim.notify(("BoneTutor: choose a lesson from 1 to %d"):format(#lessons), vim.log.levels.ERROR)
      return
    end
  end

  if valid() then
    vim.api.nvim_set_current_tabpage(session.tab)
    if number then
      load_lesson(number)
    else
      vim.api.nvim_set_current_win(session.exercise_win)
    end
    return
  end

  open_session()
  load_lesson(number or math.min(session.completed + 1, #lessons))
end

function M.practice()
  if not valid() then
    open_session()
  else
    if not session.passed then
      record_attempt("failure")
    end
    vim.api.nvim_set_current_tabpage(session.tab)
  end
  session.state = read_state()
  session.completed = session.state.guided_completed
  session.selection_count = 0
  load_practice(choose_practice())
end

local function active()
  if not valid() then
    vim.notify("BoneTutor: start with :BoneTutor", vim.log.levels.WARN)
    return false
  end
  vim.api.nvim_set_current_tabpage(session.tab)
  return true
end

function M.next()
  if not active() then
    return
  end
  if session.finished then
    M.quit()
  elseif not session.passed then
    vim.notify("BoneTutor: complete the goal before advancing (or :BoneTutor <number>)", vim.log.levels.INFO)
  else
    if session.mode == "practice" then
      load_practice(choose_practice())
    else
      load_lesson(session.index % #lessons + 1)
    end
  end
end

function M.prev()
  if active() then
    load_lesson(math.max(1, session.index - 1))
  end
end

function M.reset()
  if active() then
    if not session.passed then
      record_attempt("failure")
    end
    if session.mode == "practice" then
      load_practice(session.exercise)
    else
      load_lesson(session.index)
    end
  end
end

function M.hint()
  if active() then
    session.hint = not session.hint
    if session.hint then
      session.hints_used = session.hints_used + 1
    end
    render()
  end
end

function M.keys()
  if active() then
    session.show_keys = not session.show_keys
    render()
  end
end

function M.quit()
  if not active() then
    return
  end
  -- Our buffers contain disposable drills, not user files. Leave any other
  -- windows in the tab to Neovim's normal unsaved-changes protection.
  if session.mode == "practice" and not session.passed then
    record_attempt("failure")
  end
  vim.bo[session.exercise_buf].modified = false
  vim.bo[session.info_buf].modified = false
  local ok, err = pcall(vim.cmd, "tabclose")
  if not ok then
    vim.notify("BoneTutor: could not close tab: " .. tostring(err), vim.log.levels.WARN)
  end
end

function M.lesson_count()
  return #lessons
end

return M

local M = {}
local lessons = require("bonetutor.lessons")
local progress = require("bonetutor.progress")
local session

local function progress_path()
  return vim.fn.stdpath("state") .. "/bonetutor.json"
end

local function read_progress()
  return progress.load(progress_path(), #lessons).guided_completed
end

local function save_progress(n)
  local state = progress.load(progress_path(), #lessons)
  state.guided_completed = n
  local ok = progress.save(progress_path(), state)
  if not ok then
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

  local lesson = lessons[session.index]
  local status
  if session.finished then
    status = "ALL DONE!  :BoneTutorQuit closes the training tab."
  elseif session.passed then
    status = "PASS!  Continue with :BoneTutorNext"
  else
    status = "Try it below using normal Vim keys. Then check the result here."
  end

  local lines = {
    ("BoneTutor  %02d/%02d   [completed: %02d/%02d]"):format(session.index, #lessons, session.completed, #lessons),
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
    vim.list_extend(lines, {
      "",
      "Bone / layer 1 (physical left | right; NOT QWERTZ):",
      "  j d u a x  |  p h l m w q",
      "  c t i e o  |  b n r s g ß",
      "  f v ü ä ö  |  y z , . k",
    })
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

local function check(generation)
  if not valid() or session.generation ~= generation or session.finished then
    return
  end
  if vim.api.nvim_get_current_buf() ~= session.exercise_buf then
    return
  end

  local passed = matches(lessons[session.index])
  -- Track the completed PREFIX, not the highest arbitrary lesson jump.
  if passed and session.index == session.completed + 1 then
    session.completed = session.index
    save_progress(session.completed)
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
        load_lesson(completed_index % #lessons + 1)
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
  session.index = index
  session.passed = false
  session.finished = false
  session.hint = false
  session.generation = session.generation + 1

  local lesson = lessons[index]
  vim.bo[session.exercise_buf].modifiable = true
  vim.api.nvim_buf_set_lines(session.exercise_buf, 0, -1, false, lesson.lines)
  vim.bo[session.exercise_buf].modified = false
  vim.api.nvim_set_current_win(session.exercise_win)
  vim.api.nvim_win_set_cursor(session.exercise_win, { lesson.start[1], lesson.start[2] - 1 })
  render()
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

  local completed = read_progress()
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
    completed = completed,
    generation = 0,
    passed = false,
    hint = false,
    show_keys = false,
    finished = false,
  }
  install_watcher()
  load_lesson(number or math.min(completed + 1, #lessons))
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
    load_lesson(session.index % #lessons + 1)
  end
end

function M.prev()
  if active() then
    load_lesson(math.max(1, session.index - 1))
  end
end

function M.reset()
  if active() then
    load_lesson(session.index)
  end
end

function M.hint()
  if active() then
    session.hint = not session.hint
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

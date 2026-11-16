local M = {}

local function empty_state()
  return { version = 2, guided_completed = 0, skills = {} }
end

local function clamp_completed(value, lesson_count)
  if type(value) ~= "number" then
    return 0
  end
  return math.max(0, math.min(lesson_count, math.floor(value)))
end

local function finite_number(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function nonnegative_integer(value)
  if not finite_number(value) then
    return 0
  end
  return math.max(0, math.floor(value))
end

local function sanitize_recent(recent)
  local result = {}
  if type(recent) ~= "table" then
    return result
  end
  local first = math.max(1, #recent - 19)
  for index = first, #recent do
    local attempt = recent[index]
    if type(attempt) == "table"
      and (attempt.outcome == "success" or attempt.outcome == "failure")
      and finite_number(attempt.at)
      and type(attempt.exercise_id) == "string"
    then
      result[#result + 1] = {
        outcome = attempt.outcome,
        at = attempt.at,
        exercise_id = attempt.exercise_id,
        hint_used = attempt.hint_used == true,
        duration_seconds = nonnegative_integer(attempt.duration_seconds),
      }
      if #result == 20 then
        break
      end
    end
  end
  return result
end

local function sanitize_skills(skills)
  local result = {}
  if type(skills) ~= "table" then
    return result
  end
  for skill, record in pairs(skills) do
    if type(skill) == "string" and type(record) == "table" then
      local attempts = nonnegative_integer(record.attempts)
      local successes = math.min(attempts, nonnegative_integer(record.successes))
      local failures = math.min(attempts - successes, nonnegative_integer(record.failures))
      local proficiency = finite_number(record.proficiency) and math.max(0, math.min(1, record.proficiency))
        or (successes + 1) / (attempts + 2)
      result[skill] = {
        attempts = attempts,
        successes = successes,
        failures = failures,
        hints = nonnegative_integer(record.hints),
        proficiency = proficiency,
        due_at = finite_number(record.due_at) and record.due_at or nil,
        last_practiced = finite_number(record.last_practiced) and record.last_practiced or nil,
        last_variant = type(record.last_variant) == "string" and record.last_variant or nil,
        recent = sanitize_recent(record.recent),
      }
    end
  end
  return result
end

function M.load(path, lesson_count)
  if vim.fn.filereadable(path) == 0 then
    return empty_state()
  end

  local ok, decoded = pcall(function()
    return vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
  end)
  if not ok or type(decoded) ~= "table" then
    return empty_state()
  end

  if decoded.version == nil then
    return {
      version = 2,
      guided_completed = clamp_completed(decoded.completed, lesson_count),
      skills = {},
    }
  end

  if decoded.version ~= 2 then
    return empty_state()
  end

  return {
    version = 2,
    guided_completed = clamp_completed(decoded.guided_completed, lesson_count),
    skills = sanitize_skills(decoded.skills),
  }
end

function M.record_attempt(state, skill, exercise_id, outcome, metadata, now)
  if type(skill) ~= "string"
    or skill == ""
    or type(exercise_id) ~= "string"
    or (outcome ~= "success" and outcome ~= "failure")
    or not finite_number(now)
  then
    return state
  end
  if type(state.skills) ~= "table" then
    state.skills = {}
  end
  metadata = type(metadata) == "table" and metadata or {}
  local record = state.skills[skill]
  if type(record) ~= "table" then
    record = {
      attempts = 0,
      successes = 0,
      failures = 0,
      hints = 0,
      proficiency = 0.5,
      recent = {},
    }
    state.skills[skill] = record
  end

  record.attempts = nonnegative_integer(record.attempts) + 1
  record.successes = nonnegative_integer(record.successes)
  record.failures = nonnegative_integer(record.failures)
  record.hints = nonnegative_integer(record.hints)
  if outcome == "success" then
    record.successes = record.successes + 1
  else
    record.failures = record.failures + 1
  end
  if metadata.hint_used == true then
    record.hints = record.hints + 1
  end

  record.proficiency = (record.successes + 1) / (record.attempts + 2)
  record.last_practiced = now
  record.last_variant = exercise_id
  record.recent = sanitize_recent(record.recent)
  record.recent[#record.recent + 1] = {
    outcome = outcome,
    at = now,
    exercise_id = exercise_id,
    hint_used = metadata.hint_used == true,
    duration_seconds = nonnegative_integer(metadata.duration_seconds),
  }
  while #record.recent > 20 do
    table.remove(record.recent, 1)
  end

  local review_delay = 3600
  if record.proficiency >= 0.8 then
    review_delay = 7 * 24 * 60 * 60
  elseif record.proficiency >= 0.5 then
    review_delay = 24 * 60 * 60
  end
  record.due_at = now + review_delay
  return state
end

function M.save(path, state)
  local ok = pcall(function()
    local directory = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(directory, "p")
    local result = vim.fn.writefile({ vim.json.encode(state) }, path)
    if result ~= 0 then
      error("writefile failed")
    end
  end)
  return ok
end

return M

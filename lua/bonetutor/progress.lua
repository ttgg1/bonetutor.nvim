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
    skills = type(decoded.skills) == "table" and decoded.skills or {},
  }
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

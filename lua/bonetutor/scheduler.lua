local M = {}

local function proficiency(state, skill)
  local record = state.skills and state.skills[skill]
  return record and record.proficiency or 0
end

local function eligible(state, exercise)
  for _, prerequisite in ipairs(exercise.prerequisites or {}) do
    if proficiency(state, prerequisite) < 0.85 then
      return false
    end
  end
  return true
end

function M.next(state, exercises, now, seed)
  local candidates = {}
  for _, exercise in ipairs(exercises) do
    if eligible(state, exercise) then
      local record = state.skills and state.skills[exercise.skill]
      local due = not record or not record.due_at or record.due_at <= now
      if due then
        candidates[#candidates + 1] = exercise
      end
    end
  end
  if #candidates == 0 then
    return nil
  end

  local best_score = -1
  local best = {}
  for _, exercise in ipairs(candidates) do
    local record = state.skills and state.skills[exercise.skill]
    local score = 1 - proficiency(state, exercise.skill)
    if not record then
      score = score + 0.1
    end
    if record and record.due_at and record.due_at <= now then
      score = score + 1
    end
    if record and record.last_variant == exercise.id then
      score = score - 0.25
    end
    if score > best_score then
      best_score = score
      best = { exercise }
    elseif score == best_score then
      best[#best + 1] = exercise
    end
  end
  table.sort(best, function(left, right)
    return left.id < right.id
  end)
  local offset = (math.floor(seed or 0) % #best) + 1
  return best[offset]
end

return M

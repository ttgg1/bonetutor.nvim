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

function M.daily(state, exercises, now, seed, limit)
  state = state or {}
  now = tonumber(now) or os.time()
  seed = math.floor(tonumber(seed) or 0)
  limit = math.max(0, math.floor(tonumber(limit) or 5))
  if limit == 0 then
    return {}
  end

  local buckets = { due = {}, new = {}, future = {} }
  for _, exercise in ipairs(exercises or {}) do
    if eligible(state, exercise) then
      local skill = exercise.skill
      local record = state.skills and state.skills[skill]
      local bucket
      if not record then
        bucket = buckets.new
      elseif not record.due_at or record.due_at <= now then
        bucket = buckets.due
      else
        bucket = buckets.future
      end
      bucket[skill] = bucket[skill] or {}
      bucket[skill][#bucket[skill] + 1] = exercise
    end
  end

  local function candidates_for(groups)
    local candidates = {}
    for skill, variants in pairs(groups) do
      table.sort(variants, function(left, right)
        return left.id < right.id
      end)
      local record = state.skills and state.skills[skill]
      if record and record.last_variant and #variants > 1 then
        for index, exercise in ipairs(variants) do
          if exercise.id == record.last_variant then
            table.remove(variants, index)
            break
          end
        end
      end
      local choice = variants[(math.abs(seed) % #variants) + 1]
      candidates[#candidates + 1] = {
        exercise = choice,
        skill = skill,
        due_at = record and record.due_at or 0,
        proficiency = proficiency(state, skill),
      }
    end
    table.sort(candidates, function(left, right)
      if left.due_at ~= right.due_at then
        return left.due_at < right.due_at
      end
      if left.proficiency ~= right.proficiency then
        return left.proficiency < right.proficiency
      end
      return left.skill < right.skill
    end)
    return candidates
  end

  local result = {}
  local due = candidates_for(buckets.due)
  for _, candidate in ipairs(due) do
    if #result >= limit then
      break
    end
    result[#result + 1] = candidate.exercise
  end

  local new = candidates_for(buckets.new)
  local new_count = 0
  for _, candidate in ipairs(new) do
    if #result >= limit or new_count >= 2 then
      break
    end
    result[#result + 1] = candidate.exercise
    new_count = new_count + 1
  end

  if #result == 0 then
    local future = candidates_for(buckets.future)
    if future[1] then
      result[1] = future[1].exercise
    end
  end
  return result
end

return M

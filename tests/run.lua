local lessons = require("bonetutor.lessons")
local failures = 0

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

if failures > 0 then
  error(("%d lesson definition check(s) failed"):format(failures))
end

print(("PASS: validated %d lesson definitions"):format(#lessons))

local lessons = require("bonetutor.lessons")
local M = {}

local skills = {
  "move_left", "move_right", "move_down", "move_up",
  "word_forward", "word_backward", "word_end", "word_forward",
  "line_start", "line_end", "file_top", "file_bottom",
  "find_character", "till_character", "search", "match_pair",
  "delete_word", "delete_inside_word", "change_inside_word", "delete_line",
  "delete_character", "open_line", "append_line", "yank_paste_line",
  "delete_to_end_of_line", "change_inside_quotes",
  "change_inside_word", "delete_inside_word", "change_inside_word", "change_inside_word",
}

function M.list()
  local result = {}
  for index, lesson in ipairs(lessons) do
    result[#result + 1] = {
      id = lesson.id or ("guided_%02d"):format(index),
      skill = lesson.skill or skills[index],
      language = lesson.language,
      prerequisites = {},
      lesson_index = index,
      lines = lesson.lines,
      start = lesson.start,
      target = lesson.target,
      prompt = lesson.goal,
      hint = lesson.hint,
      keys = lesson.keys,
    }
  end

  result[#result + 1] = {
    id = "word_forward_variant_02",
    skill = "word_forward",
    prerequisites = {},
    lesson_index = 5,
    lines = { "oak pine maple birch" },
    start = { 1, 1 },
    target = { cursor = { 1, 5 } },
    prompt = "Jump to the beginning of 'pine'.",
    hint = "Press w.",
    keys = { "w" },
  }
  result[#result + 1] = {
    id = "delete_inside_word_variant_02",
    skill = "delete_inside_word",
    prerequisites = {},
    lesson_index = 18,
    lines = { "keep cobalt nearby" },
    start = { 1, 8 },
    target = { lines = { "keep  nearby" } },
    prompt = "Delete only 'cobalt', leaving the surrounding spaces.",
    hint = "Press diw.",
    keys = { "d", "i", "w" },
  }
  result[#result + 1] = {
    id = "change_inside_word_variant_02",
    skill = "change_inside_word",
    prerequisites = { "word_forward" },
    lesson_index = 19,
    lines = { "set shade value" },
    start = { 1, 6 },
    target = { lines = { "set tone value" } },
    prompt = "Replace 'shade' with 'tone'.",
    hint = "Press ciw, type tone, then Escape.",
    keys = { "c", "i", "w" },
  }

  return result
end

return M

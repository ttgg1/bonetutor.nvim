local M = {}

local function index_rows(layer)
  layer.locations = {}
  for row_index, row in ipairs(layer.rows) do
    for column_index, key in ipairs(row) do
      layer.locations[key] = {
        key = key,
        layer = layer.number,
        row = layer.number == 1 and math.ceil(row_index / 2) or row_index,
        column = column_index,
        hand = layer.number == 1 and (row_index % 2 == 1 and "left" or "right") or nil,
        modifier = layer.modifier,
      }
    end
  end
end

M.standard = {
  name = "Standard Bone",
  layers = {
    [1] = {
      number = 1,
      label = "Layer 1",
      rows = {
        { "j", "d", "u", "a", "x" },
        { "p", "h", "l", "m", "w", "q" },
        { "c", "t", "i", "e", "o" },
        { "b", "n", "r", "s", "g", "ß" },
        { "f", "v", "ü", "ä", "ö" },
        { "y", "z", ",", ".", "k" },
      },
    },
    [3] = {
      number = 3,
      label = "Layer 3",
      modifier = "Mod3",
      -- Logical symbols in the ordering used by the official Bone layer diagram.
      -- Key hardware and modifier placement are user-configurable.
      rows = {
        { "¹", "²", "³", "›", "‹", "¢", "¥", "‚", "‘", "’" },
        { "…", "_", "[", "]", "^", "!", "<", ">", "=", "&", "ſ" },
        { "\\", "/", "{", "}", "*", "?", "(", ")", "-", ":", "@" },
        { "#", "$", "|", "~", "`", "+", "%", '"', "'", ";" },
      },
    },
  },
}

for _, layer in pairs(M.standard.layers) do
  index_rows(layer)
end

function M.describe(keys, layout)
  local result = {}
  if type(keys) ~= "table" then
    return result
  end
  layout = layout or M.standard

  for _, key in ipairs(keys) do
    if type(key) == "string" then
      local found
      for _, layer in pairs(layout.layers) do
        found = layer.locations[key]
        if found then
          break
        end
      end
      if found then
        result[#result + 1] = found
      end
    end
  end
  return result
end

return M

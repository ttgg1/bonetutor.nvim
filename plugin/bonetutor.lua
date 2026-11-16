if vim.g.loaded_bonetutor then
  return
end
vim.g.loaded_bonetutor = true

local function command(name, method, opts)
  vim.api.nvim_create_user_command(name, function(args)
    require("bonetutor")[method](args.args)
  end, opts or {})
end

command("BoneTutor", "start", {
  nargs = "?",
  desc = "Start or resume the Bone keyboard Vim tutor",
  complete = function()
    local result = {}
    for i = 1, require("bonetutor").lesson_count() do
      result[#result + 1] = tostring(i)
    end
    return result
  end,
})
command("BoneTutorPractice", "practice", { desc = "Start adaptive Bone tutor practice" })
command("BoneTutorDaily", "daily", { desc = "Start a short daily Bone tutor challenge" })
command("BoneTutorNext", "next", { desc = "Continue after passing the Bone tutor goal" })
command("BoneTutorPrev", "prev", { desc = "Repeat the previous Bone tutor exercise" })
command("BoneTutorReset", "reset", { desc = "Reset the current Bone tutor exercise" })
command("BoneTutorHint", "hint", { desc = "Toggle the Bone-specific key hint" })
command("BoneTutorKeys", "keys", { desc = "Toggle the Bone keyboard diagram" })
command("BoneTutorQuit", "quit", { desc = "Close the Bone tutor tab" })

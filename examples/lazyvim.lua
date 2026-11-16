-- Copy this file to ~/.config/nvim/lua/plugins/bonetutor.lua
-- after extracting the plugin to ~/.config/nvim/local/bonetutor.nvim
return {
  {
    dir = vim.fn.stdpath("config") .. "/local/bonetutor.nvim",
    name = "bonetutor.nvim",
    cmd = {
      "BoneTutor",
      "BoneTutorNext",
      "BoneTutorPrev",
      "BoneTutorReset",
      "BoneTutorHint",
      "BoneTutorKeys",
      "BoneTutorQuit",
    },
  },
}

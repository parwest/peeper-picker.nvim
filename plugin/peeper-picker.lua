if vim.g.loaded_peeper_picker_plugin then
  return
end
vim.g.loaded_peeper_picker_plugin = 1

-- Lightweight command stub: requiring the plugin (and pulling in every
-- submodule) is deferred until :PeeperPicker is actually invoked, so nothing
-- loads at startup.
vim.api.nvim_create_user_command("PeeperPicker", function()
  require("peeper_picker").find()
end, { desc = "Peeper Picker" })

local M = {}

local filters_mod = require("peeper_picker.filters")

-- Window/buffer teardown and state reset. Kept dependency-free of the rendering
-- and panel modules so both the menu and the filter panel can require it.

function M.close_filter_menu(state)
  local filter_menu = state.filter_menu
  if not filter_menu then
    return
  end
  if filter_menu.win and vim.api.nvim_win_is_valid(filter_menu.win) then
    vim.api.nvim_win_close(filter_menu.win, true)
  end
  state.filter_menu = nil
  local menu = state.menu
  if menu and menu.list_win and vim.api.nvim_win_is_valid(menu.list_win) then
    vim.schedule(function()
      if menu.list_win and vim.api.nvim_win_is_valid(menu.list_win) then
        vim.cmd("stopinsert")
        vim.api.nvim_set_current_win(menu.list_win)
      end
    end)
  end
end

function M.close_menu_windows(menu)
  if not menu then
    return
  end
  for _, win in ipairs({ menu.header_win, menu.list_win, menu.preview_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end
end

function M.close_menu(state)
  if state.menu_closing then
    return
  end
  state.menu_closing = true
  -- Run the teardown under pcall so a failed nvim_win_close (or any other error)
  -- can't leave menu_closing stuck true, which would wedge the menu shut until a
  -- restart. The flag is always cleared below regardless of how the body exits.
  local ok, err = pcall(function()
    local prompt = state.filter_prompt
    if prompt and prompt.win and vim.api.nvim_win_is_valid(prompt.win) then
      vim.api.nvim_win_close(prompt.win, true)
    end
    state.filter_prompt = nil
    M.close_menu_windows(state.menu)
    state.menu = nil
    M.close_filter_menu(state)
    state.filters = filters_mod.defaults()
    state.all_items, state.items, state.source, state.rendered_left_lines = {}, {}, {}, {}
    state.left_lines_dirty = true
  end)
  state.menu_closing = false
  if not ok then
    error(err)
  end
end

function M.reset_menu_state(state)
  if state.menu_closing then
    return
  end
  M.close_menu(state)
end

return M

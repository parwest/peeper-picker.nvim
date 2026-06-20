local M = {}

local filters_mod = require("peeper_picker.filters")

local function picker_windows(state)
  local wins = {}
  local menu = state.menu
  if menu then
    for _, win in ipairs({ menu.list_win, menu.header_win, menu.preview_win }) do
      if win then
        wins[win] = true
      end
    end
  end
  if state.filter_menu and state.filter_menu.win then
    wins[state.filter_menu.win] = true
  end
  if state.filter_prompt and state.filter_prompt.win then
    wins[state.filter_prompt.win] = true
  end
  return wins
end

function M.is_picker_window(state, win)
  return picker_windows(state)[win] == true
end

function M.close_if_focus_left(state)
  if not state.menu or state.menu_closing then
    return
  end
  if M.is_picker_window(state, vim.api.nvim_get_current_win()) then
    return
  end
  M.close_menu(state)
end

function M.close_filter_menu(state)
  local filter_menu = state.filter_menu
  if not filter_menu then
    return
  end
  state.filter_menu = nil
  local menu = state.menu
  if menu and menu.list_win and vim.api.nvim_win_is_valid(menu.list_win) then
    vim.cmd("stopinsert")
    pcall(vim.api.nvim_set_current_win, menu.list_win)
  end
  if filter_menu.win and vim.api.nvim_win_is_valid(filter_menu.win) then
    vim.api.nvim_win_close(filter_menu.win, true)
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
  -- pcall so a failed close can't leave menu_closing stuck and wedge the menu
  local ok, err = pcall(function()
    if state.menu and state.menu.augroup then
      pcall(vim.api.nvim_del_augroup_by_id, state.menu.augroup)
    end
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
    state.expand_results = nil
    state.result_meta = nil
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

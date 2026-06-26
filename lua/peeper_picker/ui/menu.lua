local M = {}

local layout = require("peeper_picker.ui.layout")
local highlight = require("peeper_picker.ui.highlight")
local keymap = require("peeper_picker.ui.keymap")
local view = require("peeper_picker.ui.view")
local lifecycle = require("peeper_picker.ui.lifecycle")
local filter_panel = require("peeper_picker.ui.filter_panel")
local key_help = require("peeper_picker.ui.key_help")
local jump = require("peeper_picker.ui.jump")
local floating = require("peeper_picker.ui.floating")

local function float_spec(state, spec, title, focusable)
  return {
    width = spec.width,
    height = spec.height,
    row = spec.row,
    col = spec.col,
    border = state.opts.border,
    title = title,
    focusable = focusable,
  }
end

local function open_pane(state, spec, title, focusable, enter, options)
  options = options or {}
  local config = float_spec(state, spec, title, focusable)
  config.enter = enter
  config.name = options.name
  config.filetype = options.filetype or "peeper-picker"
  config.win_options = options.win_options
  return floating.open(config)
end

local function store_geometry(menu, geometry)
  menu.layout_mode = geometry.mode
  menu.list_width = geometry.list_width
  menu.preview_width = geometry.preview_width
  menu.header_width = geometry.header_width
  menu.header_left_width = geometry.header_left_width
  menu.header_right_width = geometry.header_right_width
  menu.list_height = geometry.list_height
  menu.preview_height = geometry.preview_height
  menu.pane_height = geometry.pane_height
  menu.total_width = geometry.total_width
  menu.total_height = geometry.total_height
end

local function apply_geometry(state, geometry)
  local menu = state.menu
  if not menu then
    return false
  end
  local windows = {
    { win = menu.header_win, spec = geometry.header, title = state.opts.title, focusable = false },
    { win = menu.help_win, spec = geometry.help, title = " help ", focusable = false },
    { win = menu.preview_win, spec = geometry.preview, title = " preview ", focusable = false },
    { win = menu.list_win, spec = geometry.list, title = " results ", focusable = true },
  }
  for _, entry in ipairs(windows) do
    if not entry.win or not vim.api.nvim_win_is_valid(entry.win) then
      return false
    end
  end
  for _, entry in ipairs(windows) do
    pcall(
      floating.reconfigure,
      entry.win,
      float_spec(state, entry.spec, entry.title, entry.focusable)
    )
  end
  store_geometry(menu, geometry)
  return true
end

function M.open(state, lookup_id)
  if state.menu or state.filter_menu or state.filter_prompt or state.key_help then
    state.menu_closing = true
    lifecycle.close_menu_ui(state)
    state.menu_closing = false
  end
  highlight.ensure()

  local geometry, err = layout.menu(state.opts)
  if not geometry then
    vim.notify(err, vim.log.levels.WARN)
    return false
  end

  local header_buf, header_win = open_pane(state, geometry.header, state.opts.title, false, false, {
    win_options = { cursorline = false, wrap = false },
  })
  local help_buf, help_win = open_pane(state, geometry.help, " help ", false, false, {
    filetype = "peeper-picker-help",
    win_options = {
      wrap = false,
      winhighlight = "Normal:PeeperPickerHelpBar,FloatBorder:PeeperPickerHelpBorder",
    },
  })
  local preview_buf, preview_win = open_pane(state, geometry.preview, " preview ", false, false, {
    filetype = "peeper-picker-preview",
    win_options = { cursorline = false, signcolumn = "no", wrap = false },
  })
  local list_buf, list_win = open_pane(state, geometry.list, " results ", true, true, {
    name = "peeper-picker://results",
    win_options = {
      cursorline = false,
      scrolloff = 0,
      sidescrolloff = 0,
      winbar = "",
      wrap = false,
    },
  })
  state.menu = {
    header_buf = header_buf,
    header_win = header_win,
    help_buf = help_buf,
    help_win = help_win,
    list_buf = list_buf,
    list_win = list_win,
    preview_buf = preview_buf,
    preview_win = preview_win,
    lookup_id = lookup_id,
    -- stay anchored to row 1 until the cursor actually moves
    selection_locked = false,
  }
  store_geometry(state.menu, geometry)
  for _, win in ipairs({ header_win, help_win, list_win, preview_win }) do
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        lifecycle.reset_menu_state(state)
      end,
    })
  end

  state.menu.augroup = vim.api.nvim_create_augroup("PeeperPickerFocus", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = state.menu.augroup,
    callback = function()
      if not state.menu then
        return
      end
      vim.schedule(function()
        lifecycle.close_if_focus_left(state)
      end)
    end,
  })
  vim.api.nvim_create_autocmd("WinScrolled", {
    group = state.menu.augroup,
    pattern = tostring(list_win),
    callback = function()
      if state.menu then
        view.highlight_viewport(state)
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = state.menu.augroup,
    callback = function()
      vim.schedule(function()
        if not state.menu then
          return
        end
        local next_geometry, layout_err = layout.menu(state.opts)
        if not next_geometry then
          vim.notify(layout_err, vim.log.levels.WARN)
          lifecycle.close_menu(state)
          return
        end
        if apply_geometry(state, next_geometry) then
          state.left_lines_dirty = true
          view.update_preview(state)
          filter_panel.reflow(state)
          key_help.reflow(state)
        end
      end)
    end,
  })

  view.render_loading(state)
  local bind = keymap.bind
  local function activate_current()
    if not view.toggle_group(state) then
      jump.select_current(state)
    end
  end
  bind(list_buf, "n", "q", function() lifecycle.close_menu(state) end)
  bind(list_buf, "n", "<Esc>", function() lifecycle.close_menu(state) end)
  bind(list_buf, "n", "<C-c>", function()
    state.lookup_id = state.lookup_id + 1
    lifecycle.close_menu(state)
  end)
  bind(list_buf, "n", "j", function() view.move_cursor(state, vim.v.count1) end)
  bind(list_buf, "n", "<Down>", function() view.move_cursor(state, vim.v.count1) end)
  bind(list_buf, "n", "k", function() view.move_cursor(state, -vim.v.count1) end)
  bind(list_buf, "n", "<Up>", function() view.move_cursor(state, -vim.v.count1) end)
  bind(list_buf, "n", "gg", function() view.jump_to(state, 1) end)
  bind(list_buf, "n", "G", function() view.jump_to(state, #(state.list_rows or {})) end)
  bind(list_buf, "n", "f", function() filter_panel.open(state) end)
  bind(list_buf, "n", "?", function() key_help.open(state) end)
  bind(list_buf, "n", "=", function()
    if state.expand_results then
      local ok, message = state.expand_results()
      if not ok and message then
        vim.notify("peeper-picker.nvim: " .. message, vim.log.levels.INFO)
      end
    end
  end)
  bind(list_buf, "n", "<CR>", activate_current)
  bind(list_buf, "n", "J", function() view.next_group(state, vim.v.count1) end)
  bind(list_buf, "n", "K", function() view.previous_group(state, vim.v.count1) end)
  bind(list_buf, "n", "za", function() view.fold_group(state, "toggle") end)
  bind(list_buf, "n", "zo", function() view.fold_group(state, "open") end)
  bind(list_buf, "n", "zc", function() view.fold_group(state, "close") end)
  bind(list_buf, "n", "zM", function() view.set_all_groups(state, true) end)
  bind(list_buf, "n", "zR", function() view.set_all_groups(state, false) end)
  bind(list_buf, "n", "<C-v>", function() jump.select_current(state, "vsplit", false) end)
  bind(list_buf, "n", "<C-x>", function() jump.select_current(state, "split", false) end)
  bind(list_buf, "n", "<C-t>", function() jump.select_current(state, "tabedit", false) end)
  bind(list_buf, "n", "<LeftMouse>", function()
    local menu = state.menu
    if not menu then
      return
    end
    local pos = vim.fn.getmousepos()
    if pos.winid == menu.list_win then
      if #state.items > 0 and pos.line >= 1 then
        view.jump_to(state, pos.line)
      end
    elseif not lifecycle.is_picker_window(state, pos.winid) then
      lifecycle.close_menu(state)
    end
  end)
  bind(list_buf, "n", "<2-LeftMouse>", function()
    local menu = state.menu
    if not menu then
      return
    end
    local pos = vim.fn.getmousepos()
    if pos.winid == menu.list_win and #state.items > 0 and pos.line >= 1 then
      view.jump_to(state, pos.line)
      activate_current()
    end
  end)
  return true
end

return M

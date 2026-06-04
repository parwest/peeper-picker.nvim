local M = {}

local text = require("peeper_picker.ui.text")
local keymap = require("peeper_picker.ui.keymap")
local view = require("peeper_picker.ui.view")
local lifecycle = require("peeper_picker.ui.lifecycle")
local filters_mod = require("peeper_picker.filters")
local paths = require("peeper_picker.paths")
local highlight = require("peeper_picker.ui.highlight")

local function render_columns(left_lines, right_lines, left_width, right_width)
  local total_rows = math.max(#left_lines, #right_lines)
  local lines = {}
  for i = 1, total_rows do
    table.insert(lines, text.fit_text(left_lines[i] or "", left_width) .. " │ " .. text.fit_text(right_lines[i] or "", right_width))
  end
  return lines
end

local function render_filter_menu(state)
  local filter_menu = state.filter_menu
  if not filter_menu or not vim.api.nvim_buf_is_valid(filter_menu.buf) then
    return
  end
  local function filter_line(label, value, active)
    return active and ("%s: %s (active)"):format(label, value) or ("%s: %s"):format(label, value)
  end
  local left_lines = {
    "filter menu",
    "",
    filter_line("scope", filters_mod.scope_label(state.filters.scope), state.filters.scope ~= "workspace"),
    "  press s to change scope",
    "  choices: file / dir / workspace",
    "  " .. filters_mod.scope_hint(state.source),
    "",
    filter_line("results", filters_mod.result_label(state.filters), filters_mod.result_mode(state.filters) ~= "code"),
    "  press 1 to show code",
    "  press 2 to show references",
    "  press 3 to show definitions",
    "  press 4 to show all",
    "  default: code",
    "",
    filter_line("path", filters_mod.path_label(state.filters.path), state.filters.path ~= ""),
    "  press p to filter by path",
    "",
    filter_line("extension", filters_mod.extension_label(state.filters.extension), state.filters.extension ~= ""),
    "  press t to filter by extension",
    "",
    ("results: %d / %d"):format(#state.items, #state.all_items),
  }
  local right_lines = {
    "controls",
    "",
    "j/k  move controls",
    "esc/q close panel",
    "r    reset field",
    "x    reset filters",
  }
  local left_width = math.max(30, math.min(48, (filter_menu.width or 78) - 33))
  local lines = render_columns(left_lines, right_lines, left_width, 28)
  text.set_buf_lines(filter_menu.buf, lines)
  vim.api.nvim_buf_clear_namespace(filter_menu.buf, -1, 0, -1)
  for _, row in ipairs({ 2, 7, 14, 17 }) do
    highlight.filter_control(filter_menu.buf, row, left_width)
  end
  filter_menu.focus_rows = { 3, 8, 15, 18 }
  filter_menu.focus_fields = { "scope", "results", "path", "extension" }
  filter_menu.focus_index = math.min(#filter_menu.focus_rows, math.max(1, filter_menu.focus_index or 1))
  vim.api.nvim_win_set_cursor(filter_menu.win, { filter_menu.focus_rows[filter_menu.focus_index], 0 })
end

function M.open(state)
  local menu = state.menu
  if not menu or not vim.api.nvim_win_is_valid(menu.win) then
    return
  end
  lifecycle.close_filter_menu(state)

  local width = math.max(48, math.min(84, vim.o.columns - 4))
  local height = math.max(18, math.min(28, vim.o.lines - 4))
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = state.opts.border,
    title = " filters ",
    title_pos = "center",
    zindex = 60,
  })

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "peeper-picker-filter"
  vim.bo[buf].swapfile = false
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false

  state.filter_menu = { buf = buf, win = win, width = width }
  state.render_filter_menu = function()
    render_filter_menu(state)
  end

  local function refresh()
    render_filter_menu(state)
  end
  local function set_result_mode(mode)
    filters_mod.set_result_mode(state.filters, mode)
    view.apply_filters(state)
    refresh()
  end
  local function cycle_scope()
    local order = { "file", "dir", "workspace" }
    local current = 3
    for i, value in ipairs(order) do
      if value == state.filters.scope then
        current = i
        break
      end
    end
    state.filters.scope = order[(current % #order) + 1]
    view.apply_filters(state)
    refresh()
  end
  local function close_prompt(cancelled)
    local prompt = state.filter_prompt
    if not prompt then
      return
    end
    vim.cmd("stopinsert")
    if prompt.win and vim.api.nvim_win_is_valid(prompt.win) then
      vim.api.nvim_win_close(prompt.win, true)
    end
    state.filter_prompt = nil
    if state.filter_menu and state.filter_menu.win and vim.api.nvim_win_is_valid(state.filter_menu.win) then
      vim.schedule(function()
        if state.filter_menu and state.filter_menu.win and vim.api.nvim_win_is_valid(state.filter_menu.win) then
          vim.cmd("stopinsert")
          vim.api.nvim_set_current_win(state.filter_menu.win)
        end
      end)
    elseif cancelled then
      lifecycle.close_menu(state)
    end
  end
  local function prompt_field(field, prompt)
    local current = state.filters[field] or ""
    local width = math.max(40, math.min(90, vim.o.columns - 8))
    local prompt_lines = { prompt }
    if field == "path" then
      prompt_lines = {
        "Path filter",
        "Type text to include matching paths.",
        "Start with ! to exclude. Example: !src/",
        current,
      }
    elseif field == "extension" then
      prompt_lines = {
        "Extension filter",
        "Type js to include .js files.",
        "Start with ! to exclude. Example: !js",
        current,
      }
    else
      prompt_lines = { prompt, current }
    end
    local input_row = #prompt_lines
    local height = math.max(3, #prompt_lines + 1)
    local buf_prompt = vim.api.nvim_create_buf(false, true)
    local win_prompt = vim.api.nvim_open_win(buf_prompt, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.max(0, math.floor((vim.o.lines - height) / 2)),
      col = math.max(0, math.floor((vim.o.columns - width) / 2)),
      style = "minimal",
      border = state.opts.border,
      title = prompt,
      title_pos = "center",
      zindex = 70,
    })
    vim.bo[buf_prompt].bufhidden = "wipe"
    vim.bo[buf_prompt].buftype = "nofile"
    vim.bo[buf_prompt].swapfile = false
    vim.bo[buf_prompt].modifiable = true
    vim.bo[buf_prompt].filetype = "peeper-picker-filter-prompt"
    vim.wo[win_prompt].wrap = false
    vim.api.nvim_buf_set_lines(buf_prompt, 0, -1, false, prompt_lines)
    vim.api.nvim_win_set_cursor(win_prompt, { input_row, #current })
    state.filter_prompt = { buf = buf_prompt, win = win_prompt, field = field }
    local function accept()
      local line = vim.api.nvim_buf_get_lines(buf_prompt, input_row - 1, input_row, false)[1] or ""
      close_prompt(false)
      state.filters[field] = vim.trim(line):lower()
      view.apply_filters(state)
      refresh()
    end
    local function cancel()
      close_prompt(true)
    end
    for lhs, fn in pairs({ ["<CR>"] = accept, ["<Esc>"] = cancel, q = cancel, ["<F9>"] = cancel }) do
      keymap.bind(buf_prompt, "i", lhs, fn)
    end
    keymap.bind(buf_prompt, "n", "q", cancel)
    keymap.bind(buf_prompt, "n", "<Esc>", cancel)
    keymap.bind(buf_prompt, "n", "<F9>", cancel)
    vim.cmd("startinsert!")
  end
  local function reset_all()
    state.filters = filters_mod.defaults()
    view.apply_filters(state)
    refresh()
  end
  local function reset_focused_field()
    local focus_index = state.filter_menu and state.filter_menu.focus_index or 1
    local field = state.filter_menu and state.filter_menu.focus_fields and state.filter_menu.focus_fields[focus_index] or nil
    if field == "scope" then
      state.filters.scope = "workspace"
    elseif field == "results" then
      filters_mod.set_result_mode(state.filters, "code")
    elseif field == "path" or field == "extension" then
      state.filters[field] = ""
    else
      return
    end
    view.apply_filters(state)
    refresh()
  end
  local function move_focus(delta)
    local rows = state.filter_menu and state.filter_menu.focus_rows
    if not rows then
      return
    end
    state.filter_menu.focus_index = math.min(#rows, math.max(1, (state.filter_menu.focus_index or 1) + delta))
    vim.api.nvim_win_set_cursor(state.filter_menu.win, { rows[state.filter_menu.focus_index], 0 })
  end
  local function filter_key(lhs, fn)
    keymap.bind(buf, { "n", "i" }, lhs, function()
      vim.cmd("stopinsert")
      fn()
    end)
  end

  filter_key("1", function() set_result_mode("code") end)
  filter_key("2", function() set_result_mode("refs") end)
  filter_key("3", function() set_result_mode("defs") end)
  filter_key("4", function() set_result_mode("all") end)
  filter_key("s", cycle_scope)
  filter_key("p", function() prompt_field("path", "Path filter") end)
  filter_key("t", function() prompt_field("extension", "Extension filter") end)
  filter_key("r", reset_focused_field)
  filter_key("x", reset_all)
  filter_key("j", function() move_focus(1) end)
  filter_key("<Down>", function() move_focus(1) end)
  filter_key("k", function() move_focus(-1) end)
  filter_key("<Up>", function() move_focus(-1) end)
  filter_key("q", function() lifecycle.close_filter_menu(state) end)
  filter_key("<Esc>", function() lifecycle.close_filter_menu(state) end)
  filter_key("<CR>", function() lifecycle.close_filter_menu(state) end)

  render_filter_menu(state)
  vim.cmd("stopinsert")
end

return M

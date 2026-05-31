local M = {}

local config = require("peeper_picker.config")
local filters_mod = require("peeper_picker.filters")
local paths = require("peeper_picker.paths")
local preview = require("peeper_picker.preview")
local results = require("peeper_picker.results")

local selected_ns = vim.api.nvim_create_namespace("peeper-picker-selected")
local eager_text_radius = 25

local function display_width(text)
  return vim.fn.strdisplaywidth(text)
end

local function fit_text(text, width)
  text = text or ""
  local current = display_width(text)
  if current <= width then
    return text .. string.rep(" ", width - current)
  end
  if width <= 1 then
    return string.rep(" ", math.max(width, 0))
  end
  return vim.fn.strcharpart(text, 0, width - 1) .. "…"
end

local function set_buf_lines(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function ensure_highlights()
  vim.api.nvim_set_hl(0, "PeeperPickerDefinition", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerReference", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerPath", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerSelected", { link = "Visual", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerFilterControl", { link = "WarningMsg", default = true })
end

local function source_header_lines(state, left_width, right_width)
  local source = state.source or {}
  local word = source.word and source.word ~= "" and source.word or "symbol"
  local path = source.path and paths.display_path(source.path) or "[No Name]"
  local pos = source.line and source.character and (":%d:%d"):format(source.line, source.character) or ""
  local root = source.workspace_root and paths.display_path(source.workspace_root) or vim.fn.getcwd()
  return {
    fit_text(("Searching for  %s"):format(word), left_width) .. "│" .. fit_text(path .. pos, right_width),
    fit_text(("Scope  %s"):format(state.filters.scope), left_width) .. "│" .. fit_text("Workspace  " .. root, right_width),
    string.rep("─", left_width) .. "┼" .. string.rep("─", right_width),
  }
end

local function render_combo_lines(left_lines, right_lines, left_width, right_width)
  local total_rows = math.max(#left_lines, #right_lines)
  local lines = {}
  for i = 1, total_rows do
    table.insert(lines, fit_text(left_lines[i] or "", left_width) .. "│" .. fit_text(right_lines[i] or "", right_width))
  end
  return lines
end

local function render_columns(left_lines, right_lines, left_width, right_width)
  local total_rows = math.max(#left_lines, #right_lines)
  local lines = {}
  for i = 1, total_rows do
    table.insert(lines, fit_text(left_lines[i] or "", left_width) .. " │ " .. fit_text(right_lines[i] or "", right_width))
  end
  return lines
end

local function menu_layout(opts)
  local available = math.max(40, vim.o.columns - 4)
  local preview_width = math.min(opts.preview_width, math.max(24, math.floor(available * 0.46)))
  local list_width = math.min(opts.width, math.max(32, available - preview_width - 3))
  if list_width + preview_width + 3 > available then
    preview_width = math.max(24, available - list_width - 3)
  end
  if list_width + preview_width + 3 > available then
    list_width = math.max(32, available - preview_width - 3)
  end
  local total_width = math.min(vim.o.columns - 4, math.max(60, list_width + preview_width + 3))
  local height = math.min(math.max(opts.height, opts.preview_height), math.max(8, vim.o.lines - 6))
  return list_width, preview_width, total_width, height
end

local function item_from_cursor(state)
  local menu = state.menu
  if not menu or not menu.win or not vim.api.nvim_win_is_valid(menu.win) then
    return nil, nil
  end
  local idx = vim.api.nvim_win_get_cursor(menu.win)[1] - (menu.header_height or 0)
  return state.items[idx], idx
end

local function selected_item_key(state)
  local item = item_from_cursor(state)
  return item and results.key(item) or nil
end

local function apply_result_highlights(buf, items, end_col, row_offset)
  local offset = row_offset or 0
  for i, item in ipairs(items) do
    local group = item.kind == "ref" and "PeeperPickerReference" or "PeeperPickerDefinition"
    local row = offset + i - 1
    vim.api.nvim_buf_add_highlight(buf, -1, group, row, 4, math.min(11, end_col or -1))
    vim.api.nvim_buf_add_highlight(buf, -1, "PeeperPickerPath", row, 12, end_col or -1)
  end
end

local function highlight_selected_row(buf, idx, end_col)
  vim.api.nvim_buf_clear_namespace(buf, selected_ns, 0, -1)
  if idx and idx >= 1 then
    vim.api.nvim_buf_add_highlight(buf, selected_ns, "PeeperPickerSelected", idx - 1, 0, end_col or -1)
  end
end

local function render_left_line(state, idx, hydrate_text)
  local item = state.items[idx]
  if not item then
    return ""
  end
  if hydrate_text and not item.text then
    item.text = preview.line_at(item.uri, item.range.start.line)
  end
  return results.format_line(item, idx, #state.items)
end

local function rebuild_left_lines(state, selected_idx)
  state.rendered_left_lines = {}
  for i, _ in ipairs(state.items) do
    local hydrate_text = i <= eager_text_radius or math.abs(i - selected_idx) <= eager_text_radius
    state.rendered_left_lines[i] = render_left_line(state, i, hydrate_text)
  end
end

local function hydrate_visible_left_lines(state, selected_idx)
  if not state.rendered_left_lines then
    state.rendered_left_lines = {}
  end
  local first = math.max(1, selected_idx - eager_text_radius)
  local last = math.min(#state.items, selected_idx + eager_text_radius)
  for i = first, last do
    state.rendered_left_lines[i] = render_left_line(state, i, true)
  end
end

local function update_winbar(state)
  local menu = state.menu
  if not menu or not menu.win or not vim.api.nvim_win_is_valid(menu.win) then
    return
  end
  local summary = #state.items > 0 and ("%d results"):format(#state.items) or "no results"
  vim.wo[menu.win].winbar = (" j/k move  ENTER open  f filters  q quit  %s "):format(summary)
end

local function item_byte_col(bufnr, item)
  local position = item.range and item.range.start
  if not position then
    return 0
  end
  local ok, byte_col = pcall(
    vim.lsp.util._get_line_byte_from_position,
    bufnr,
    position,
    item.position_encoding or "utf-16"
  )
  return ok and byte_col or position.character
end

function M.update_preview(state)
  local menu = state.menu
  if not menu or not menu.buf or not vim.api.nvim_buf_is_valid(menu.buf) then
    return
  end
  if not menu.win or not vim.api.nvim_win_is_valid(menu.win) then
    return
  end

  local header_height = menu.header_height or 0
  local row = menu.pending_selected_row or vim.api.nvim_win_get_cursor(menu.win)[1]
  menu.pending_selected_row = nil
  local idx = math.max(1, row - header_height)
  local item = state.items[idx]

  if state.left_lines_dirty then
    rebuild_left_lines(state, idx)
    state.left_lines_dirty = false
  else
    hydrate_visible_left_lines(state, idx)
  end

  local right_lines = { "Press f to adjust filters." }
  local target_line = nil
  if item then
    right_lines, target_line = preview.context(item, state.opts.preview_context)
  end

  local lines = source_header_lines(state, menu.list_width, menu.preview_width)
  vim.list_extend(lines, render_combo_lines(state.rendered_left_lines or {}, right_lines, menu.list_width, menu.preview_width))
  vim.bo[menu.buf].modifiable = true
  vim.api.nvim_buf_set_lines(menu.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(menu.buf, -1, 0, -1)
  apply_result_highlights(menu.buf, state.items, menu.list_width, header_height)
  if item and target_line then
    vim.api.nvim_buf_add_highlight(menu.buf, -1, "PeeperPickerDefinition", header_height + target_line - 1, menu.list_width + 3, menu.list_width + 3 + menu.preview_width)
  end
  highlight_selected_row(menu.buf, header_height + idx, menu.list_width)
  vim.bo[menu.buf].modifiable = false
  vim.api.nvim_win_set_cursor(menu.win, { math.min(#lines, math.max(header_height + idx, 1)), 0 })
  update_winbar(state)
end

function M.render_filtered_empty(state)
  local menu = state.menu
  if not menu then
    return
  end
  state.rendered_left_lines = {}
  state.left_lines_dirty = false
  menu.mode = "filtered_empty"
  local lines = source_header_lines(state, menu.list_width or 32, menu.preview_width or 32)
  vim.list_extend(lines, {
    fit_text("No results match filters", menu.list_width or 32) .. "│" .. fit_text("Press f to adjust filters.", menu.preview_width or 32),
  })
  set_buf_lines(menu.buf, lines)
  update_winbar(state)
end

function M.render_loading(state)
  local menu = state.menu
  if not menu then
    return
  end
  state.all_items, state.items, state.rendered_left_lines = {}, {}, {}
  menu.mode = "loading"
  local lines = source_header_lines(state, menu.list_width or 32, menu.preview_width or 32)
  vim.list_extend(lines, {
    fit_text("Loading...", menu.list_width or 32) .. "│" .. fit_text("Waiting for LSP response...", menu.preview_width or 32),
  })
  set_buf_lines(menu.buf, lines)
  update_winbar(state)
end

function M.render_empty(state)
  local menu = state.menu
  if not menu then
    return
  end
  state.all_items, state.items, state.rendered_left_lines = {}, {}, {}
  menu.mode = "empty"
  local lines = source_header_lines(state, menu.list_width or 32, menu.preview_width or 32)
  vim.list_extend(lines, {
    fit_text("No definitions or references found", menu.list_width or 32) .. "│" .. fit_text("Press q or Esc to close.", menu.preview_width or 32),
  })
  set_buf_lines(menu.buf, lines)
  update_winbar(state)
end

function M.apply_filters(state, preserve_key)
  local keep_key = preserve_key or selected_item_key(state)
  state.items = filters_mod.apply(state.all_items, state.filters, state.source)
  state.left_lines_dirty = true
  if #state.items == 0 then
    M.render_filtered_empty(state)
    if state.render_filter_menu then
      state.render_filter_menu()
    end
    return
  end

  local selected = 1
  if keep_key then
    for i, item in ipairs(state.items) do
      if results.key(item) == keep_key then
        selected = i
        break
      end
    end
  end
  state.menu.mode = "results"
  state.menu.pending_selected_row = (state.menu.header_height or 0) + selected
  M.update_preview(state)
  if state.render_filter_menu then
    state.render_filter_menu()
  end
end

local function close_filter_menu(state)
  local filter_menu = state.filter_menu
  if not filter_menu then
    return
  end
  if filter_menu.win and vim.api.nvim_win_is_valid(filter_menu.win) then
    vim.api.nvim_win_close(filter_menu.win, true)
  end
  state.filter_menu = nil
  local menu = state.menu
  if menu and menu.win and vim.api.nvim_win_is_valid(menu.win) then
    vim.schedule(function()
      if menu.win and vim.api.nvim_win_is_valid(menu.win) then
        vim.cmd("stopinsert")
        vim.api.nvim_set_current_win(menu.win)
      end
    end)
  end
end

function M.close_menu(state)
  local prompt = state.filter_prompt
  if prompt and prompt.win and vim.api.nvim_win_is_valid(prompt.win) then
    vim.api.nvim_win_close(prompt.win, true)
  end
  state.filter_prompt = nil
  local menu = state.menu
  if menu and menu.win and vim.api.nvim_win_is_valid(menu.win) then
    vim.api.nvim_win_close(menu.win, true)
  end
  state.menu = nil
  close_filter_menu(state)
  state.filters = filters_mod.defaults()
  state.all_items, state.items, state.source, state.rendered_left_lines = {}, {}, {}, {}
  state.left_lines_dirty = true
end

function M.reset_menu_state(state)
  state.menu = nil
  close_filter_menu(state)
  state.filters = filters_mod.defaults()
  state.all_items, state.items, state.source, state.rendered_left_lines = {}, {}, {}, {}
  state.left_lines_dirty = true
end

function M.move_cursor(state, delta)
  local menu = state.menu
  if not menu or not vim.api.nvim_win_is_valid(menu.win) or #state.items == 0 then
    return
  end
  local header_height = menu.header_height or 0
  local pos = vim.api.nvim_win_get_cursor(menu.win)[1] - header_height
  pos = math.min(#state.items, math.max(1, pos + delta))
  vim.api.nvim_win_set_cursor(menu.win, { header_height + pos, 0 })
  M.update_preview(state)
end

local function jump_to_item(state, item, command, reuse_window)
  local path = vim.uri_to_fname(item.uri)
  if reuse_window == nil then
    reuse_window = state.opts.reuse_window
  end
  if reuse_window == nil then
    reuse_window = config.options.reuse_window
  end

  local tabpage, win
  if reuse_window then
    tabpage, win = paths.find_open_window(path)
  end

  if tabpage and win then
    vim.api.nvim_set_current_tabpage(tabpage)
    vim.api.nvim_set_current_win(win)
  else
    command = command or state.opts.jump or config.options.jump
    if type(command) == "function" then
      command(path, item)
    else
      vim.cmd(command .. " " .. vim.fn.fnameescape(path))
    end
  end
  local bufnr = vim.api.nvim_get_current_buf()
  vim.api.nvim_win_set_cursor(0, { item.range.start.line + 1, item_byte_col(bufnr, item) })
  vim.cmd("normal! zz")
end

function M.select_current(state, command, reuse_window)
  local item = item_from_cursor(state)
  if not item then
    return
  end
  state.lookup_id = state.lookup_id + 1
  local menu = state.menu
  if menu and menu.win and vim.api.nvim_win_is_valid(menu.win) then
    pcall(vim.api.nvim_win_close, menu.win, true)
  end
  M.reset_menu_state(state)
  vim.schedule(function()
    jump_to_item(state, item, command, reuse_window)
  end)
end

local function bind(buf, modes, lhs, fn)
  vim.keymap.set(modes, lhs, fn, { buffer = buf, nowait = true, silent = true })
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
    filter_line("kinds", filters_mod.kind_label(state.filters.kind_mode), state.filters.kind_mode ~= "both"),
    "  press 1 to show references only",
    "  press 2 to show definitions only",
    "  press 3 to show both",
    "  refs are places where the symbol is used",
    "  default: both",
    "",
    filter_line("path", filters_mod.field_label(state.filters.path), state.filters.path ~= ""),
    "  press p to filter by path",
    "  matches any path substring",
    "",
    filter_line("extension", filters_mod.extension_label(state.filters.extension), state.filters.extension ~= ""),
    "  press t to filter by extension",
    "  matches filename suffixes like .js",
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
  set_buf_lines(filter_menu.buf, lines)
  vim.api.nvim_buf_clear_namespace(filter_menu.buf, -1, 0, -1)
  for _, row in ipairs({ 2, 7, 14, 18 }) do
    vim.api.nvim_buf_add_highlight(filter_menu.buf, -1, "PeeperPickerFilterControl", row, 0, left_width)
  end
  filter_menu.focus_rows = { 3, 8, 15, 19 }
  filter_menu.focus_fields = { "scope", "kind_mode", "path", "extension" }
  filter_menu.focus_index = math.min(#filter_menu.focus_rows, math.max(1, filter_menu.focus_index or 1))
  vim.api.nvim_win_set_cursor(filter_menu.win, { filter_menu.focus_rows[filter_menu.focus_index], 0 })
end

function M.open_filter_menu(state)
  local menu = state.menu
  if not menu or not vim.api.nvim_win_is_valid(menu.win) then
    return
  end
  close_filter_menu(state)

  local width = math.max(48, math.min(84, vim.o.columns - 4))
  local height = math.max(18, math.min(24, vim.o.lines - 4))
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
  local function set_kind_mode(mode)
    state.filters.kind_mode = mode
    M.apply_filters(state)
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
    M.apply_filters(state)
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
      M.close_menu(state)
    end
  end
  local function prompt_field(field, prompt)
    local current = state.filters[field] or ""
    local width = math.max(40, math.min(90, vim.o.columns - 8))
    local buf_prompt = vim.api.nvim_create_buf(false, true)
    local win_prompt = vim.api.nvim_open_win(buf_prompt, true, {
      relative = "editor",
      width = width,
      height = 3,
      row = math.max(0, math.floor((vim.o.lines - 3) / 2)),
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
    vim.api.nvim_buf_set_lines(buf_prompt, 0, -1, false, { prompt, current })
    vim.api.nvim_win_set_cursor(win_prompt, { 2, #current })
    state.filter_prompt = { buf = buf_prompt, win = win_prompt, field = field }
    local function accept()
      local line = vim.api.nvim_buf_get_lines(buf_prompt, 1, 2, false)[1] or ""
      close_prompt(false)
      state.filters[field] = field == "extension" and paths.normalize_extension(line) or vim.trim(line):lower()
      M.apply_filters(state)
      refresh()
    end
    local function cancel()
      close_prompt(true)
    end
    for lhs, fn in pairs({ ["<CR>"] = accept, ["<Esc>"] = cancel, q = cancel, ["<F9>"] = cancel }) do
      bind(buf_prompt, "i", lhs, fn)
    end
    bind(buf_prompt, "n", "q", cancel)
    bind(buf_prompt, "n", "<Esc>", cancel)
    bind(buf_prompt, "n", "<F9>", cancel)
    vim.cmd("startinsert!")
  end
  local function reset_all()
    state.filters = filters_mod.defaults()
    M.apply_filters(state)
    refresh()
  end
  local function reset_focused_field()
    local focus_index = state.filter_menu and state.filter_menu.focus_index or 1
    local field = state.filter_menu and state.filter_menu.focus_fields and state.filter_menu.focus_fields[focus_index] or nil
    if field == "scope" then
      state.filters.scope = "workspace"
    elseif field == "kind_mode" then
      state.filters.kind_mode = "both"
    elseif field == "path" or field == "extension" then
      state.filters[field] = ""
    else
      return
    end
    M.apply_filters(state)
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
    bind(buf, { "n", "i" }, lhs, function()
      vim.cmd("stopinsert")
      fn()
    end)
  end

  filter_key("1", function() set_kind_mode("refs") end)
  filter_key("2", function() set_kind_mode("defs") end)
  filter_key("3", function() set_kind_mode("both") end)
  filter_key("s", cycle_scope)
  filter_key("p", function() prompt_field("path", "Path contains: ") end)
  filter_key("t", function() prompt_field("extension", "Extension (.js): ") end)
  filter_key("r", reset_focused_field)
  filter_key("x", reset_all)
  filter_key("j", function() move_focus(1) end)
  filter_key("<Down>", function() move_focus(1) end)
  filter_key("k", function() move_focus(-1) end)
  filter_key("<Up>", function() move_focus(-1) end)
  filter_key("q", function() close_filter_menu(state) end)
  filter_key("<Esc>", function() close_filter_menu(state) end)
  filter_key("<CR>", function() close_filter_menu(state) end)

  render_filter_menu(state)
  vim.cmd("stopinsert")
end

function M.open_menu(state, lookup_id)
  local prompt = state.filter_prompt
  if prompt and prompt.win and vim.api.nvim_win_is_valid(prompt.win) then
    vim.api.nvim_win_close(prompt.win, true)
  end
  state.filter_prompt = nil
  close_filter_menu(state)
  if state.menu and state.menu.win and vim.api.nvim_win_is_valid(state.menu.win) then
    vim.api.nvim_win_close(state.menu.win, true)
  end
  state.menu = nil
  ensure_highlights()

  local list_width, preview_width, total_width, height = menu_layout(state.opts)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = total_width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2)),
    col = math.max(0, math.floor((vim.o.columns - total_width) / 2)),
    style = "minimal",
    border = state.opts.border,
    title = state.opts.title,
    title_pos = "center",
  })

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].filetype = "peeper-picker"
  vim.bo[buf].swapfile = false
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false
  state.menu = {
    buf = buf,
    win = win,
    mode = "loading",
    lookup_id = lookup_id,
    list_width = list_width,
    preview_width = preview_width,
    header_height = 3,
  }
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      M.reset_menu_state(state)
    end,
  })

  M.render_loading(state)
  bind(buf, "n", "q", function() M.close_menu(state) end)
  bind(buf, "n", "<Esc>", function() M.close_menu(state) end)
  bind(buf, "n", "<C-c>", function()
    state.lookup_id = state.lookup_id + 1
    M.close_menu(state)
  end)
  bind(buf, "n", "j", function() M.move_cursor(state, 1) end)
  bind(buf, "n", "<Down>", function() M.move_cursor(state, 1) end)
  bind(buf, "n", "k", function() M.move_cursor(state, -1) end)
  bind(buf, "n", "<Up>", function() M.move_cursor(state, -1) end)
  bind(buf, "n", "f", function() M.open_filter_menu(state) end)
  bind(buf, "n", "<Enter>", function() M.select_current(state) end)
  bind(buf, "n", "<CR>", function() M.select_current(state) end)
  bind(buf, "n", "<C-m>", function() M.select_current(state) end)
  bind(buf, "n", "<C-v>", function() M.select_current(state, "vsplit", false) end)
  bind(buf, "n", "<C-x>", function() M.select_current(state, "split", false) end)
  bind(buf, "n", "<C-t>", function() M.select_current(state, "tabedit", false) end)
end

return M

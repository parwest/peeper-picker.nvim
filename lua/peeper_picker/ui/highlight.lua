local M = {}

local results_ns = vim.api.nvim_create_namespace("peeper-picker-results")
local selected_ns = vim.api.nvim_create_namespace("peeper-picker-selected")
local header_symbol_ns = vim.api.nvim_create_namespace("peeper-picker-header-symbol")
local help_action_ns = vim.api.nvim_create_namespace("peeper-picker-help-action")
local preview_ns = vim.api.nvim_create_namespace("peeper-picker-preview")
local results = require("peeper_picker.results")

local function add_hl(buf, ns, group, row, col_start, col_end)
  local opts = { hl_group = group, strict = false }
  if col_end == nil or col_end < 0 then
    opts.end_row = row + 1
    opts.end_col = 0
  else
    opts.end_col = col_end
  end
  vim.api.nvim_buf_set_extmark(buf, ns, row, col_start, opts)
end

local function mix_color(from, toward, amount)
  local function channel(color, shift)
    return math.floor(color / (256 ^ shift)) % 256
  end
  local mixed = {}
  for shift = 0, 2 do
    local a = channel(from, shift)
    local b = channel(toward, shift)
    mixed[shift] = math.floor(a + (b - a) * amount + 0.5)
  end
  return mixed[2] * 65536 + mixed[1] * 256 + mixed[0]
end

M.results_ns = results_ns

function M.ensure()
  local normal_float = vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false })
  local modal_text = { fg = normal_float.fg or "fg", default = true }
  local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
  local help_bg = normal_float.bg or normal.bg
  local help_fg = normal_float.fg or normal.fg
  local help_style = { default = true }
  if help_bg then
    local target = help_fg or (help_bg < 0x808080 and 0xffffff or 0)
    help_style.bg = mix_color(help_bg, target, 0.08)
    help_style.fg = help_fg or "fg"
  else
    help_style.link = "StatusLineNC"
  end
  local preview_target_style = { default = true }
  local preview_bg = normal_float.bg or normal.bg
  local preview_fg = normal_float.fg or normal.fg
  if preview_bg then
    local target = preview_fg or (preview_bg < 0x808080 and 0xffffff or 0)
    preview_target_style.bg = mix_color(preview_bg, target, 0.1)
  else
    preview_target_style.link = "CursorLine"
  end
  local float_border = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
  local help_border = {
    fg = float_border.fg or help_fg or "fg",
    bg = normal_float.bg or normal.bg,
    default = true,
  }
  local search_style = vim.api.nvim_get_hl(0, { name = "Search", link = false })
  if not next(search_style) then
    search_style = { reverse = true }
  end
  search_style.default = true
  vim.api.nvim_set_hl(0, "PeeperPickerDefinition", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerReference", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerTextMatch", { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerCommentMatch", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerGroup", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerSelected", { link = "Visual", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerFilterControl", { link = "WarningMsg", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerSymbolName", { link = "Underlined", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerExpandAction", search_style)
  vim.api.nvim_set_hl(0, "PeeperPickerPreviewMatch", search_style)
  vim.api.nvim_set_hl(0, "PeeperPickerHiddenSearch", { default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerPreviewTargetLine", preview_target_style)
  vim.api.nvim_set_hl(0, "PeeperPickerPreviewTargetMarker", { link = "WarningMsg", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerPreviewLineNumber", modal_text)
  vim.api.nvim_set_hl(0, "PeeperPickerHelpBar", help_style)
  vim.api.nvim_set_hl(0, "PeeperPickerHelpBorder", help_border)
end

function M.apply_results(buf, rows, row_offset, item_offset, row_count)
  local offset = row_offset or 0
  local start_item = item_offset or 1
  local stop_item = math.min(#rows, start_item + (row_count or #rows) - 1)
  if stop_item < start_item then
    return
  end
  local lines = vim.api.nvim_buf_get_lines(buf, offset, offset + (stop_item - start_item + 1), false)
  for i = start_item, stop_item do
    local entry = rows[i]
    local item = entry.item
    local row = offset + i - start_item
    local line = lines[i - start_item + 1] or ""
    if entry.type == "group" then
      add_hl(buf, results_ns, "PeeperPickerGroup", row, 0, nil)
    elseif item then
      local group = "PeeperPickerDefinition"
      if item.kind == "ref" then
        group = "PeeperPickerReference"
      elseif item.kind == "txt" then
        group = "PeeperPickerTextMatch"
      elseif item.kind == "com" then
        group = "PeeperPickerCommentMatch"
      end
      local label = results.display_kind(item.kind)
      local kind_start = line:find(label, 1, true)
      if kind_start then
        kind_start = kind_start - 1
        add_hl(buf, results_ns, group, row, kind_start, kind_start + #label)
      end
    end
  end
end

function M.selected_row(buf, idx)
  vim.api.nvim_buf_clear_namespace(buf, selected_ns, 0, -1)
  if idx and idx >= 1 then
    local line = vim.api.nvim_buf_get_lines(buf, idx - 1, idx, false)[1] or ""
    add_hl(buf, selected_ns, "PeeperPickerSelected", idx - 1, 0, #line)
  end
end

function M.filter_control(buf, row)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local separator = line:find(" │ ", 1, true)
  local left = separator and line:sub(1, separator - 1) or line
  local end_col = #(left:gsub("%s+$", ""))
  if end_col > 0 then
    add_hl(buf, results_ns, "PeeperPickerFilterControl", row, 0, end_col)
  end
end

function M.preview_context(buf, first_line, line_count, target_line, start_col, end_col)
  local last_line = first_line + math.max(line_count - 1, 0)
  local number_width = math.max(4, #tostring(last_line))
  for row = 0, line_count - 1 do
    local is_target = target_line == row + 1
    local marker_group = is_target and "PeeperPickerPreviewTargetMarker" or "PeeperPickerPreviewLineNumber"
    vim.api.nvim_buf_set_extmark(buf, preview_ns, row, 0, {
      virt_text = {
        { is_target and "▶" or " ", marker_group },
        { ("%" .. number_width .. "d │ "):format(first_line + row), "PeeperPickerPreviewLineNumber" },
      },
      virt_text_pos = "inline",
      right_gravity = false,
    })
  end
  if target_line then
    vim.api.nvim_buf_set_extmark(buf, preview_ns, target_line - 1, 0, {
      end_row = target_line,
      end_col = 0,
      hl_group = "PeeperPickerPreviewTargetLine",
      hl_eol = true,
      priority = 100,
    })
  end
  if target_line and start_col and end_col and end_col > start_col then
    vim.api.nvim_buf_set_extmark(buf, preview_ns, target_line - 1, start_col, {
      end_col = end_col,
      hl_group = "PeeperPickerPreviewMatch",
      priority = 120,
    })
  end
  return number_width + 4
end

function M.clear_preview(buf)
  vim.api.nvim_buf_clear_namespace(buf, preview_ns, 0, -1)
end

function M.help_actions(buf, specs)
  vim.api.nvim_buf_clear_namespace(buf, help_action_ns, 0, -1)
  for _, spec in ipairs(specs or {}) do
    if spec.start_col and spec.end_col then
      add_hl(buf, help_action_ns, spec.group or "PeeperPickerExpandAction", 0, spec.start_col, spec.end_col)
    end
  end
end

function M.header_symbols(buf, specs)
  vim.api.nvim_buf_clear_namespace(buf, header_symbol_ns, 0, -1)
  for _, spec in ipairs(specs or {}) do
    if spec.start_col and spec.end_col then
      add_hl(buf, header_symbol_ns, "PeeperPickerSymbolName", spec.row, spec.start_col, spec.end_col)
    end
  end
end

return M

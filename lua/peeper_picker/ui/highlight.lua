local M = {}

local results_ns = vim.api.nvim_create_namespace("peeper-picker-results")
local selected_ns = vim.api.nvim_create_namespace("peeper-picker-selected")
local header_symbol_ns = vim.api.nvim_create_namespace("peeper-picker-header-symbol")

-- extmark replacement for the deprecated nvim_buf_add_highlight
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

M.results_ns = results_ns

function M.ensure()
  vim.api.nvim_set_hl(0, "PeeperPickerDefinition", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerReference", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerTextMatch", { link = "NonText", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerCommentMatch", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerPath", { link = "Directory", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerSelected", { link = "Visual", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerFilterControl", { link = "WarningMsg", default = true })
  vim.api.nvim_set_hl(0, "PeeperPickerSymbolName", { link = "Underlined", default = true })
end

function M.apply_results(buf, items, end_col, row_offset, item_offset, row_count)
  local offset = row_offset or 0
  local start_item = item_offset or 1
  local stop_item = math.min(#items, start_item + (row_count or #items) - 1)
  for i = start_item, stop_item do
    local item = items[i]
    local group = "PeeperPickerDefinition"
    if item.kind == "ref" then
      group = "PeeperPickerReference"
    elseif item.kind == "txt" then
      group = "PeeperPickerTextMatch"
    elseif item.kind == "com" then
      group = "PeeperPickerCommentMatch"
    end
    local row = offset + i - start_item
    add_hl(buf, results_ns, group, row, 4, math.min(11, end_col or -1))
    add_hl(buf, results_ns, "PeeperPickerPath", row, 12, end_col or -1)
  end
end

function M.selected_row(buf, idx, end_col)
  vim.api.nvim_buf_clear_namespace(buf, selected_ns, 0, -1)
  if idx and idx >= 1 then
    add_hl(buf, selected_ns, "PeeperPickerSelected", idx - 1, 0, end_col or -1)
  end
end

function M.filter_control(buf, row, end_col)
  add_hl(buf, results_ns, "PeeperPickerFilterControl", row, 0, end_col or -1)
end

function M.preview_definition(buf, target_line, end_col)
  add_hl(buf, results_ns, "PeeperPickerDefinition", target_line - 1, 0, end_col or -1)
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

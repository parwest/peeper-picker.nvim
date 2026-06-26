local M = {}

local preview = require("peeper_picker.preview")
local text = require("peeper_picker.ui.text")

local function preview_block(state, item, row, height)
  local lines = { (state.menu and state.menu.preview_hint) or "Press f to adjust filters.", "" }
  local target_line = nil
  local first_line = nil
  if row and row.type == "group" then
    local action = row.collapsed and "expand" or "collapse"
    local detail = row.is_origin and "This is where the symbol was peeped."
      or row.is_primary_definition and "This file contains the primary definition."
      or "Result file"
    local result_count = row.result_count or 0
    local result_label = result_count == 1 and "result" or "results"
    lines = {
      row.path,
      "",
      detail,
      ("%d %s in this file."):format(result_count, result_label),
      ("Press <CR> to %s this group."):format(action),
    }
  elseif item then
    lines, target_line, first_line = preview.context(item, state.opts.preview_context)
  end

  local clipped, clipped_target, start, content_count = text.clip_lines(lines, height, target_line)
  if first_line then
    first_line = first_line + start - 1
  end
  return clipped, clipped_target, first_line, content_count
end

function M.lines(state, menu, item, row)
  return preview_block(state, item, row, menu.preview_height or menu.pane_height)
end

return M

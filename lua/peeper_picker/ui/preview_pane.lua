local M = {}

local text = require("peeper_picker.ui.text")
local preview = require("peeper_picker.preview")

local function preview_block(state, item, width, height)
  local lines = { (state.menu and state.menu.preview_hint) or "Press f to adjust filters.", "" }
  local target_line = nil
  if item then
    lines, target_line = preview.context(item, state.opts.preview_context)
  end

  local clipped = {}
  for i = 1, #lines do
    clipped[#clipped + 1] = text.fit_text(lines[i], width)
  end

  return text.clip_lines(clipped, height, target_line)
end

function M.lines(state, menu, item)
  return preview_block(state, item, menu.preview_width, menu.pane_height)
end

return M

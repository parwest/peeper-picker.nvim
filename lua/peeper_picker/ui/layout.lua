local M = {}

M.header_height = 3

local min_side_list_width = 28
local min_side_preview_width = 22
local min_stacked_width = 30
local min_pane_height = 3
local min_stacked_list_height = 3
local min_stacked_preview_height = 3
local min_help_width = 32
local min_help_height = 6

local function option_int(value, fallback)
  value = tonumber(value)
  if not value then
    return fallback
  end
  return math.max(1, math.floor(value))
end

function M.has_border(border)
  return border ~= nil and border ~= false and border ~= "" and border ~= "none"
end

local function clamp(value, min_value, max_value)
  return math.min(max_value, math.max(min_value, value))
end

function M.margin(size)
  if size >= 48 then
    return 2
  end
  if size >= 32 then
    return 1
  end
  return 0
end

local function centered_start(size, used)
  return math.max(0, math.floor((size - used) / 2))
end

local function win(row, col, width, height)
  return { row = row, col = col, width = width, height = height }
end

local function place_side_by_side(layout, bordered)
  local left, top = layout.left, layout.top
  -- each bordered window adds one row of chrome below the previous one
  local gap = bordered and 1 or 0
  local help_row = top + M.header_height + gap
  local pane_row = help_row + 1 + gap
  layout.header = win(top, left, layout.header_width, M.header_height)
  layout.help = win(help_row, left, layout.header_width, 1)
  layout.list = win(pane_row, left, layout.list_width, layout.list_height)
  layout.preview = {
    row = pane_row,
    col = left + layout.list_width + 1,
    width = layout.preview_width,
    height = layout.preview_height,
  }
end

local function place_stacked(layout, bordered)
  local left, top = layout.left, layout.top
  local gap = bordered and 1 or 0
  local help_row = top + M.header_height + gap
  local list_row = help_row + 1 + gap
  local preview_row = list_row + layout.list_height + gap
  layout.header = win(top, left, layout.header_width, M.header_height)
  layout.help = win(help_row, left, layout.header_width, 1)
  layout.list = win(list_row, left, layout.list_width, layout.list_height)
  layout.preview = win(preview_row, left, layout.preview_width, layout.preview_height)
end

local function finalize(layout, columns, lines, bordered)
  layout.left = centered_start(columns, layout.total_width)
  layout.top = centered_start(lines, layout.total_height)

  if layout.mode == "side" then
    place_side_by_side(layout, bordered)
  else
    place_stacked(layout, bordered)
  end

  return layout
end

local function side_layout(opts, available_width, available_height, bordered)
  local chrome_width = bordered and 3 or 1
  local chrome_height = bordered and (M.header_height + 5) or (M.header_height + 1)
  local min_width = min_side_list_width + min_side_preview_width + chrome_width
  local min_height = chrome_height + min_pane_height
  if available_width < min_width or available_height < min_height then
    return nil
  end

  local desired_list = option_int(opts.width, 92)
  local desired_preview = option_int(opts.preview_width, 86)
  local desired_total = desired_list + desired_preview + chrome_width
  local total_width = clamp(desired_total, min_width, available_width)
  local inner_width = total_width - chrome_width
  local preview_width = math.min(
    desired_preview,
    math.max(min_side_preview_width, math.floor(inner_width * 0.46))
  )
  local list_width = inner_width - preview_width
  if list_width < min_side_list_width then
    list_width = min_side_list_width
    preview_width = inner_width - list_width
  end
  if preview_width < min_side_preview_width then
    return nil
  end

  local max_pane_height = available_height - chrome_height
  local pane_height = clamp(option_int(opts.height, 18), min_pane_height, max_pane_height)
  local header_width = bordered and (total_width - 2) or total_width

  return {
    mode = "side",
    list_width = list_width,
    preview_width = preview_width,
    header_width = header_width,
    header_left_width = list_width,
    header_right_width = preview_width,
    list_height = pane_height,
    preview_height = pane_height,
    pane_height = pane_height,
    total_width = total_width,
    total_height = chrome_height + pane_height,
  }
end

local function stacked_layout(opts, available_width, available_height, bordered)
  local chrome_width = bordered and 2 or 0
  local chrome_height = bordered and (M.header_height + 6) or (M.header_height + 1)
  local min_width = min_stacked_width + chrome_width
  local min_height = chrome_height + min_stacked_list_height + min_stacked_preview_height
  if available_width < min_width or available_height < min_height then
    return nil
  end

  local desired_content = math.max(option_int(opts.width, 92), option_int(opts.preview_width, 86))
  local total_width = clamp(desired_content + chrome_width, min_width, available_width)
  local content_width = total_width - chrome_width
  local pane_total_max = available_height - chrome_height
  local desired_pane_total = option_int(opts.height, 18) + math.floor(option_int(opts.height, 18) / 2)
  local pane_total = clamp(desired_pane_total, min_stacked_list_height + min_stacked_preview_height, pane_total_max)

  local list_height = math.floor(pane_total * 0.58)
  list_height = clamp(list_height, min_stacked_list_height, pane_total - min_stacked_preview_height)
  local preview_height = pane_total - list_height
  if preview_height < min_stacked_preview_height then
    preview_height = min_stacked_preview_height
    list_height = pane_total - preview_height
  end

  local header_left_width = math.max(1, math.floor((content_width - 1) * 0.48))
  local header_right_width = math.max(1, content_width - header_left_width - 1)
  header_left_width = content_width - header_right_width - 1

  return {
    mode = "stacked",
    list_width = content_width,
    preview_width = content_width,
    header_width = content_width,
    header_left_width = header_left_width,
    header_right_width = header_right_width,
    list_height = list_height,
    preview_height = preview_height,
    pane_height = preview_height,
    total_width = total_width,
    total_height = chrome_height + list_height + preview_height,
  }
end

function M.menu(opts)
  opts = opts or {}
  local columns = math.max(1, vim.o.columns)
  local lines = math.max(1, vim.o.lines)
  local bordered = M.has_border(opts.border)
  local horizontal_margin = M.margin(columns)
  local vertical_margin = M.margin(lines)
  local available_width = columns - (horizontal_margin * 2)
  local available_height = lines - (vertical_margin * 2)

  local layout = side_layout(opts, available_width, available_height, bordered)
  if not layout then
    layout = stacked_layout(opts, available_width, available_height, bordered)
  end
  if not layout then
    return nil,
      ("peeper-picker.nvim: Neovim window is too small for the picker (%dx%d). "
        .. "Try a larger window or reduce the configured border/size."):format(
        columns,
        lines
      )
  end

  return finalize(layout, columns, lines, bordered)
end

function M.key_help(opts, line_count)
  opts = opts or {}
  line_count = math.max(1, line_count or 1)

  local columns = math.max(1, vim.o.columns)
  local lines = math.max(1, vim.o.lines)
  local bordered = M.has_border(opts.border)
  local chrome = bordered and 2 or 0
  local available_width = columns - (M.margin(columns) * 2) - chrome
  local available_height = lines - (M.margin(lines) * 2) - chrome
  if available_width < min_help_width or available_height < min_help_height then
    return nil,
      ("peeper-picker.nvim: Neovim window is too small for key help (%dx%d). "
        .. "Try a larger window."):format(columns, lines)
  end

  local width = clamp(104, min_help_width, available_width)
  local desired_height = math.min(line_count, 28)
  local height = clamp(desired_height, min_help_height, available_height)
  return {
    row = centered_start(lines, height + chrome),
    col = centered_start(columns, width + chrome),
    width = width,
    height = height,
  }
end

return M

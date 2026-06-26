local M = {}

function M.display_width(text)
  return vim.fn.strdisplaywidth(text)
end

function M.fit_text(text, width)
  text = text or ""
  local current = M.display_width(text)
  if current <= width then
    return text .. string.rep(" ", width - current)
  end
  if width <= 1 then
    return string.rep(" ", math.max(width, 0))
  end
  local target = width - 1
  local low, high = 0, vim.fn.strchars(text)
  while low < high do
    local mid = math.floor((low + high + 1) / 2)
    if M.display_width(vim.fn.strcharpart(text, 0, mid)) <= target then
      low = mid
    else
      high = mid - 1
    end
  end
  local fitted = vim.fn.strcharpart(text, 0, low) .. "…"
  return fitted .. string.rep(" ", width - M.display_width(fitted))
end

function M.clamp(value, min_value, max_value)
  return math.min(max_value, math.max(min_value, value))
end

function M.center_text(text, width, reserved)
  text = text or ""
  local content = M.display_width(text)
  if content >= width then
    return M.fit_text(text, width)
  end
  local effective = math.min(math.max(content, reserved or 0), width)
  local left = math.floor((width - effective) / 2)
  local right = math.max(0, width - content - left)
  return string.rep(" ", math.max(0, left)) .. text .. string.rep(" ", right)
end

function M.clip_lines(lines, height, target_line)
  local clipped = {}
  local total = #lines
  if height <= 0 then
    return clipped, nil, 1, 0
  end

  local start = 1
  if total > height then
    local above = math.floor((height - 1) / 2)
    start = M.clamp((target_line or 1) - above, 1, total - height + 1)
  end

  for i = start, math.min(total, start + height - 1) do
    clipped[#clipped + 1] = lines[i]
  end
  local content_count = #clipped
  while #clipped < height do
    clipped[#clipped + 1] = ""
  end

  if target_line then
    target_line = M.clamp(target_line - start + 1, 1, height)
  end

  return clipped, target_line, start, content_count
end

function M.set_buf_lines(buf, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

function M.set_buf_line_range(buf, first, last, lines)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, first, last, false, lines)
  vim.bo[buf].modifiable = false
end

return M

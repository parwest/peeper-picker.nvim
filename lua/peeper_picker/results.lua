local M = {}

local paths = require("peeper_picker.paths")
local preview = require("peeper_picker.preview")

local supported_encodings = {
  ["utf-8"] = true,
  ["utf-16"] = true,
  ["utf-32"] = true,
}

local kind_priority = {
  ref = 1,
  decl = 2,
  def = 3,
}

local function location_range(location)
  if location.targetUri then
    return location.targetUri, location.targetSelectionRange or location.targetRange
  end
  return location.uri, location.range
end

function M.flatten(result)
  if not result then
    return {}
  end
  if result.uri or result.targetUri then
    return { result }
  end
  return result
end

function M.add(items, seen, location, kind, position_encoding)
  local uri, range = location_range(location)
  if not uri or not range then
    return
  end
  local item = { kind = kind, uri = uri, range = range, text = nil, position_encoding = position_encoding or "utf-16" }
  local key = M.key(item)
  local existing = seen[key]
  if existing then
    if (kind_priority[kind] or 0) > (kind_priority[existing.kind] or 0) then
      existing.kind = kind
    end
    return
  end
  seen[key] = item
  table.insert(items, item)
end

function M.rank(item)
  if item.kind == "def" then
    return 1
  end
  if item.kind == "decl" then
    return 2
  end
  if item.kind == "ref" then
    return 3
  end
  if item.kind == "txt" then
    return 4
  end
  if item.kind == "com" then
    return 5
  end
  return 6
end

function M.sort(items)
  table.sort(items, function(a, b)
    local ar, br = M.rank(a), M.rank(b)
    if ar ~= br then
      return ar < br
    end
    if a.uri ~= b.uri then
      return paths.display_uri(a.uri) < paths.display_uri(b.uri)
    end
    if a.range.start.line ~= b.range.start.line then
      return a.range.start.line < b.range.start.line
    end
    return a.range.start.character < b.range.start.character
  end)
end

function M.normalize_encoding(encoding)
  if type(encoding) == "string" and supported_encodings[encoding] then
    return encoding
  end
  if type(encoding) == "table" then
    for _, value in ipairs(encoding) do
      if type(value) == "string" and supported_encodings[value] then
        return value
      end
    end
  end
  return "utf-16"
end

local function clamp(value, min_value, max_value)
  return math.min(max_value, math.max(min_value, value))
end

function M.byte_col(line, position, encoding)
  if not position then
    return nil
  end
  encoding = M.normalize_encoding(encoding)
  local ok, col = pcall(vim.str_byteindex, line, encoding, position.character, false)
  return ok and col or position.character
end

function M.byte_span(item, line, fallback_word)
  local position = item.range and item.range.start
  if not position then
    return nil, nil
  end

  local encoding = M.normalize_encoding(item.position_encoding)
  local start_col = clamp(M.byte_col(line, position, encoding), 0, #line)
  local finish = item.range and item.range["end"]
  local end_col
  if finish and finish.line == position.line then
    end_col = M.byte_col(line, finish, encoding)
  end
  if not end_col or end_col <= start_col then
    end_col = start_col + #(fallback_word or "")
  end
  return start_col, clamp(end_col, start_col, #line)
end

function M.canonical_uri(uri)
  if uri:match("^file:") then
    return vim.uri_from_fname(paths.normalize(vim.uri_to_fname(uri)))
  end
  return uri
end

function M.key(item)
  if item._key then
    return item._key
  end
  local position = item.range.start
  local column
  local encoding = M.normalize_encoding(item.position_encoding)
  if encoding == "utf-8" then
    column = position.character
  else
    local line = preview.raw_line_at(item.uri, position.line)
    column = line and M.byte_col(line, position, encoding)
      or table.concat({ encoding, position.character }, ":")
  end
  item._key = table.concat({ M.canonical_uri(item.uri), position.line, column }, ":")
  return item._key
end

local function origin_span(source)
  local line = source.line_text or ""
  local cursor = math.max(0, (source.character or 1) - 1)
  local word = source.word or ""
  if word ~= "" then
    local from = 1
    while true do
      local first, last = line:find(word, from, true)
      if not first then
        break
      end
      local start_col, end_col = first - 1, last
      if cursor >= start_col and cursor < end_col then
        return start_col, end_col
      end
      from = first + 1
    end
  end
  return cursor, math.min(#line, cursor + #word)
end

function M.mark_origin(items, source)
  if not source or not source.path or not source.line then
    return false
  end
  local origin_start, origin_end = origin_span(source)
  local best, best_score
  for _, item in ipairs(items or {}) do
    item.is_origin = nil
    local item_path = paths.normalize(vim.uri_to_fname(item.uri))
    local position = item.range and item.range.start
    if item_path == source.path and position and position.line == source.line - 1 then
      local start_col, end_col = M.byte_span(item, source.line_text or "", source.word)
      if start_col and start_col <= origin_start and end_col >= origin_end then
        local score = M.rank(item) * 100000 + math.abs(start_col - origin_start)
        if not best_score or score < best_score then
          best, best_score = item, score
        end
      end
    end
  end
  if best then
    best.is_origin = true
    return true
  end
  return false
end

function M.origin_item(source)
  if not source or not source.path or not source.line then
    return nil
  end
  local start_col, end_col = origin_span(source)
  return {
    kind = "ref",
    uri = vim.uri_from_fname(source.path),
    range = {
      start = { line = source.line - 1, character = start_col },
      ["end"] = { line = source.line - 1, character = end_col },
    },
    text = vim.trim(source.line_text or ""),
    position_encoding = "utf-8",
    is_origin = true,
  }
end

function M.display_kind(kind)
  if kind == "decl" then
    return "DECL"
  end
  if kind == "ref" then
    return "REF"
  end
  if kind == "txt" then
    return "TXT"
  end
  if kind == "com" then
    return "COM"
  end
  return "DEF"
end

function M.index_width(count)
  return math.max(4, #tostring(math.max(count or 0, 1)))
end

function M.format_grouped_line(item, idx, count)
  local marker = item.is_origin and "●" or " "
  return ("%s % " .. M.index_width(count) .. "d  %-4s %d:%d  %s"):format(
    marker,
    idx,
    M.display_kind(item.kind),
    item.range.start.line + 1,
    item.range.start.character + 1,
    item.text or ""
  )
end

return M

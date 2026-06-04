local M = {}

local paths = require("peeper_picker.paths")

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
  local key = table.concat({ uri, range.start.line, range.start.character }, ":")
  local existing = seen[key]
  if existing then
    if kind ~= "ref" then
      existing.kind = kind
    end
    return
  end
  local item = { kind = kind, uri = uri, range = range, text = nil, position_encoding = position_encoding or "utf-16" }
  seen[key] = item
  table.insert(items, item)
end

function M.rank(item)
  if item.kind == "com" then
    return 4
  end
  if item.kind == "txt" then
    return 3
  end
  return item.kind == "ref" and 2 or 1
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

function M.key(item)
  return table.concat({ item.uri, item.range.start.line, item.range.start.character }, ":")
end

function M.display_kind(kind)
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

function M.format_line(item, idx, count)
  return ("% " .. M.index_width(count) .. "d  %-7s %s:%d:%d  %s"):format(
    idx,
    M.display_kind(item.kind),
    paths.display_uri(item.uri),
    item.range.start.line + 1,
    item.range.start.character + 1,
    item.text or ""
  )
end

return M

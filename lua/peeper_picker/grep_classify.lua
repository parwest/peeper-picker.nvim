local M = {}

local comment_prefixes = {
  "^//",
  "^#",
  "^%-%-",
  "^%*",
  "^/%*",
  "^<!%-%-",
  "^;",
  "^%%",
  "^!",
  "^rem%s",
  "^REM%s",
}

local text_extensions = {
  [".md"] = true,
  [".txt"] = true,
  [".rst"] = true,
  [".org"] = true,
  [".adoc"] = true,
}

local max_treesitter_source_bytes = 512 * 1024

local function file_ext(path)
  return (path:match("(%.[^./]+)$") or ""):lower()
end

local function line_is_comment(line)
  local t = vim.trim(line or "")
  for _, pat in ipairs(comment_prefixes) do
    if t:find(pat) then
      return true
    end
  end
  return false
end

local function node_kind(node)
  local cur = node
  for _ = 1, 8 do
    if not cur then
      break
    end
    local node_type = cur:type()
    if node_type:find("comment", 1, true) then
      return "com"
    end
    if node_type:find("string", 1, true) or node_type:find("template", 1, true) then
      return "txt"
    end
    cur = cur:parent()
  end
  return "ref"
end

local function source_tree(fname, source)
  if not vim.treesitter or not vim.treesitter.get_string_parser then
    return nil
  end
  local ok_filetype, filetype = pcall(vim.filetype.match, { filename = fname })
  if not ok_filetype or not filetype or filetype == "" then
    return nil
  end
  local lang = filetype
  if vim.treesitter.language and vim.treesitter.language.get_lang then
    lang = vim.treesitter.language.get_lang(filetype) or filetype
  end
  local ok_parser, parser = pcall(vim.treesitter.get_string_parser, source, lang)
  if not ok_parser or not parser then
    return nil
  end
  local ok_parse, trees = pcall(function()
    return parser:parse(true)
  end)
  local tree = ok_parse and trees and trees[1] or nil
  return tree and tree:root() or nil
end

local function fallback_kind(fname, line_text)
  if text_extensions[file_ext(fname)] then
    return "txt"
  end
  if line_is_comment(line_text) then
    return "com"
  end
  return "ref"
end

function M.classifier(fname, source)
  local prose = text_extensions[file_ext(fname)] == true
  local root = not prose and source and #source <= max_treesitter_source_bytes and source_tree(fname, source) or nil

  return function(items, first, last)
    first = first or 1
    last = last or #items
    if first > last or first > #items then
      return
    end

    for i = first, math.min(last, #items) do
      local item = items[i]
      local position = item.range and item.range.start
      local kind
      if prose then
        kind = "txt"
      elseif root and position then
        local row = position.line
        local col = position.character
        local ok_node, node = pcall(root.named_descendant_for_range, root, row, col, row, col + 1)
        if ok_node and node then
          kind = node_kind(node)
        end
      end
      item.kind = kind or fallback_kind(fname, item.text)
    end
  end
end

function M.classify_source(fname, source, items, first, last)
  first = first or 1
  if first > #items then
    return
  end

  M.classifier(fname, source)(items, first, last)
end

return M

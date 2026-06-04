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

local function treesitter_kind(fname, lnum, col)
  local bufnr = vim.fn.bufnr(fname)
  if bufnr == -1 then
    return nil
  end
  if not vim.treesitter or not vim.treesitter.get_node then
    return nil
  end
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { lnum - 1, col - 1 } })
  if not ok or not node then
    return nil
  end
  if node:type():find("comment", 1, true) then
    return "com"
  end
  local cur = node
  for _ = 1, 6 do
    local t = cur:type()
    if t:find("string", 1, true) or t:find("template", 1, true) then
      return "txt"
    end
    cur = cur:parent()
    if not cur then
      break
    end
  end
  return "ref"
end

-- Returns "com", "ref", or "txt" for a grep match.
function M.classify(fname, lnum, col, line_text)
  local ts = treesitter_kind(fname, lnum, col)
  if ts then
    return ts
  end
  if text_extensions[file_ext(fname)] then
    return "txt"
  end
  if line_is_comment(line_text) then
    return "com"
  end
  return "ref"
end

return M

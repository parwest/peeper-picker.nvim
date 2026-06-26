local M = {}

local uv = vim.uv
local sep = package.config:sub(1, 1)
local is_windows = sep == "\\"

local function trim_trailing_sep(path)
  if not path or path == "" then
    return path
  end
  if is_windows and path:match("^%a:[/\\]$") then
    return path:gsub("/", "\\")
  end
  if path == sep then
    return path
  end
  return (path:gsub("[/\\]+$", ""))
end

local function comparable(path)
  path = trim_trailing_sep(path or "") or ""
  if is_windows then
    return path:gsub("/", "\\"):lower()
  end
  return path
end

function M.separator()
  return sep
end

local normalize_cache = {}
local display_uri_cache = {}

function M.reset_cache()
  normalize_cache = {}
  display_uri_cache = {}
end

function M.normalize(path)
  local cached = normalize_cache[path]
  if cached ~= nil then
    return cached
  end
  local normalized = vim.fn.fnamemodify(path, ":p")
  normalized = uv.fs_realpath(normalized) or normalized
  if is_windows then
    normalized = normalized:gsub("/", "\\")
  end
  normalized = trim_trailing_sep(normalized)
  normalize_cache[path] = normalized
  return normalized
end

function M.is_inside(path, root)
  if not path or not root or root == "" then
    return false
  end
  local normalized_path = comparable(M.normalize(path))
  local normalized_root = comparable(M.normalize(root))
  if normalized_path == normalized_root then
    return true
  end
  local prefix = normalized_root:sub(-1) == sep and normalized_root or normalized_root .. sep
  return normalized_path:sub(1, #prefix) == prefix
end

function M.relative_to(path, root)
  if not M.is_inside(path, root) then
    return nil
  end
  local normalized_path = M.normalize(path)
  local normalized_root = M.normalize(root)
  if comparable(normalized_path) == comparable(normalized_root) then
    return ""
  end
  return normalized_path:sub(#normalized_root + 2)
end

function M.parent(path)
  return M.normalize(vim.fn.fnamemodify(path, ":p:h"))
end

local function git_root(start_path)
  local start = start_path and M.parent(start_path) or vim.fn.getcwd()
  local found = vim.fs.find(".git", { upward = true, path = start, limit = 1 })[1]
  return found and M.normalize(vim.fs.dirname(found)) or nil
end

local project_markers = {
  "package.json",
  "tsconfig.json",
  "jsconfig.json",
  "deno.json",
  "deno.jsonc",
  "pyproject.toml",
  "Cargo.toml",
  "go.mod",
}

local function lsp_workspace_root(bufnr, current_path)
  local best = nil
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    local roots = {}
    if client.config and client.config.root_dir then
      table.insert(roots, client.config.root_dir)
    end
    for _, folder in ipairs(client.workspace_folders or {}) do
      table.insert(roots, folder.uri and vim.uri_to_fname(folder.uri) or folder.name)
    end
    for _, root in ipairs(roots) do
      local normalized = M.normalize(root)
      local stat = uv.fs_stat(normalized)
      if stat and stat.type ~= "directory" then
        normalized = M.parent(normalized)
      end
      if M.is_inside(current_path, normalized) and (not best or #normalized > #best) then
        best = normalized
      end
    end
  end
  return best
end

local function marker_root(start_path)
  local start = start_path and M.parent(start_path) or vim.fn.getcwd()
  local found = vim.fs.find(project_markers, { upward = true, path = start, limit = 1 })[1]
  return found and M.parent(found) or nil
end

local function too_broad(path)
  if not path then
    return true
  end
  local home = M.normalize(vim.fn.expand("~"))
  return M.is_inside(home, path)
end

local function valid_root(root, current_path)
  if not root then
    return nil
  end
  local normalized = M.normalize(root)
  if too_broad(normalized) then
    return nil
  end
  if current_path and current_path ~= "" and not M.is_inside(current_path, normalized) then
    return nil
  end
  return normalized
end

function M.workspace_root(bufnr, current_path)
  local start = current_path or vim.fn.getcwd()

  local marker = valid_root(marker_root(start), current_path)
  if marker then
    return marker
  end

  -- lsp can report a single-file root; prefer the git root for a wider search
  local lsp_root = valid_root(lsp_workspace_root(bufnr, current_path), current_path)
  local git = valid_root(git_root(start), current_path)
  local current_dir = current_path and current_path ~= "" and M.parent(current_path) or nil

  if
    lsp_root
    and git
    and current_dir
    and comparable(lsp_root) == comparable(current_dir)
    and M.is_inside(lsp_root, git)
    and comparable(lsp_root) ~= comparable(git)
  then
    return git
  end

  if lsp_root then
    return lsp_root
  end

  if git then
    return git
  end

  if current_path and current_path ~= "" then
    return M.parent(current_path)
  end
  return M.normalize(vim.fn.getcwd())
end

function M.display_uri(uri)
  local cached = display_uri_cache[uri]
  if cached ~= nil then
    return cached
  end
  local path = M.normalize(vim.uri_to_fname(uri))
  local cwd = M.normalize(vim.fn.getcwd())
  local result = path
  local relative = M.relative_to(path, cwd)
  if relative and relative ~= "" then
    result = relative
  else
    local home = M.normalize(vim.fn.expand("~"))
    relative = M.relative_to(path, home)
    if relative and relative ~= "" then
      result = "~" .. sep .. relative
    end
  end
  display_uri_cache[uri] = result
  return result
end

function M.display_path(path)
  return M.display_uri(vim.uri_from_fname(path))
end

function M.display_path_from_root(path, root)
  if root then
    local relative = M.relative_to(path, root)
    if relative and relative ~= "" then
      return M.display_path(root) .. sep .. relative
    end
  end
  return M.display_path(path)
end

function M.find_open_window(path)
  local target = comparable(M.normalize(path))
  for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      if name ~= "" and comparable(M.normalize(name)) == target then
        return tabpage, win
      end
    end
  end
end

function M.normalize_extension(value)
  local ext = vim.trim(value or ""):lower()
  if ext == "" then
    return ""
  end
  return ext:sub(1, 1) == "." and ext or "." .. ext
end

return M

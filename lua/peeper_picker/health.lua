local M = {}

local lsp = require("peeper_picker.lsp")

local minimum_version = "0.12.2"

local function has_minimum_nvim()
  local version = vim.version()
  if version.major > 0 then
    return true
  end
  if version.minor > 12 then
    return true
  end
  if version.minor < 12 then
    return false
  end
  return version.patch >= 2
end

-- :checkhealth runs inside its own scratch buffer, which never has LSP clients
-- attached. Fall back to the alternate buffer (the file the user was editing
-- when they invoked :checkhealth) so the LSP checks reflect a real buffer.
local function target_buffer()
  local alt = vim.fn.bufnr("#")
  if alt > 0 and vim.api.nvim_buf_is_valid(alt) then
    return alt
  end
  return vim.api.nvim_get_current_buf()
end

local function client_names(clients)
  local names = {}
  for _, client in ipairs(clients) do
    table.insert(names, client.name or ("client " .. client.id))
  end
  table.sort(names)
  return table.concat(names, ", ")
end

function M.check()
  vim.health.start("peeper-picker.nvim")

  if has_minimum_nvim() then
    vim.health.ok(("Neovim %s is supported"):format(tostring(vim.version())))
  else
    vim.health.error(("Neovim %s or newer is required"):format(minimum_version))
  end

  local bufnr = target_buffer()
  local all_clients = vim.lsp.get_clients({ bufnr = bufnr })
  if #all_clients == 0 then
    vim.health.warn("No LSP clients are attached to the current buffer")
    return
  end

  vim.health.ok(("Attached LSP clients: %s"):format(client_names(all_clients)))

  local supported = {}
  for label, method in pairs(lsp.methods) do
    local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
    if #clients > 0 then
      table.insert(supported, ("%s (%s)"):format(method, client_names(clients)))
    end
  end
  table.sort(supported)

  if #supported == 0 then
    vim.health.warn("No attached LSP client supports declaration, definition, or references")
  else
    vim.health.ok("Supported LSP methods: " .. table.concat(supported, ", "))
  end
end

return M


local M = {}

local results = require("peeper_picker.results")
local classify = require("peeper_picker.lsp.classify")

local methods = {
  decl = "textDocument/declaration",
  def = "textDocument/definition",
  ref = "textDocument/references",
}

M.methods = methods

-- Symbol-kind detection lives in lsp.classify; re-export for callers.
M.source_symbol = classify.source_symbol

local function client_position_params(client, bufnr, params_by_encoding)
  local encoding = client.offset_encoding or "utf-16"
  local params = vim.deepcopy(params_by_encoding[encoding] or params_by_encoding["utf-16"])
  params.textDocument.uri = vim.uri_from_bufnr(bufnr)
  return params, encoding
end

local function request_all(bufnr, method, make_params, callback)
  local clients = vim.lsp.get_clients({ bufnr = bufnr, method = method })
  if #clients == 0 then
    callback({})
    return
  end

  local locations = {}
  local pending = #clients
  for _, client in ipairs(clients) do
    local params, encoding = make_params(client)
    local ok = client:request(method, params, function(_, result)
      if result then
        for _, location in ipairs(results.flatten(result)) do
          table.insert(locations, { location = location, encoding = encoding })
        end
      end
      pending = pending - 1
      if pending == 0 then
        callback(locations)
      end
    end, bufnr)
    if not ok then
      pending = pending - 1
      if pending == 0 then
        callback(locations)
      end
    end
  end
end

function M.supported_count(bufnr)
  local count = 0
  for _, method in pairs(methods) do
    if #vim.lsp.get_clients({ bufnr = bufnr, method = method }) > 0 then
      count = count + 1
    end
  end
  return count
end

-- Each method we collect from: how to detect support, and how to build its
-- request params (references needs includeDeclaration).
local collectors = {
  { kind = "decl", method = methods.decl },
  { kind = "def", method = methods.def },
  {
    kind = "ref",
    method = methods.ref,
    augment = function(params)
      params.context = { includeDeclaration = true }
      return params
    end,
  },
}

function M.collect(bufnr, params_by_encoding, on_done)
  local items, seen = {}, {}

  -- Snapshot which collectors actually have a supporting client *now*, so the
  -- pending count reflects the requests we are about to launch. Re-checking the
  -- client count per collector after deriving pending from a separate pre-flight
  -- count would leave on_done unfired if a client dropped in between.
  local active = {}
  for _, collector in ipairs(collectors) do
    if #vim.lsp.get_clients({ bufnr = bufnr, method = collector.method }) > 0 then
      table.insert(active, collector)
    end
  end

  local pending = #active
  if pending == 0 then
    on_done(items)
    return
  end

  local function finish()
    pending = pending - 1
    if pending > 0 then
      return
    end
    results.sort(items)
    on_done(items)
  end

  for _, collector in ipairs(active) do
    request_all(bufnr, collector.method, function(client)
      local params, encoding = client_position_params(client, bufnr, params_by_encoding)
      if collector.augment then
        params = collector.augment(params)
      end
      return params, encoding
    end, function(locations)
      for _, entry in ipairs(locations) do
        results.add(items, seen, entry.location, collector.kind, entry.encoding)
      end
      finish()
    end)
  end
end

return M

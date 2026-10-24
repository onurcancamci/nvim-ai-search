-- Provider registry: argv resolution and dispatch.

local config = require("ai-search.config")

local M = {}

M.providers = {
  pi = require("ai-search.providers.pi"),
  qmd = require("ai-search.providers.qmd"),
  grep = require("ai-search.providers.grep"),
}

--- Build the argv for a provider, substituting {query} in place or appending it.
---@param pcfg table
---@param query string
---@return string[]
function M.argv(pcfg, query)
  local argv = { pcfg.command }
  local substituted = false

  for _, arg in ipairs(pcfg.params or {}) do
    if type(arg) == "string" and arg:find("{query}", 1, true) then
      argv[#argv + 1] = (
        arg:gsub("{query}", function()
          return query
        end)
      )
      substituted = true
    else
      argv[#argv + 1] = arg
    end
  end

  if not substituted then
    argv[#argv + 1] = query
  end

  return argv
end

---@param name string
---@return table|nil
function M.get(name)
  return M.providers[name]
end

---@param name string
---@return boolean
function M.exists(name)
  return M.providers[name] ~= nil and config.get().providers[name] ~= nil
end

return M

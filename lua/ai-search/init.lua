-- ai-search: AI-backed codebase search for Neovim.
--
-- Public surface: setup(), open(), run(), cancel(). Everything else is reached
-- through the user commands :AISearch, :AISearchRun and :AISearchCancel.

local config = require("ai-search.config")
local picker = require("ai-search.picker")
local prompt = require("ai-search.prompt")
local providers = require("ai-search.providers")
local results = require("ai-search.results")
local spinner = require("ai-search.spinner")

local M = {}

local state = {
  gen = 0,
  handle = nil,
  spinner = nil,
  invocation_provider = nil,
}

local function stop_spinner()
  if state.spinner then
    state.spinner.stop()
    state.spinner = nil
  end
end

---@param msg string
---@param level number|nil
local function notify(msg, level)
  vim.notify("ai-search: " .. msg, level or vim.log.levels.INFO)
end

---@param provider string
---@return boolean
local function is_known_provider(provider)
  return config.get().providers[provider] ~= nil
end

---@param provider string
local function report_unknown_provider(provider)
  notify(
    string.format(
      "unknown provider %q; configured providers: %s",
      provider,
      table.concat(vim.tbl_keys(config.get().providers), ", ")
    ),
    vim.log.levels.ERROR
  )
end

---@param opts table|nil
---@return table
function M.setup(opts)
  config.setup(opts)
  return M
end

--- Open the prompt.
---@param provider string|nil optional provider for this invocation
function M.open(provider)
  if prompt.is_open() then
    prompt.focus()
    return
  end

  if provider and provider ~= "" and not is_known_provider(provider) then
    report_unknown_provider(provider)
    return
  end

  state.invocation_provider = (provider and provider ~= "") and provider or nil
  prompt.open()
end

--- Submit the open prompt with a provider.
---@param provider string|nil
function M.run(provider)
  if not prompt.is_open() then
    notify("the prompt is not open; use :AISearch first", vim.log.levels.WARN)
    return
  end

  local query = prompt.get_text()
  if query == "" then
    prompt.set_status("query is empty", "ErrorMsg")
    return
  end

  local cfg = config.get()
  local name = (provider and provider ~= "") and provider
    or state.invocation_provider
    or cfg.default_provider

  if not is_known_provider(name) then
    prompt.set_status("unknown provider: " .. name, "ErrorMsg")
    return
  end

  local pcfg = cfg.providers[name]
  if pcfg.enabled == false then
    prompt.set_status(("provider %q is disabled"):format(name), "ErrorMsg")
    return
  end

  local implementation = providers.get(name)
  if not implementation then
    prompt.set_status(
      ("provider %q is not implemented"):format(name),
      "ErrorMsg"
    )
    return
  end

  if state.handle then
    state.handle.cancel()
    state.handle = nil
  end
  stop_spinner()

  state.gen = state.gen + 1
  local gen = state.gen

  local ctx = {
    query = query,
    cwd = pcfg.cwd or vim.fn.getcwd(),
    bufnr = vim.api.nvim_get_current_buf(),
  }

  state.spinner = spinner.start(function(frame)
    prompt.set_status(("%s searching with %s"):format(frame, name), "Comment")
  end)

  state.handle = implementation.run(ctx, pcfg, function(err, entries)
    if gen ~= state.gen then
      return
    end

    stop_spinner()
    state.handle = nil

    if err then
      prompt.set_status(err, "ErrorMsg")
      return
    end

    local final = results.finalize(entries or {}, {
      cwd = ctx.cwd,
      max = config.get().max_results,
    })

    if #final == 0 then
      prompt.set_status("no results", "ErrorMsg")
      return
    end

    prompt.close()
    picker.open(final, {
      query = ctx.query,
      provider = name,
      cwd = ctx.cwd,
    })
  end)
end

--- Cancel the running job and close the prompt.
function M.cancel()
  state.gen = state.gen + 1
  stop_spinner()

  if state.handle then
    state.handle.cancel()
    state.handle = nil
  end

  state.invocation_provider = nil
  prompt.close()
end

return M

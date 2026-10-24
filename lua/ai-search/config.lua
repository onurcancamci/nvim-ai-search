-- Configuration defaults, merging and validation for ai-search.

local pi = require("ai-search.providers.pi")

local M = {}

M.default_pi_params = {
  "-p",
  "--no-session",
  "--no-context-files",
  "-t",
  "grep,find,read,ls",
  "--system-prompt",
  pi.system_prompt,
  "--",
}

M.defaults = {
  default_provider = "pi",
  picker = "auto", -- "auto" | "snacks" | "telescope"
  max_results = 100,
  timeout = 90000,

  prompt = {
    width = 0.6, -- fraction of columns
    min_width = 60,
    border = "rounded",
    title = "AI Search",
  },

  hints = {
    enabled = true,
    max_items = 8,
    prettify = true,
  },

  providers = {
    pi = {
      command = "pi",
      params = M.default_pi_params,
      timeout = 90000,
    },

    qmd = {
      command = "qmd",
      params = {
        "query",
        "{query}",
        "-n",
        "40",
        "--format",
        "json",
        "--full-path",
        "--chunk-strategy",
        "auto",
      },
      scope = "code", -- "code" | "docs"
      collections = { code = {}, docs = {} },
      timeout = 30000,
    },

    grep = {
      command = "rg",
      params = {
        "--vimgrep",
        "--smart-case",
        "--hidden",
        "-g",
        "!.git",
        "--",
        "{query}",
        ".",
      },
      timeout = 10000,
    },
  },
}

M.options = vim.deepcopy(M.defaults)

M.known_providers = { "pi", "qmd", "grep" }

-- Deterministic display order; pairs() does not preserve insertion order.
M.provider_order = { "pi", "qmd", "grep" }

local provider_keys = {
  command = true,
  params = true,
  timeout = true,
  env = true,
  cwd = true,
  enabled = true,
  scope = true,
  collections = true,
}

local function is_list(t)
  if vim.islist then
    return vim.islist(t)
  end
  return vim.tbl_islist(t)
end

local function merge_table(dst, src)
  for k, v in pairs(src) do
    if
      type(v) == "table"
      and not is_list(v)
      and type(dst[k]) == "table"
      and not is_list(dst[k])
    then
      merge_table(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

local function fail(fmt, ...)
  error("ai-search: " .. string.format(fmt, ...), 0)
end

local function validate_provider(name, pcfg, cfg)
  if type(pcfg) ~= "table" then
    fail(
      "providers.%s must be a table (got %s), e.g. { command = 'x', params = { '{query}' } }",
      name,
      type(pcfg)
    )
  end

  if not vim.tbl_contains(M.known_providers, name) then
    fail(
      "unknown provider %q; known providers are: %s",
      name,
      table.concat(M.known_providers, ", ")
    )
  end

  if type(pcfg.command) ~= "string" or pcfg.command == "" then
    fail("providers.%s.command must be a non-empty string", name)
  end

  if pcfg.params ~= nil and type(pcfg.params) ~= "table" then
    fail("providers.%s.params must be a list of strings", name)
  end

  if pcfg.timeout ~= nil and type(pcfg.timeout) ~= "number" then
    fail("providers.%s.timeout must be a number of milliseconds", name)
  end

  if pcfg.scope ~= nil and pcfg.scope ~= "code" and pcfg.scope ~= "docs" then
    fail("providers.%s.scope must be 'code' or 'docs'", name)
  end

  for k in pairs(pcfg) do
    if not provider_keys[k] then
      vim.notify(
        string.format(
          "ai-search: unknown key %q in providers.%s (ignored)",
          k,
          name
        ),
        vim.log.levels.WARN
      )
    end
  end

  if not cfg.providers[cfg.default_provider] then
    fail(
      "default_provider %q is not a configured provider",
      cfg.default_provider
    )
  end
end

local function validate(cfg)
  if
    not (
      cfg.picker == "auto"
      or cfg.picker == "snacks"
      or cfg.picker == "telescope"
    )
  then
    fail("picker must be 'auto', 'snacks' or 'telescope'")
  end
  if type(cfg.max_results) ~= "number" or cfg.max_results < 1 then
    fail("max_results must be a positive number")
  end
  if type(cfg.timeout) ~= "number" or cfg.timeout <= 0 then
    fail("timeout must be a positive number of milliseconds")
  end
  if type(cfg.prompt) ~= "table" then
    fail("prompt must be a table")
  end
  if type(cfg.hints) ~= "table" then
    fail("hints must be a table")
  end
  for name, pcfg in pairs(cfg.providers) do
    validate_provider(name, pcfg, cfg)
  end
end

---@param opts table|nil
---@return table
function M.setup(opts)
  opts = opts or {}
  local cfg = vim.deepcopy(M.defaults)

  for k, v in pairs(opts) do
    if k == "providers" then
      -- merged below, params replaced wholesale
    elseif k == "prompt" or k == "hints" then
      if type(v) ~= "table" then
        fail("%s must be a table", k)
      end
      merge_table(cfg[k], v)
    else
      cfg[k] = v
    end
  end

  for name, pcfg in pairs(opts.providers or {}) do
    if type(pcfg) ~= "table" then
      fail(
        "providers.%s must be a table (got %s); the string shorthand is not supported",
        name,
        type(pcfg)
      )
    end
    local target = cfg.providers[name]
    if target then
      for k, v in pairs(pcfg) do
        if k == "params" then
          target.params = v
        elseif
          type(v) == "table"
          and not is_list(v)
          and type(target[k]) == "table"
          and not is_list(target[k])
        then
          merge_table(target[k], v)
        else
          target[k] = v
        end
      end
    else
      cfg.providers[name] = pcfg
    end
  end

  validate(cfg)
  M.options = cfg
  return cfg
end

---@return table
function M.get()
  return M.options
end

return M

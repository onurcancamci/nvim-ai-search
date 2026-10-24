-- qmd provider: hybrid (BM25 + vector + rerank) search over a qmd index.
--
-- The plugin only runs the command. Creating, updating and inspecting the index
-- and its collections is entirely the user's responsibility.

local job = require("ai-search.job")

local M = {}

local function first_line(text)
  local line = text and text:match("[^\r\n]+")
  return line and vim.trim(line) or nil
end

--- Collection filters for the configured scope. Empty lists append nothing.
---@param pcfg table
---@return string[]
local function scope_filters(pcfg)
  local collections = type(pcfg.collections) == "table" and pcfg.collections
    or {}
  local names = {}

  if pcfg.scope == "docs" then
    names = collections.docs or {}
  else
    names = collections.code or {}
  end

  local filters = {}
  for _, name in ipairs(names) do
    if type(name) == "string" and name ~= "" then
      filters[#filters + 1] = "-c"
      filters[#filters + 1] = name
    end
  end
  return filters
end

---@param stdout string
---@return table|nil
local function decode(stdout)
  local ok, decoded = pcall(vim.json.decode, stdout)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  if type(decoded.results) == "table" then
    decoded = decoded.results
  end

  local entries = {}
  for _, raw in ipairs(decoded) do
    if type(raw) == "table" then
      local file = raw.file or raw.path or raw.filename
      if type(file) == "string" and file ~= "" then
        entries[#entries + 1] = {
          file = file,
          lnum = tonumber(raw.line) or tonumber(raw.start_line) or 1,
          text = raw.title or raw.snippet,
          score = tonumber(raw.score),
          source = "qmd",
        }
      end
    end
  end

  return entries
end

---@param ctx table
---@param pcfg table
---@param cb fun(err: string|nil, entries: table[]|nil)
---@return table handle
function M.run(ctx, pcfg, cb)
  local argv = require("ai-search.providers").argv(pcfg, ctx.query)

  -- Keep filters adjacent to the command so they never trail the positionals.
  for _, arg in ipairs(scope_filters(pcfg)) do
    argv[#argv + 1] = arg
  end

  return job.start(argv, {
    cwd = ctx.cwd,
    env = pcfg.env,
    timeout = pcfg.timeout or 30000,
    on_exit = function(res)
      if res.cancelled then
        return cb(res.timed_out and "timed out" or "cancelled")
      end

      if res.code ~= 0 and res.code ~= nil then
        return cb(first_line(res.stderr) or ("qmd exited with " .. res.code))
      end

      local entries = decode(res.stdout)
      if not entries then
        return cb("qmd returned unparsable output")
      end

      cb(nil, entries)
    end,
  })
end

return M

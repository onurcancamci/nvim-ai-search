-- pi provider: agentic code search through the `pi` CLI in print mode.
--
-- pi answers in prose by default, so the result contract is enforced with a
-- dedicated system prompt and parsed back into locations. No pi extension is
-- used or shipped: pi extensions are TypeScript/JavaScript only, and this plugin
-- stays Lua.

local job = require("ai-search.job")

local M = {}

M.system_prompt = table.concat({
  "You are a codebase search engine.",
  "Use the grep, find, read and ls tools to locate code that matches the user's query.",
  "Search the current working directory.",
  "",
  "Reply with only a JSON array. No prose, no markdown, no code fences, no explanation.",
  "Each element is an object with exactly two keys:",
  '  "file": a path to a file, relative to the current working directory or absolute',
  '  "line": the 1-based line number inside that file',
  "",
  "Return [] when nothing matches.",
  "Never invent paths or line numbers, and never report a line you have not seen.",
  "Return at most 40 elements, most relevant first.",
}, "\n")

local function first_line(text)
  if not text or text == "" then
    return nil
  end
  local line = text:match("[^\r\n]+")
  if not line then
    return nil
  end
  line = vim.trim(line)
  return line ~= "" and line or nil
end

--- Scan for the first balanced JSON array, ignoring brackets inside strings.
---@param text string
---@return string|nil
local function first_json_array(text)
  local start = text:find("[", 1, true)
  if not start then
    return nil
  end

  local depth, in_string, escaped = 0, false, false
  for i = start, #text do
    local c = text:sub(i, i)
    if in_string then
      if escaped then
        escaped = false
      elseif c == "\\" then
        escaped = true
      elseif c == '"' then
        in_string = false
      end
    elseif c == '"' then
      in_string = true
    elseif c == "[" or c == "{" then
      depth = depth + 1
    elseif c == "]" or c == "}" then
      depth = depth - 1
      if depth == 0 then
        return text:sub(start, i)
      end
    end
  end

  return nil
end

---@param raw any
---@return string|nil file, number|nil line
local function read_entry(raw)
  if type(raw) ~= "table" then
    return nil, nil
  end

  local file = raw.file or raw.path or raw.filename
  if type(file) ~= "string" or file == "" then
    return nil, nil
  end

  local line = tonumber(raw.line or raw.lnum or raw.line_number)
  if not line and type(raw.loc) == "table" then
    line = tonumber(raw.loc.line) or tonumber(raw.loc[1])
  end

  -- tolerate "path:12" packed into the file field
  local packed_file, packed_line = file:match("^(.-):(%d+)$")
  if packed_file and packed_file ~= "" and not line then
    file, line = packed_file, tonumber(packed_line)
  end

  return file, line
end

---@param stdout string
---@return table[]|nil
local function parse_json(stdout)
  local blob = first_json_array(stdout)
  if not blob then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, blob)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  if decoded.results then
    decoded = decoded.results
  end

  local entries = {}
  for _, raw in ipairs(decoded) do
    local file, line = read_entry(raw)
    if file then
      entries[#entries + 1] = { file = file, lnum = line }
    end
  end
  return entries
end

--- Last resort when the model answered in prose: pick out "path:line" pairs.
---@param stdout string
---@return table[]
local function parse_loose(stdout)
  local entries, seen = {}, {}
  for file, line in stdout:gmatch("([%w%._/%-]+%.%w+):(%d+)") do
    local key = file .. ":" .. line
    if not seen[key] then
      seen[key] = true
      entries[#entries + 1] = { file = file, lnum = tonumber(line) }
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

  return job.start(argv, {
    cwd = ctx.cwd,
    env = pcfg.env,
    timeout = pcfg.timeout or 90000,
    on_exit = function(res)
      if res.cancelled then
        return cb(res.timed_out and "timed out" or "cancelled")
      end

      if res.code ~= 0 and res.code ~= nil then
        return cb(first_line(res.stderr) or ("pi exited with " .. res.code))
      end

      local entries = parse_json(res.stdout) or parse_loose(res.stdout)
      if not entries then
        return cb("pi returned no parsable results")
      end

      for _, entry in ipairs(entries) do
        entry.source = "pi"
        entry.col = 1
      end

      cb(nil, entries)
    end,
  })
end

return M

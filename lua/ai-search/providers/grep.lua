-- grep provider: plain text search through ripgrep.

local job = require("ai-search.job")

local M = {}

local function first_line(text)
  local line = text and text:match("[^\r\n]+")
  return line and vim.trim(line) or nil
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
    timeout = pcfg.timeout or 10000,
    on_exit = function(res)
      if res.cancelled then
        return cb(res.timed_out and "timed out" or "cancelled")
      end

      -- rg exits 1 when there are simply no matches.
      if res.code ~= 0 and res.code ~= 1 then
        return cb(
          first_line(res.stderr) or ("grep exited with " .. tostring(res.code))
        )
      end

      local entries = {}
      for line in res.stdout:gmatch("[^\r\n]+") do
        local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
        if file then
          entries[#entries + 1] = {
            file = file,
            lnum = tonumber(lnum),
            col = tonumber(col),
            text = text,
            source = "grep",
          }
        end
      end

      cb(nil, entries)
    end,
  })
end

return M

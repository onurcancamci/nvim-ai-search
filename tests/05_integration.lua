-- End-to-end: commands, provider dispatch, generation guard, quickfix fallback.

local H = dofile(
  vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/util.lua"
)
H.bootstrap()

local ai = require("ai-search")
local config = require("ai-search.config")
local prompt = require("ai-search.prompt")
local ns = vim.api.nvim_create_namespace("ai-search-prompt")

local dir = H.tmpdir()
vim.fn.mkdir(dir .. "/lua", "p")
vim.fn.writefile({ "local foo = 1", "local bar = 2" }, dir .. "/lua/a.lua")
vim.fn.writefile({ "local baz = 3" }, dir .. "/lua/b.lua")
vim.cmd("cd " .. dir)

local function status()
  local marks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
  if #marks == 0 then
    return nil
  end
  local row = marks[1][4].virt_lines[1]
  return row
    and table.concat(
      vim.tbl_map(function(c)
        return c[1]
      end, row),
      ""
    )
end

local function write_query(text)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { text, "" })
end

ai.setup({ default_provider = "grep", picker = "auto" })
H.equal(
  "no picker available -> quickfix",
  require("ai-search.picker").resolve(),
  "quickfix"
)

-- :AISearch is registered by plugin registration
local commands = vim.api.nvim_get_commands({})
H.check(":AISearch exists", commands.AISearch ~= nil)
H.check(":AISearchRun exists", commands.AISearchRun ~= nil)
H.check(":AISearchCancel exists", commands.AISearchCancel ~= nil)
H.equal(":AISearchRun is optional-arg", commands.AISearchRun.nargs, "?")

-- running without an open prompt warns and does nothing
local notifications = {}
local original = vim.notify
vim.notify = function(msg, level)
  notifications[#notifications + 1] = { msg = msg, level = level }
end
vim.cmd("AISearchRun")
vim.notify = original
H.equal("run without prompt notifies", #notifications, 1)
H.match(
  "run without prompt message",
  notifications[1].msg,
  "prompt is not open"
)

-- full flow with the default provider
vim.cmd("AISearch")
H.wait_for(function()
  return prompt.is_open()
end, 2000)
H.check("prompt opened by command", prompt.is_open())

write_query("bar")
vim.cmd("AISearchRun")
H.wait_for(function()
  return #vim.fn.getqflist() > 0
end, 10000)

H.equal("prompt closed after results", prompt.is_open(), false)
local qf = vim.fn.getqflist()
H.equal("quickfix item count", #qf, 1)
H.equal("quickfix line", qf[1].lnum, 2)
H.match("quickfix file", vim.fn.bufname(qf[1].bufnr), "a%.lua$")

-- empty results keep the prompt open with the query intact
vim.cmd("AISearch")
H.wait_for(function()
  return prompt.is_open()
end, 2000)
write_query("zzz-no-such-symbol")
vim.cmd("AISearchRun")
H.wait_for(function()
  return status() == "no results"
end, 10000)
H.equal("empty result status", status(), "no results")
H.check("prompt stays open on empty", prompt.is_open())
H.equal("query preserved", prompt.get_text(), "zzz-no-such-symbol")

-- unknown provider keeps the prompt and the query
vim.cmd("AISearchRun nope")
H.wait_for(function()
  return status() == "unknown provider: nope"
end, 2000)
H.equal("unknown provider status", status(), "unknown provider: nope")
H.check("prompt stays open on unknown provider", prompt.is_open())

-- provider shortcut command
vim.cmd("AISearchRun grep")
H.wait_for(function()
  return status() == "no results"
end, 10000)
H.equal("explicit provider run", status(), "no results")

-- cancel closes
H.check("open before cancel", prompt.is_open())
vim.cmd("AISearchCancel")
H.equal("cancel closes", prompt.is_open(), false)

-- stale results from an abandoned run are dropped
config.setup({
  default_provider = "grep",
  providers = {
    grep = {
      command = H.stub(
        dir,
        "slow-grep",
        "sleep 1; printf 'lua/a.lua:2:1:stale\n'"
      ),
    },
  },
})
vim.fn.setqflist({})
vim.cmd("AISearch")
H.wait_for(function()
  return prompt.is_open()
end, 2000)
write_query("bar")
vim.cmd("AISearchRun")
vim.cmd("AISearchCancel")
vim.wait(2000)
H.equal("stale results dropped", #vim.fn.getqflist(), 0)
H.equal("still closed after stale run", prompt.is_open(), false)

-- a second run supersedes the first
config.setup({ default_provider = "grep" })
vim.cmd("AISearch")
H.wait_for(function()
  return prompt.is_open()
end, 2000)
write_query("bar")
vim.cmd("AISearchRun")
vim.cmd("AISearchRun")
H.wait_for(function()
  return #vim.fn.getqflist() > 0
end, 10000)
H.equal("superseding run produces one result set", #vim.fn.getqflist(), 1)

H.finish("integration")

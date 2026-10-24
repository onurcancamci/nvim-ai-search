-- Configuration defaults, merging and validation.

local H = dofile(
  vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/util.lua"
)
H.bootstrap()

local config = require("ai-search.config")

local cfg = config.setup({})
H.equal("default provider", cfg.default_provider, "pi")
H.equal("default picker", cfg.picker, "auto")
H.equal("grep indexed as a provider", cfg.providers.grep.command, "rg")
H.check(
  "pi has a system prompt",
  cfg.providers.pi.params[7]:match("JSON array") ~= nil
)

-- the string shorthand is rejected outright
local ok, err = pcall(config.setup, { providers = { pi = "pi" } })
H.check("string provider rejected", not ok)
H.match("string provider message", err, "string shorthand")

-- unknown provider names are rejected with the valid list
ok, err = pcall(config.setup, { providers = { custom = { command = "x" } } })
H.check("unknown provider rejected", not ok)
H.match("unknown provider message", err, "unknown provider")
H.match("unknown provider lists valid names", err, "pi, qmd, grep")

-- a missing command is an error, even for a known provider name
ok, err = pcall(config.setup, { providers = { grep = { command = "" } } })
H.check("empty command rejected", not ok)
H.match("empty command message", err, "command must be")

-- shortcut is gone: it must warn, not silently do nothing
local notified
local original = vim.notify
vim.notify = function(msg, level)
  notified = { msg = msg, level = level }
end
config.setup({ providers = { pi = { shortcut = "<C-p>" } } })
vim.notify = original
H.check("shortcut warns", notified ~= nil)
H.match(
  "shortcut warning names the key",
  notified and notified.msg,
  'unknown key "shortcut"'
)
H.equal(
  "shortcut warning level",
  notified and notified.level,
  vim.log.levels.WARN
)

-- params are replaced wholesale, not index-merged into the defaults
cfg = config.setup({ providers = { pi = { params = { "-p" } } } })
H.equal("params replaced wholesale", cfg.providers.pi.params, { "-p" })
H.equal("command kept from defaults", cfg.providers.pi.command, "pi")

-- collections merge key by key
cfg = config.setup({
  providers = { qmd = { collections = { docs = { "notes" } } } },
})
H.equal("collections merge", cfg.providers.qmd.collections.docs, { "notes" })
H.equal("collections keep defaults", cfg.providers.qmd.collections.code, {})

-- other invalid values
ok, err = pcall(config.setup, { picker = "fzf" })
H.check("bad picker rejected", not ok)
H.match("bad picker message", err, "picker must be")

ok, err =
  pcall(config.setup, { providers = { qmd = { scope = "everything" } } })
H.check("bad scope rejected", not ok)
H.match("bad scope message", err, "scope must be")

ok, err = pcall(config.setup, { default_provider = "nope" })
H.check("bad default provider rejected", not ok)
H.match("bad default provider message", err, "not a configured provider")

H.finish("config")

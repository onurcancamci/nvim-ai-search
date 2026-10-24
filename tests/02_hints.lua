-- Hint row discovery from real mappings.

local H = dofile(
  vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/util.lua"
)
H.bootstrap()

local config = require("ai-search.config")
local hints = require("ai-search.hints")

config.setup({})

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(buf)

local function map(mode, lhs, rhs, desc)
  vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
end

local function by_lhs_for(target)
  local out = {}
  for _, entry in ipairs(hints.discover(target)) do
    out[entry.lhs] = entry
  end
  return out
end

local function by_lhs()
  return by_lhs_for(buf)
end

-- nothing mapped: nothing discovered
H.equal("empty buffer has no triggers", hints.discover(buf), {})

map("n", "<CR>", "<Cmd>AISearchRun<CR>", "run")
map({ "n", "i" }, "<C-1>", "<Cmd>AISearchRun pi<CR>", "ai-search: pi")
map("n", "<C-2>", ":<C-u>AISearchRun qmd<CR>", "ai-search: qmd")
map("n", "g", "<Cmd>AISearchRun grep<CR>", "search text instead")
map("n", "<Esc>", "<Cmd>AISearchCancel<CR>", "cancel")
map({ "i", "n" }, "<C-c>", "<Cmd>AISearchCancel<CR>", "cancel")
map("n", "<C-7>", function() end, "ai-search: qmd")
map("n", "<C-8>", function() end, "unrelated")
map("n", "<C-9>", function() end)

local found = by_lhs()

H.check("<CR> discovered", found["<CR>"] ~= nil)
H.equal(
  "<CR> provider is nil (default)",
  found["<CR>"] and found["<CR>"].provider,
  nil
)
H.equal("<CR> label", found["<CR>"] and hints.label(found["<CR>"]), "run")
H.equal("<C-1> provider", found["<C-1>"] and found["<C-1>"].provider, "pi")
H.equal(
  "<C-1> canonical desc falls back to provider",
  found["<C-1>"] and hints.label(found["<C-1>"]),
  "pi"
)
H.equal(
  "<C-2> colon form provider",
  found["<C-2>"] and found["<C-2>"].provider,
  "qmd"
)
H.equal(
  "custom desc used as label",
  found["g"] and hints.label(found["g"]),
  "search text instead"
)
H.equal("cancel action", found["<Esc>"] and found["<Esc>"].action, "cancel")
H.equal(
  "cancel label",
  found["<Esc>"] and hints.label(found["<Esc>"]),
  "cancel"
)
H.equal(
  "lua callback with desc tag",
  found["<C-7>"] and found["<C-7>"].provider,
  "qmd"
)
H.equal("untagged lua callback hidden", found["<C-9>"], nil)
H.equal("unrelated desc hidden", found["<C-8>"], nil)
do
  local n = 0
  for _, entry in ipairs(hints.discover(buf)) do
    if entry.lhs == "<C-1>" then
      n = n + 1
    end
  end
  H.equal("n+i map collapses to one entry", n, 1)
end

-- global maps are discovered, and buffer-local shadows global for the same lhs
local gbuf = vim.api.nvim_create_buf(false, true)
vim.keymap.set("n", "<C-5>", "<Cmd>AISearchRun qmd<CR>", { buffer = gbuf })
vim.keymap.set("n", "<C-6>", "<Cmd>AISearchRun pi<CR>", { desc = "global pi" })
vim.keymap.set(
  "n",
  "<C-7>",
  "<Cmd>SomeUnrelatedCommand<CR>",
  { desc = "unrelated global" }
)

local gfound = by_lhs_for(gbuf)
H.check("global map discovered", gfound["<C-6>"] ~= nil)
H.equal(
  "global map provider",
  gfound["<C-6>"] and gfound["<C-6>"].provider,
  "pi"
)
H.equal(
  "buffer map provider",
  gfound["<C-5>"] and gfound["<C-5>"].provider,
  "qmd"
)
H.equal("unrelated global ignored", gfound["<C-7>"], nil)

vim.keymap.set("n", "<C-6>", "<Cmd>AISearchRun grep<CR>", { buffer = gbuf })
gfound = by_lhs_for(gbuf)
H.equal(
  "buffer-local shadows global",
  gfound["<C-6>"] and gfound["<C-6>"].provider,
  "grep"
)

-- rendering: <CR> first, cancel always reserved and last
local chunks = hints.compute(buf, 80)
local text = table.concat(vim.tbl_map(function(c)
  return c[1]
end, chunks))
H.match("render starts with enter", text, "^enter run")
H.match("render ends with cancel", text, "cancel$")
H.match("render joins with dashes", text, " %- ")

-- tight width truncates providers but keeps cancel
local narrow = hints.compute(buf, 34)
local narrow_text = table.concat(vim.tbl_map(function(c)
  return c[1]
end, narrow))
H.match("narrow render keeps cancel", narrow_text, "cancel$")
H.match("narrow render truncates", narrow_text, "%.%.%.")

-- max_items
config.setup({ hints = { max_items = 2 } })
local limited = hints.compute(buf, 200)
local count = 0
for _, chunk in ipairs(limited) do
  if chunk[2] == "Title" and chunk[1] ~= "cancel" then
    count = count + 1
  end
end
H.check("max_items limits provider entries", count <= 3, count)

-- disabled
config.setup({ hints = { enabled = false } })
H.equal("hints can be disabled", hints.compute(buf, 80), {})

-- prettify
config.setup({})
H.equal("prettify CR", hints.prettify("<CR>"), "enter")
H.equal("prettify ctrl", hints.prettify("<C-1>"), "ctrl-1")
H.equal("prettify ctrl letter", hints.prettify("<C-c>"), "ctrl-c")
H.equal("prettify alt", hints.prettify("<A-x>"), "alt-x")
H.equal("prettify plain", hints.prettify("g"), "g")
config.setup({ hints = { prettify = false } })
H.equal("prettify disabled", hints.prettify("<CR>"), "<CR>")

H.finish("hints")

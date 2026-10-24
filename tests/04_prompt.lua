-- Prompt float: geometry, the two editable lines, virtual status and hint rows,
-- and the default mappings.

local H = dofile(
  vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/util.lua"
)
H.bootstrap()

local config = require("ai-search.config")
local prompt = require("ai-search.prompt")
local ns = vim.api.nvim_create_namespace("ai-search-prompt")

config.setup({})

local function virt_lines()
  local buf = vim.api.nvim_get_current_buf()
  local marks =
    vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  if #marks == 0 then
    return {}
  end
  return marks[1][4].virt_lines or {}
end

local function line_text(chunks)
  return table.concat(
    vim.tbl_map(function(chunk)
      return chunk[1]
    end, chunks),
    ""
  )
end

H.equal("prompt starts closed", prompt.is_open(), false)
H.equal("text of a closed prompt", prompt.get_text(), "")

prompt.open()
H.wait_for(function()
  return prompt.is_open()
end, 2000)
vim.wait(100)

H.check("prompt open", prompt.is_open())
H.equal("filetype", vim.bo.filetype, "ai-search-prompt")
H.equal("two editable input lines", vim.api.nvim_buf_line_count(0), 2)
H.equal("buftype", vim.bo.buftype, "nofile")
H.equal("swapfile off", vim.bo.swapfile, false)

local win = prompt.winid()
H.check("float window", vim.api.nvim_win_is_valid(win))
H.equal("float height", vim.api.nvim_win_get_height(win), 4)
H.equal("border", vim.api.nvim_win_get_config(win).border[1], "╭")

H.equal("empty query", prompt.get_text(), "")

-- both input lines are part of the query
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "find the", "auth  flow" })
vim.wait(50)
H.equal("two lines joined", prompt.get_text(), "find the auth flow")

-- rows 3 and 4 are virtual, so they cannot be edited
local vl = virt_lines()
H.equal("two virtual rows", #vl, 2)
H.check("status row rendered", line_text(vl[1]) ~= nil)
local hint_text = line_text(vl[2])
H.match(
  "hint shows <CR> submit with the default provider",
  hint_text,
  "enter pi"
)
H.match("hint shows cancel", hint_text, "cancel$")

prompt.set_status("searching with pi", "Comment")
vim.wait(50)
vl = virt_lines()
H.equal("status updated", line_text(vl[1]), "searching with pi")

-- the three default mappings exist and are buffer-local
local maps = {}
for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
  maps[map.lhs] = map
end
H.check("<CR> mapped", maps["<CR>"] ~= nil)
H.equal(
  "<CR> command",
  maps["<CR>"] and maps["<CR>"].rhs,
  "<Cmd>AISearchRun<CR>"
)
H.check("<Esc> mapped", maps["<Esc>"] ~= nil)
H.equal(
  "<Esc> command",
  maps["<Esc>"] and maps["<Esc>"].rhs,
  "<Cmd>AISearchCancel<CR>"
)

local insert_maps = {}
for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "i")) do
  insert_maps[map.lhs] = map
end
H.equal("insert mode keeps <CR> free", insert_maps["<CR>"], nil)
-- nvim normalises <C-c> to <C-C> in keymap listings
H.equal("insert mode <C-c> left to the user", insert_maps["<C-C>"], nil)
H.check("normal mode <C-c> cancels", maps["<C-C>"] ~= nil)
H.equal(
  "normal mode <C-c> command",
  maps["<C-C>"] and maps["<C-C>"].rhs,
  "<Cmd>AISearchCancel<CR>"
)

-- reopening focuses instead of creating a second float
local before = #vim.api.nvim_list_wins()
prompt.open()
H.wait_for(function()
  return prompt.is_open()
end, 1000)
H.equal("no second window", #vim.api.nvim_list_wins(), before)

prompt.close()
H.equal("closed", prompt.is_open(), false)
H.equal("buffer wiped", vim.fn.bufexists(""), 0)
H.equal("text after close", prompt.get_text(), "")

-- geometry respects min_width and the column budget
config.setup({ prompt = { width = 0.2, min_width = 40 } })
prompt.open()
vim.wait(100)
H.equal("min_width respected", vim.api.nvim_win_get_width(prompt.winid()), 40)
prompt.close()

H.finish("prompt")

-- snacks.picker adapter. This is the real target.

local M = {}

---@param entry table
---@return table
function M.item(entry)
  return {
    file = entry.file,
    -- snacks.picker expects { 1-based row, 0-based column }
    pos = { entry.lnum, (entry.col or 1) - 1 },
    text = entry.text or entry.file,
    line = entry.text or "",
    source = entry.source,
  }
end

---@param picker table
---@param item table
local function open_item(picker, item)
  if not item or not item.file then
    return
  end

  picker:close()

  vim.cmd.edit(vim.fn.fnameescape(item.file))
  local row = math.min(item.pos[1], vim.api.nvim_buf_line_count(0))
  pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, row), item.pos[2] })
  vim.cmd.normal({ args = { "zz" }, bang = true })
end

---@param entries table[]
---@param ctx table
function M.open(entries, ctx)
  local Snacks = require("snacks")

  local items = {}
  for _, entry in ipairs(entries) do
    items[#items + 1] = M.item(entry)
  end

  Snacks.picker.pick({
    title = string.format("AI Search [%s]: %s", ctx.provider, ctx.query),
    items = items,
    confirm = open_item,
  })
end

return M

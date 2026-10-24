-- Picker dispatch: snacks first, telescope as a fallback, quickfix as a last
-- resort so results are never lost.

local config = require("ai-search.config")

local M = {}

---@return string
function M.resolve()
  local picker = config.get().picker
  if picker ~= "auto" then
    return picker
  end

  if pcall(require, "snacks.picker") then
    return "snacks"
  end
  if pcall(require, "telescope") then
    return "telescope"
  end
  return "quickfix"
end

---@param entries table[]
---@param ctx table
function M.open(entries, ctx)
  local kind = M.resolve()

  if kind == "snacks" then
    local ok, err = pcall(function()
      require("ai-search.picker.snacks").open(entries, ctx)
    end)
    if ok then
      return
    end
    vim.notify(
      "ai-search: snacks picker failed, falling back to quickfix: "
        .. tostring(err),
      vim.log.levels.WARN
    )
  elseif kind == "telescope" then
    local ok = pcall(function()
      return require("ai-search.picker.telescope").open(entries, ctx)
    end)
    if ok then
      return
    end
  end

  local list = {}
  for _, entry in ipairs(entries) do
    list[#list + 1] = {
      filename = entry.file,
      lnum = entry.lnum,
      col = entry.col or 1,
      text = entry.text or "",
    }
  end
  vim.fn.setqflist(list)
  vim.cmd.copen()
end

return M

-- Derive the hint row from the mappings that actually exist in the prompt
-- buffer. There is no registry: the row cannot drift from what the keys do.

local config = require("ai-search.config")

local M = {}

local run_command = "AISearchRun"
local cancel_command = "AISearchCancel"
local desc_tag = "^%s*ai%-search:%s*(%S+)%s*$"

local prettify_map = {
  ["<CR>"] = "enter",
  ["<Esc>"] = "esc",
  ["<Tab>"] = "tab",
  ["<Space>"] = "space",
  ["<BS>"] = "backspace",
  ["<Del>"] = "delete",
  ["<Up>"] = "up",
  ["<Down>"] = "down",
  ["<Left>"] = "left",
  ["<Right>"] = "right",
}

---@param lhs string
---@return string
function M.prettify(lhs)
  if not config.get().hints.prettify then
    return lhs
  end

  if prettify_map[lhs] then
    return prettify_map[lhs]
  end

  local out = lhs
  out = out:gsub("<[Cc]%-([^>]+)>", function(key)
    return "ctrl-" .. key:lower()
  end)
  out = out:gsub("<[Ss]%-([^>]+)>", function(key)
    return "shift-" .. key:lower()
  end)
  out = out:gsub("<[MmAa]%-([^>]+)>", function(key)
    return "alt-" .. key:lower()
  end)
  return out
end

--- Classify a mapping as a submit or cancel trigger.
---@param map table
---@return string|nil action, string|nil provider
local function classify(map)
  local rhs = map.rhs or ""

  if rhs:find(run_command, 1, true) then
    local provider = rhs:match(run_command .. "%s+([^%s<]+)")
    return "run", provider
  end

  if rhs:find(cancel_command, 1, true) then
    return "cancel", nil
  end

  if map.desc then
    local provider = map.desc:match(desc_tag)
    if provider then
      return "run", provider
    end
  end

  return nil
end

--- Collect trigger mappings. Buffer-local wins over global for the same lhs.
---@param bufnr number
---@return table[]
function M.discover(bufnr)
  local found, seen = {}, {}

  local function scan(list)
    for _, map in ipairs(list) do
      if not seen[map.lhs] then
        local action, provider = classify(map)
        if action then
          seen[map.lhs] = true
          found[#found + 1] = {
            lhs = map.lhs,
            action = action,
            provider = provider,
            desc = map.desc,
          }
        end
      end
    end
  end

  for _, mode in ipairs({ "n", "i" }) do
    scan(vim.api.nvim_buf_get_keymap(bufnr, mode))
  end
  for _, mode in ipairs({ "n", "i" }) do
    scan(vim.api.nvim_get_keymap(mode))
  end

  return found
end

---@param entry table
---@return string
function M.label(entry)
  local desc = entry.desc
  if desc and desc ~= "" and not desc:match(desc_tag) then
    return desc
  end
  if entry.action == "cancel" then
    return "cancel"
  end
  return entry.provider or "run"
end

---@param entries table[]
---@param order string[]
---@return table[]
local function sort_entries(entries, order)
  local rank = {}
  for i, name in ipairs(order) do
    rank[name] = i
  end

  local function key(entry)
    if entry.lhs == "<CR>" then
      return 0
    end
    if entry.action == "cancel" then
      return 500
    end
    return 100 + (rank[entry.provider] or (#order + 1))
  end

  table.sort(entries, function(a, b)
    local ka, kb = key(a), key(b)
    if ka ~= kb then
      return ka < kb
    end
    return a.lhs < b.lhs
  end)

  return entries
end

---@param entry table
---@param known boolean
---@return table[] chunks
local function entry_chunks(entry, known, with_separator)
  local chunks = {}
  if with_separator then
    chunks[#chunks + 1] = { " - ", "Comment" }
  end
  chunks[#chunks + 1] = { M.prettify(entry.lhs), "Title" }
  chunks[#chunks + 1] =
    { " " .. M.label(entry), known and "Comment" or "ErrorMsg" }
  return chunks
end

---@param chunks table[]
---@return number
local function chunks_width(chunks)
  local total = 0
  for _, chunk in ipairs(chunks) do
    total = total + vim.fn.strdisplaywidth(chunk[1])
  end
  return total
end

---@param bufnr number
---@param width number
---@return table[] chunks virt_text style chunks
function M.compute(bufnr, width)
  local cfg = config.get()
  if not cfg.hints.enabled then
    return {}
  end

  local order = {}
  for _, name in ipairs(config.provider_order) do
    if cfg.providers[name] then
      order[#order + 1] = name
    end
  end

  local entries = sort_entries(M.discover(bufnr), order)

  -- Collapse the cancel triggers into one entry so the escape hatch is visible
  -- without repeating itself. <Esc> is the primary, so prefer it when present.
  local cancel
  local main = {}
  for _, entry in ipairs(entries) do
    if entry.action == "cancel" then
      if not cancel or entry.lhs == "<Esc>" then
        cancel = entry
      end
    else
      main[#main + 1] = entry
    end
  end

  local known = function(entry)
    return entry.provider == nil or cfg.providers[entry.provider] ~= nil
  end

  local cancel_chunks = cancel and entry_chunks(cancel, true, true) or {}
  local reserve = chunks_width(cancel_chunks)

  local max_items = cfg.hints.max_items or 8
  local budget = math.max(10, width - 2 - reserve)

  local chunks = {}
  local used = 0
  local truncated = false

  for i, entry in ipairs(main) do
    local pieces = entry_chunks(entry, known(entry), i > 1)
    local added = chunks_width(pieces)

    if (max_items > 0 and i > max_items) or added > budget - used then
      truncated = true
      break
    end

    used = used + added
    vim.list_extend(chunks, pieces)
  end

  if truncated then
    chunks[#chunks + 1] = { " - ...", "Comment" }
  end

  vim.list_extend(chunks, cancel_chunks)

  return chunks
end

return M

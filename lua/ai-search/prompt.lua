-- The prompt float: two editable input lines, a status line and a hint row.
-- Rows 3 and 4 are virt_lines, so the cursor can never land on them.

local config = require("ai-search.config")
local hints = require("ai-search.hints")

local M = {}

local ns = vim.api.nvim_create_namespace("ai-search-prompt")

local state = {
  bufnr = nil,
  winid = nil,
  mark = nil,
  status = nil,
  width = 0,
}

local function valid()
  return state.bufnr ~= nil
    and vim.api.nvim_buf_is_valid(state.bufnr)
    and state.winid ~= nil
    and vim.api.nvim_win_is_valid(state.winid)
end

local function default_status()
  return { { "", "Comment" } }
end

---@param text string
---@param group string|nil
function M.set_status(text, group)
  state.status = { { text, group or "Comment" } }
  M.render()
end

--- Width of the float, recomputed on resize.
---@return number
local function compute_width()
  local prompt = config.get().prompt
  return math.max(
    prompt.min_width,
    math.min(math.floor(vim.o.columns * prompt.width), vim.o.columns - 8)
  )
end

--- Push the current status and hint row into the buffer as two virtual lines.
function M.render()
  if not valid() then
    return
  end

  local lines = { state.status or default_status() }
  local hint_chunks = hints.compute(state.bufnr, state.width)
  if #hint_chunks > 0 then
    lines[#lines + 1] = hint_chunks
  end

  local row = math.max(0, vim.api.nvim_buf_line_count(state.bufnr) - 1)
  local opts = {
    virt_lines = lines,
    virt_lines_above = false,
  }
  if state.mark then
    opts.id = state.mark
  end

  local ok, mark =
    pcall(vim.api.nvim_buf_set_extmark, state.bufnr, ns, row, 0, opts)
  if ok then
    state.mark = mark
  end
end

---@return string
function M.get_text()
  if not valid() then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(state.bufnr, 0, -1, false)
  local text = vim.trim(table.concat(lines, " "))
  return (text:gsub("%s+", " "))
end

---@return boolean
function M.is_open()
  return valid()
end

---@return number|nil
function M.winid()
  return valid() and state.winid or nil
end

function M.focus()
  if valid() then
    vim.api.nvim_set_current_win(state.winid)
  end
end

function M.close()
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    pcall(vim.api.nvim_win_close, state.winid, true)
  end
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    pcall(vim.api.nvim_buf_delete, state.bufnr, { force = true })
  end
  state.bufnr, state.winid, state.mark, state.status = nil, nil, nil, nil
end

---@param bufnr number
---@param default_provider string
local function set_default_maps(bufnr, default_provider)
  local function map(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, {
      buffer = bufnr,
      desc = desc,
      nowait = true,
      silent = true,
    })
  end

  map("n", "<CR>", "<Cmd>AISearchRun<CR>", default_provider)
  map("n", "<Esc>", "<Cmd>AISearchCancel<CR>", "cancel")
  -- Normal mode only: insert mode <C-c> belongs to the user's own config, where
  -- it is commonly mapped to <Esc>.
  map("n", "<C-c>", "<Cmd>AISearchCancel<CR>", "cancel")
end

--- Open the prompt float.
---@param opts table|nil
function M.open(opts)
  opts = opts or {}
  local cfg = config.get()

  if valid() then
    M.focus()
    return
  end

  local height = 4
  state.width = compute_width()
  local row = math.max(0, math.floor((vim.o.lines - height) * 0.35))
  local col = math.max(0, math.floor((vim.o.columns - state.width) / 2))

  local bufnr = vim.api.nvim_create_buf(false, true)
  state.bufnr = bufnr
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "" })

  for key, value in pairs({
    buftype = "nofile",
    bufhidden = "wipe",
    swapfile = false,
    undolevels = -1,
  }) do
    vim.api.nvim_set_option_value(key, value, { buf = bufnr })
  end

  local win_opts = {
    relative = "editor",
    row = row,
    col = col,
    width = state.width,
    height = height,
    style = "minimal",
    border = cfg.prompt.border,
  }
  if cfg.prompt.title and cfg.prompt.border ~= "none" then
    win_opts.title = cfg.prompt.title
    win_opts.title_pos = "left"
  end

  state.winid = vim.api.nvim_open_win(bufnr, true, win_opts)

  vim.api.nvim_set_option_value("wrap", true, { win = state.winid })

  state.status = default_status()
  state.mark = nil

  -- Re-anchor the virtual lines whenever the buffer changes, including when the
  -- user deletes a line.
  vim.api.nvim_buf_attach(bufnr, false, {
    on_lines = function()
      vim.schedule(function()
        if valid() then
          M.render()
        end
      end)
    end,
  })

  set_default_maps(bufnr, cfg.default_provider)

  -- Set the filetype last: FileType autocmds fire synchronously, so maps added
  -- by the user's FileType autocmd or ftplugin override the defaults above.
  vim.api.nvim_set_option_value("filetype", "ai-search-prompt", { buf = bufnr })

  vim.schedule(function()
    if not valid() then
      return
    end
    M.render()
    vim.cmd.startinsert()
  end)
end

-- Keep the hint row correct when the window width changes.
local resized =
  vim.api.nvim_create_augroup("ai-search-prompt-resize", { clear = true })
vim.api.nvim_create_autocmd("VimResized", {
  group = resized,
  callback = function()
    if not valid() then
      return
    end
    state.width = compute_width()
    local height = 4
    local col = math.max(0, math.floor((vim.o.columns - state.width) / 2))
    local row = math.max(0, math.floor((vim.o.lines - height) * 0.35))
    pcall(vim.api.nvim_win_set_config, state.winid, {
      relative = "editor",
      row = row,
      col = col,
      width = state.width,
      height = height,
    })
    M.render()
  end,
})

return M

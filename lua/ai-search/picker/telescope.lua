-- telescope.nvim adapter. Fallback only.

local M = {}

---@param entry table
---@return table
local function entry_maker(entry)
  return {
    value = entry,
    display = string.format(
      "%s:%d: %s",
      vim.fn.fnamemodify(entry.file, ":."),
      entry.lnum,
      entry.text or ""
    ),
    ordinal = string.format("%s %s", entry.file, entry.text or ""),
    filename = entry.file,
    lnum = entry.lnum,
    col = entry.col or 1,
  }
end

---@param entries table[]
---@param ctx table
function M.open(entries, ctx)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then
    return false
  end
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  pickers
    .new({}, {
      prompt_title = string.format(
        "AI Search [%s]: %s",
        ctx.provider,
        ctx.query
      ),
      finder = finders.new_table({
        results = entries,
        entry_maker = entry_maker,
      }),
      sorter = conf.generic_sorter({}),
      previewer = conf.file_previewer({}),
      attach_mappings = function(prompt_bufnr, map)
        local function open(edit_command)
          return function()
            local selection = action_state.get_selected_entry()
            if not selection then
              return
            end
            actions.close(prompt_bufnr)
            vim.cmd(
              string.format(
                "%s %s",
                edit_command,
                vim.fn.fnameescape(selection.filename)
              )
            )
            local row = math.min(selection.lnum, vim.api.nvim_buf_line_count(0))
            pcall(vim.api.nvim_win_set_cursor, 0, { math.max(1, row), 0 })
            vim.cmd.normal({ args = { "zz" }, bang = true })
          end
        end

        map("i", "<CR>", open("edit"))
        map("n", "<CR>", open("edit"))
        map({ "i", "n" }, "<C-s>", open("split"))
        map({ "i", "n" }, "<C-v>", open("vsplit"))
        map({ "i", "n" }, "<C-t>", open("tabedit"))
        return true
      end,
    })
    :find()

  return true
end

return M

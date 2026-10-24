-- User commands. Defined eagerly so they exist before setup().

local M = {}

local function provider_complete(arglead)
  local ok, config = pcall(require, "ai-search.config")
  if not ok then
    return {}
  end

  local out = {}
  for name in pairs(config.get().providers) do
    if vim.startswith(name, arglead) then
      out[#out + 1] = name
    end
  end
  table.sort(out)
  return out
end

function M.register()
  if vim.g.loaded_ai_search_commands then
    return
  end
  vim.g.loaded_ai_search_commands = 1

  local function call(fn)
    return function(opts)
      local ok, mod = pcall(require, "ai-search")
      if not ok then
        vim.notify("ai-search: " .. tostring(mod), vim.log.levels.ERROR)
        return
      end
      mod[fn](opts.args ~= "" and opts.args or nil)
    end
  end

  vim.api.nvim_create_user_command("AISearch", call("open"), {
    nargs = "?",
    complete = provider_complete,
    desc = "Open the AI search prompt",
  })

  vim.api.nvim_create_user_command("AISearchRun", call("run"), {
    nargs = "?",
    complete = provider_complete,
    desc = "Submit the AI search prompt with a provider",
  })

  vim.api.nvim_create_user_command("AISearchCancel", function()
    require("ai-search").cancel()
  end, {
    nargs = 0,
    desc = "Cancel the AI search prompt",
  })
end

return M

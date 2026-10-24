-- :checkhealth ai-search

local M = {}

function M.check()
  local config = require("ai-search.config")
  local cfg = config.get()

  vim.health.start("ai-search")

  local version = string.format(
    "Neovim %d.%d (requires >= 0.10)",
    vim.version().major,
    vim.version().minor
  )
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok(version)
  else
    vim.health.error(version)
  end

  local picker = require("ai-search.picker").resolve()
  if picker == "snacks" then
    vim.health.ok("picker: snacks.picker")
  elseif picker == "telescope" then
    vim.health.warn(
      "picker: telescope.nvim (fallback; snacks.picker is the target)"
    )
  else
    vim.health.warn(
      "picker: quickfix only (neither snacks.picker nor telescope found)"
    )
  end

  vim.health.start("ai-search providers")

  for _, name in ipairs(config.provider_order) do
    local pcfg = cfg.providers[name]
    if not pcfg then
      vim.health.info(string.format("%s: not configured", name))
    elseif pcfg.enabled == false then
      vim.health.info(string.format("%s: disabled", name))
    else
      local command = pcfg.command
      if vim.fn.executable(command) == 1 then
        vim.health.ok(string.format("%s: %s found", name, command))
      else
        vim.health.error(
          string.format("%s: executable %q not found on PATH", name, command)
        )
      end
    end
  end

  if cfg.providers.qmd then
    vim.health.info(
      "qmd: index and collection management is the user's responsibility "
        .. "(qmd collection add, qmd update, qmd embed)"
    )
  end
end

return M

-- Load autocommands/commands for ai-search. Configuration happens in setup().

if vim.g.loaded_ai_search then
  return
end
vim.g.loaded_ai_search = 1

require("ai-search.commands").register()

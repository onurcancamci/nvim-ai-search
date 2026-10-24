# nvim-ai-search

AI-backed codebase search for Neovim. One keymap opens a prompt, a provider answers,
results open in [snacks.picker](https://github.com/folke/snacks.nvim) (telescope.nvim is a
fallback).

Requires Neovim >= 0.10. Lua only, no external helper binaries beyond the providers you
configure.

## Install

```lua
{
  dir = "~/Code/nvim-ai-search",
  config = function()
    require("ai-search").setup({
      default_provider = "pi", -- "pi" | "qmd" | "grep"
    })
  end,
}
```

## Keymaps

The plugin does not map your keys. It exposes commands; you decide the keys.

```lua
-- open the prompt
vim.keymap.set("n", "<leader>as", "<Cmd>AISearch<CR>", { desc = "AI Search" })

-- run the prompt with a specific provider, from inside the prompt
vim.api.nvim_create_autocmd("FileType", {
  pattern = "ai-search-prompt",
  callback = function(ev)
    local map = function(mode, lhs, provider)
      vim.keymap.set(
        mode,
        lhs,
        "<Cmd>AISearchRun " .. provider .. "<CR>",
        { buffer = ev.buf, desc = "ai-search: " .. provider }
      )
    end

    map({ "n", "i" }, "<C-1>", "pi")
    map("n", "<C-2>", "qmd")
    map("n", "g", "grep")
  end,
})
```

`<CR>` in the prompt submits with `default_provider`. It is normal mode only, so `<CR>` in
insert mode stays a newline and the prompt is a genuine two-line input: type, `<Esc>`, `<CR>`.

Normal mode only is the rule for the defaults in general: `<Esc>` and `<C-c>` cancel from
normal mode, and insert mode is left alone. That way a config which maps insert `<C-c>` to
`<Esc>` keeps working, and `<C-c><C-c>` still cancels everywhere.

## Commands

| Command                 | Action                                                          |
| ----------------------- | --------------------------------------------------------------- |
| `:AISearch [provider]`  | Open the prompt; the optional provider overrides the default     |
| `:AISearchRun [provider]` | Submit the open prompt with that provider                      |
| `:AISearchCancel`       | Cancel and close                                                |

`:AIS`, `:AISR` and `:AISC` work as abbreviations.

## Hints

The dim row at the bottom of the prompt is derived from the mappings that actually exist in
the prompt buffer, so it never drifts from what the keys do. Discovery looks for:

1. mappings whose `rhs` contains `AISearchRun <provider>` or `AISearchCancel`, and
2. mappings whose `desc` is `ai-search: <provider>` — this is the only way to discover
   Lua-callback maps, which expose no `rhs`.

```lua
vim.keymap.set("n", "<C-7>", function()
  require("ai-search").run("qmd")
end, { buffer = 0, desc = "ai-search: qmd" })
```

A Lua-callback map without that `desc` still works, it just does not appear in the hint row.
The same applies to `expr = true` maps.

## Providers

Providers are tables. There is no string shorthand.

```lua
require("ai-search").setup({
  default_provider = "pi",
  picker = "auto",      -- "auto" | "snacks" | "telescope"
  max_results = 100,
  timeout = 90000,
  prompt = { width = 0.6, min_width = 60, border = "rounded", title = "AI Search" },
  hints = { enabled = true, max_items = 8, prettify = true },

  providers = {
    pi = {
      command = "pi",
      params = { "-p", "--no-session", "--no-context-files", "-t", "grep,find,read,ls",
                 "--system-prompt", "<search prompt>", "--" },
      timeout = 90000,
    },
    qmd = {
      command = "qmd",
      params = { "query", "{query}", "-n", "40", "--format", "json", "--full-path",
                 "--chunk-strategy", "auto" },
      scope = "code", -- "code" (default) | "docs"
      collections = { code = {}, docs = {} },
      timeout = 30000,
    },
    grep = {
      command = "rg",
      params = { "--vimgrep", "--smart-case", "--hidden", "-g", "!.git", "--", "{query}", "." },
      timeout = 10000,
    },
  },
})
```

Commands run as argv, never through a shell. `{query}` is substituted anywhere in `params`;
if there is no placeholder the query is appended last.

### `pi`

Agentic search through the `pi` CLI in print mode. The result contract is a strict system
prompt asking for a bare JSON array of `{ "file", "line" }`, parsed back in Lua. Locations
only, no explanations. No pi extension is shipped: pi extensions are TypeScript/JavaScript,
and this plugin stays Lua.

### `qmd`

Hybrid (BM25 + vector + rerank) search over a [qmd](https://github.com/tobilu/qmd) index.
`--chunk-strategy auto` makes code searchable, so code is the default scope.

The plugin only runs the command. Creating, updating and inspecting the index and its
collections is entirely up to you:

```sh
qmd collection add .
qmd update
qmd embed
```

Set `scope = "docs"` and `collections.docs = { "notes" }` to restrict searches to specific
collections, or `collections.code` to filter the code scope.

### `grep`

Plain ripgrep. Useful when you open the prompt, write a query, and decide you just want to
grep instead of waiting for a model.

## Health

```vim
:checkhealth ai-search
```

## Tests

Headless, hermetic, no model calls:

```sh
./tests/run.sh
```

| File | Covers |
| --- | --- |
| `tests/01_config.lua` | defaults, merging, validation errors, the removed `shortcut` key |
| `tests/02_hints.lua` | mapping discovery, labels, ordering, dedupe, truncation, prettify |
| `tests/03_providers.lua` | argv resolution, hostile queries, grep, qmd scopes, pi parsing, timeout |
| `tests/04_prompt.lua` | float geometry, two input lines, virtual rows, default maps |
| `tests/05_integration.lua` | commands, dispatch, generation guard, cancel, quickfix |

Provider tests use stub executables created in a temp directory, so nothing calls a model.

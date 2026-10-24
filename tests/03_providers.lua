-- Provider argv resolution and result parsing, using stub executables so no
-- network or model call is involved.

local H = dofile(
  vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/util.lua"
)
H.bootstrap()

local config = require("ai-search.config")
local providers = require("ai-search.providers")

config.setup({})

local cfg = config.get()

-- argv: substitution in place
H.equal(
  "argv substitutes in place",
  providers.argv(cfg.providers.grep, "bar"),
  {
    "rg",
    "--vimgrep",
    "--smart-case",
    "--hidden",
    "-g",
    "!.git",
    "--",
    "bar",
    ".",
  }
)

-- argv: appended when there is no placeholder
H.equal(
  "argv appends when no placeholder",
  providers.argv(cfg.providers.pi, "hello"),
  {
    "pi",
    "-p",
    "--no-session",
    "--no-context-files",
    "-t",
    "grep,find,read,ls",
    "--system-prompt",
    cfg.providers.pi.params[7],
    "--",
    "hello",
  }
)

-- argv: hostile queries stay a single argument and never hit a shell
local hostile = 'he said "hi" 100% $HOME `rm -rf /` ; echo'
local argv = providers.argv(cfg.providers.grep, hostile)
H.equal("hostile query is one argv element", argv[#argv - 1], hostile)

-- grep provider against a real ripgrep run
local dir = H.tmpdir()
vim.fn.mkdir(dir .. "/lua", "p")
vim.fn.writefile({ "local foo = 1", "local bar = 2" }, dir .. "/lua/a.lua")
vim.fn.writefile({ "local baz = 3" }, dir .. "/lua/b.lua")

local function run(name, ctx)
  local box = nil
  local handle = providers
    .get(name)
    .run(ctx, config.get().providers[name], function(err, entries)
      box = { err = err, entries = entries }
    end)
  H.wait_for(function()
    return box ~= nil
  end, 15000)
  return box, handle
end

local box = run("grep", { query = "bar", cwd = dir })
H.equal("grep no error", box and box.err, nil)
H.equal("grep result count", #(box and box.entries or {}), 1)
H.equal("grep file", box and box.entries[1].file, "./lua/a.lua")
H.equal("grep line", box and box.entries[1].lnum, 2)
H.equal("grep text", box and box.entries[1].text, "local bar = 2")

box = run("grep", { query = "nothing-matches-this", cwd = dir })
H.equal("grep exit 1 is not an error", box and box.err, nil)
H.equal("grep exit 1 has no entries", #(box and box.entries or {}), 0)

-- pi provider against a stub that emits the expected contract
local pi_stub = H.stub(
  dir,
  "pi-stub",
  [[printf '%s' '[{"file": "lua/a.lua", "line": 2}, {"file": "lua/b.lua", "line": 1}]']]
)
config.setup({
  providers = { pi = { command = pi_stub, params = { "{query}" } } },
})
box = run("pi", { query = "bar", cwd = dir })
H.equal("pi no error", box and box.err, nil)
H.equal("pi entry count", #(box and box.entries or {}), 2)
H.equal("pi entry file", box and box.entries[1].file, "lua/a.lua")
H.equal("pi entry line", box and box.entries[1].lnum, 2)
H.equal("pi entry source", box and box.entries[1].source, "pi")

-- pi tolerates prose around the array and packed "file:line" values
local prose_stub = H.stub(
  dir,
  "pi-prose",
  [[printf '%s' 'Sure! Here you go:
```json
[{"file": "lua/a.lua:2"}]
```']]
)
config.setup({ providers = { pi = { command = prose_stub, params = {} } } })
box = run("pi", { query = "bar", cwd = dir })
H.equal("pi parses fenced array", box and box.entries and #box.entries, 1)
H.equal(
  "pi splits packed path",
  box and box.entries and box.entries[1].file,
  "lua/a.lua"
)
H.equal("pi splits packed line", box and box.entries and box.entries[1].lnum, 2)

-- pi falls back to scanning "path:line" pairs
local loose_stub = H.stub(
  dir,
  "pi-loose",
  [[printf '%s' 'The match is in lua/a.lua:2 and also lua/b.lua:1
done']]
)
config.setup({ providers = { pi = { command = loose_stub, params = {} } } })
box = run("pi", { query = "bar", cwd = dir })
H.equal("pi loose fallback count", box and box.entries and #box.entries, 2)

-- pi empty array is a valid empty result, not an error
local empty_stub = H.stub(dir, "pi-empty", [[printf '%s' '[]']])
config.setup({ providers = { pi = { command = empty_stub, params = {} } } })
box = run("pi", { query = "bar", cwd = dir })
H.equal("pi empty array no error", box and box.err, nil)
H.equal("pi empty array no entries", #(box and box.entries or {}), 0)

-- pi failure surfaces stderr
local fail_stub =
  H.stub(dir, "pi-fail", [[echo "provider exploded" >&2; exit 2]])
config.setup({ providers = { pi = { command = fail_stub, params = {} } } })
box = run("pi", { query = "bar", cwd = dir })
H.match("pi failure reports stderr", box and box.err, "provider exploded")

-- qmd JSON contract
local qmd_stub = H.stub(
  dir,
  "qmd-stub",
  [[printf '%s' '[{"docid": "#abc123", "score": 0.89, "file": "./lua/a.lua", "line": 2, "title": "A", "snippet": "local bar = 2"}]']]
)
config.setup({
  providers = { qmd = { command = qmd_stub, params = { "query", "{query}" } } },
})
box = run("qmd", { query = "bar", cwd = dir })
H.equal("qmd no error", box and box.err, nil)
H.equal("qmd file", box and box.entries[1].file, "./lua/a.lua")
H.equal("qmd line", box and box.entries[1].lnum, 2)
H.equal("qmd text", box and box.entries[1].text, "A")
H.equal("qmd score", box and box.entries[1].score, 0.89)

-- qmd results object wrapper
local qmd_wrapped = H.stub(
  dir,
  "qmd-wrapped",
  [[printf '%s' '{"results": [{"file": "lua/b.lua", "score": 0.5}]}']]
)
config.setup({ providers = { qmd = { command = qmd_wrapped, params = {} } } })
box = run("qmd", { query = "baz", cwd = dir })
H.equal("qmd wrapped results", box and box.entries and #box.entries, 1)
H.equal("qmd default line", box and box.entries and box.entries[1].lnum, 1)

-- qmd scope filters
local argv_stub = H.stub(dir, "qmd-argv", [[printf '%s' '[]']])
config.setup({
  providers = {
    qmd = {
      command = argv_stub,
      params = { "query", "{query}" },
      scope = "docs",
      collections = { docs = { "notes", "papers" } },
    },
  },
})
H.equal(
  "qmd base argv has no scope filters",
  providers.argv(config.get().providers.qmd, "x"),
  { argv_stub, "query", "x" }
)

local argfile = dir .. "/qmd-args.txt"
config.setup({
  providers = {
    qmd = {
      command = H.stub(
        dir,
        "qmd-echo",
        ('printf "%%s" "$*" > %s; printf "[]"'):format(argfile)
      ),
      params = { "query", "{query}" },
      scope = "docs",
      collections = { docs = { "notes", "papers" } },
    },
  },
})
box = run("qmd", { query = "x", cwd = dir })
H.equal("qmd scope run no error", box and box.err, nil)
H.match(
  "qmd docs scope appends -c filters",
  vim.fn.readfile(argfile)[1],
  "%-c notes %-c papers$"
)

config.setup({
  providers = {
    qmd = {
      command = H.stub(
        dir,
        "qmd-echo-code",
        ('printf "%%s" "$*" > %s; printf "[]"'):format(argfile)
      ),
      params = { "query", "{query}" },
      scope = "code",
      collections = { code = { "src" }, docs = { "notes" } },
    },
  },
})
box = run("qmd", { query = "x", cwd = dir })
H.match(
  "qmd code scope appends code collection",
  vim.fn.readfile(argfile)[1],
  "%-c src$"
)

config.setup({
  providers = {
    qmd = {
      command = H.stub(
        dir,
        "qmd-echo-none",
        ('printf "%%s" "$*" > %s; printf "[]"'):format(argfile)
      ),
      params = { "query", "{query}" },
      scope = "docs",
      collections = { docs = {} },
    },
  },
})
box = run("qmd", { query = "x", cwd = dir })
H.equal(
  "qmd empty docs collections appends nothing",
  vim.fn.readfile(argfile)[1],
  "query x"
)

-- unknown output is reported, not silently empty
local junk_stub = H.stub(dir, "qmd-junk", [[printf '%s' 'not json at all']])
config.setup({ providers = { qmd = { command = junk_stub, params = {} } } })
box = run("qmd", { query = "x", cwd = dir })
H.match("qmd unparsable output", box and box.err, "unparsable")

-- timeout path
config.setup({
  providers = {
    grep = { timeout = 60, command = H.stub(dir, "slow", "sleep 5") },
  },
})
box = run("grep", { query = "x", cwd = dir })
H.match("timeout reported", box and box.err, "timed out")

H.finish("providers")

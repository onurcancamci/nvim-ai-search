-- Shared helpers for the headless test scripts.
--
-- Each test file starts with:
--   local H = dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/util.lua")
--   H.bootstrap()

local H = {}

H.root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

function H.bootstrap()
  vim.opt.runtimepath:prepend(H.root)
  require("ai-search.commands").register()
end

local failures = 0
local checks = 0

function H.check(name, cond, extra)
  checks = checks + 1
  if cond then
    return true
  end
  failures = failures + 1
  io.write(
    ("FAIL %s%s\n"):format(
      name,
      extra ~= nil and (" -> " .. tostring(extra)) or ""
    )
  )
  return false
end

function H.equal(name, actual, expected)
  return H.check(
    name,
    vim.deep_equal(actual, expected),
    ("got %s, expected %s"):format(vim.inspect(actual), vim.inspect(expected))
  )
end

function H.match(name, value, pattern)
  return H.check(name, tostring(value):match(pattern) ~= nil, tostring(value))
end

function H.wait_for(predicate, timeout)
  return vim.wait(timeout or 5000, predicate, 20)
end

function H.tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Write an executable stub command that prints the given text.
function H.stub(dir, name, body)
  local path = dir .. "/" .. name
  vim.fn.writefile({ "#!/bin/sh", body }, path)
  vim.fn.setfperm(path, "rwxr-xr-x")
  return path
end

--- Report and exit.
function H.finish(label)
  if failures == 0 then
    io.write(("ok %s (%d checks)\n"):format(label, checks))
    io.flush()
    os.exit(0)
  end
  io.write(("%s: %d/%d checks failed\n"):format(label, failures, checks))
  io.flush()
  os.exit(1)
end

return H

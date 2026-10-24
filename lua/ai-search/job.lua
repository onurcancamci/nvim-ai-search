-- Thin vim.system wrapper: argv execution, streamed capture, cancellation and
-- timeout. Never invokes a shell.

local M = {}

---@param argv string[]
---@param opts table
---@return table handle { cancel = fun(), signal = nil }
function M.start(argv, opts)
  opts = opts or {}

  local stdout, stderr = {}, {}
  local finished = false
  local cancelled = false
  local timed_out = false
  local timer
  local proc

  local handle = {}

  local function stop_timer()
    if not timer then
      return
    end
    pcall(function()
      timer:stop()
    end)
    pcall(function()
      timer:close()
    end)
    timer = nil
  end

  local function finish(code, signal)
    if finished then
      return
    end
    finished = true
    stop_timer()
    vim.schedule(function()
      opts.on_exit({
        code = code,
        signal = signal,
        stdout = table.concat(stdout),
        stderr = table.concat(stderr),
        cancelled = cancelled,
        timed_out = timed_out,
      })
    end)
  end

  local ok, err = pcall(function()
    proc = vim.system(argv, {
      cwd = opts.cwd,
      env = opts.env,
      text = true,
      stdout = function(_, data)
        if data then
          stdout[#stdout + 1] = data
        end
      end,
      stderr = function(_, data)
        if data then
          stderr[#stderr + 1] = data
        end
      end,
    }, function(obj)
      finish(obj and obj.code or -1, obj and obj.signal)
    end)
  end)

  if not ok then
    vim.schedule(function()
      opts.on_exit({
        code = -1,
        stdout = "",
        stderr = tostring(err),
        cancelled = false,
        timed_out = false,
      })
    end)
    handle.cancel = function() end
    return handle
  end

  function handle.cancel()
    if finished then
      return
    end
    cancelled = true
    pcall(function()
      proc:kill("sigterm")
    end)
  end

  if opts.timeout and opts.timeout > 0 then
    timer = vim.uv.new_timer()
    timer:start(
      opts.timeout,
      0,
      vim.schedule_wrap(function()
        if finished then
          return
        end
        cancelled = true
        timed_out = true
        pcall(function()
          proc:kill("sigterm")
        end)
      end)
    )
  end

  return handle
end

return M

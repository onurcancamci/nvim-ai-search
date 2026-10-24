-- Braille spinner driven by a libuv timer.

local M = {}

local frames =
  { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

---@param on_frame fun(frame: string)
---@param interval number|nil
---@return table { stop = fun() }
function M.start(on_frame, interval)
  local index = 0
  local timer = vim.uv.new_timer()

  local stopped = false
  local function stop()
    if stopped then
      return
    end
    stopped = true
    if timer then
      pcall(function()
        timer:stop()
      end)
      pcall(function()
        timer:close()
      end)
      timer = nil
    end
  end

  timer:start(
    0,
    interval or 90,
    vim.schedule_wrap(function()
      if stopped then
        return
      end
      index = index % #frames + 1
      on_frame(frames[index])
    end)
  )

  return { stop = stop }
end

return M

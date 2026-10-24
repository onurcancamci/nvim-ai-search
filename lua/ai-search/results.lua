-- Normalization of provider output into one entry shape, plus dedupe and capping.

local M = {}

---@param file string
---@param cwd string
---@return string absolute, boolean is_uri
function M.resolve_path(file, cwd)
  if file:match("^%a[%w+.%-]*://") then
    return file, true
  end
  if file:sub(1, 1) == "/" then
    return vim.fs.normalize(file), false
  end
  return vim.fs.normalize(cwd .. "/" .. file), false
end

---@param entries table[]
---@param opts table { cwd: string, max: number }
---@return table[]
function M.finalize(entries, opts)
  local cwd = opts.cwd or vim.fn.getcwd()
  local max = opts.max or 100

  local out, seen = {}, {}

  for _, entry in ipairs(entries) do
    local file = entry.file
    if type(file) == "string" and file ~= "" then
      local abs, is_uri = M.resolve_path(file, cwd)
      local keep = true

      if not is_uri then
        keep = vim.uv.fs_stat(abs) ~= nil
      end

      if keep then
        local lnum = math.max(1, math.floor(tonumber(entry.lnum) or 1))
        local key = abs .. ":" .. lnum
        if not seen[key] then
          seen[key] = true
          out[#out + 1] = {
            file = abs,
            lnum = lnum,
            col = entry.col and math.max(1, math.floor(entry.col)) or 1,
            text = entry.text and vim.trim(entry.text) or nil,
            score = entry.score,
            source = entry.source,
            is_uri = is_uri,
          }
          if #out >= max then
            break
          end
        end
      end
    end
  end

  return out
end

return M

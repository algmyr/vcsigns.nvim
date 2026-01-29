local M = {}

local logging = require "vclib.logging"

local DEFAULT_TIMEOUT_MS = 2000
local TERMINAL_WIDTH = 10000

--- Print a message to the user if verbose mode is enabled.
M.verbose = logging.verbose_logger "vcsigns"

--- Run a system command with a timeout.
--- If a callback is provided, runs async and calls the callback on completion.
---@param cmd string[] The command to execute.
---@param opts table Options table passed to vim.system (merged with defaults).
---@param callback function|nil Optional callback function.
---@return vim.SystemObj
function M.run_with_timeout(cmd, opts, callback)
  M.verbose("Running command: " .. table.concat(cmd, " "))
  local merged_opts = vim.tbl_deep_extend(
    "force",
    { timeout = DEFAULT_TIMEOUT_MS, env = { COLUMNS = TERMINAL_WIDTH } },
    opts
  )
  if callback == nil then
    return vim.system(cmd, merged_opts)
  end

  return vim.system(cmd, merged_opts, function(out)
    if out.code == 124 then
      M.verbose("Command timed out: " .. table.concat(cmd, " "))
      return
    end
    vim.schedule(function()
      callback(out)
    end)
  end)
end

--- Get the directory of the file in the given buffer.
--- Returns the absolute path to the parent directory.
---@param bufnr integer The buffer number.
---@return string The absolute directory path.
function M.file_dir(bufnr)
  return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p:h")
end

--- Slice a table to get a subtable.
---@param tbl table The table to slice.
---@param start integer The starting index (1-based).
---@param count integer The number of elements to take.
---@return table A new table containing the sliced elements.
function M.slice(tbl, start, count)
  local result = {}
  for i = start, start + count - 1 do
    if i >= 1 and i <= #tbl then
      table.insert(result, tbl[i])
    end
  end
  return result
end

return M

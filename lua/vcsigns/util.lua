local M = {}

local logging = require "vclib.logging"

local DEFAULT_TIMEOUT_MS = 2000
local TERMINAL_WIDTH = 10000

--- Print a message to the user if verbose mode is enabled.
M.verbose = logging.verbose_logger "vcsigns"

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

--- Check if the buffer is a special buffer that we shouldn't try to get VCS info for.
--- @param bufnr integer The buffer number.
--- @return boolean True if it's a special buffer, false otherwise.
function M.is_special_buffer(bufnr)
  if vim.bo[bufnr].buftype ~= "" then
    -- Special buffer.
    return true
  end
  if vim.api.nvim_buf_get_name(bufnr) == "" then
    -- Unnamed buffer, treat as special.
    return true
  end
  if vim.bo[bufnr].filetype == "netrw" then
    -- Netrw buffer, don't try to get VCS info.
    return true
  end
  return false
end

return M

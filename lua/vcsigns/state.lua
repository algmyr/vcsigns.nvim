local M = {}

---@class DiffState
---@field hunks Hunk[]
---@field old_contents string
---@field last_update integer
---@field hunks_changedtick integer

---@type table<integer, DiffState>
local buffers = {}

---@param bufnr integer
---@return DiffState
function M.get(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not buffers[bufnr] then
    buffers[bufnr] = {
      hunks = {},
      old_contents = "",
      last_update = 0,
      hunks_changedtick = 0,
    }
  end
  return buffers[bufnr]
end

---@param bufnr integer
function M.clear(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  buffers[bufnr] = nil
end

return M

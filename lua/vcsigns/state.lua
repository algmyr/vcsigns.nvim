local M = {}

---@class BufferState
---@field diff DiffState
---@field vcs VcsState

---@class DiffState
---@field hunks Hunk[]
---@field old_lines string[]
---@field last_update integer
---@field hunks_changedtick integer

---@class VcsState
---@field vcs Vcs|nil
---@field detecting boolean|nil

---@type table<integer, BufferState>
local buffers = {}

--- Get (or create) the state for the given buffer.
---@param bufnr integer The buffer number (0 for current buffer).
---@return BufferState The buffer state.
function M.get(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  if not buffers[bufnr] then
    buffers[bufnr] = {
      diff = {
        hunks = {},
        old_lines = {},
        last_update = 0,
        hunks_changedtick = 0,
      },
      vcs = {
        vcs = nil,
        detecting = nil,
      },
    }
  end
  return buffers[bufnr]
end

--- Clear the state for the given buffer.
---@param bufnr integer The buffer number (0 for current buffer).
function M.clear(bufnr)
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  buffers[bufnr] = nil
end

return M

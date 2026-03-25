local M = {}

---@class BufferState
---@field diff DiffState
---@field vcs VcsState
---@field anchor string|nil
---@field offset integer|nil Buffer-specific offset override (if set, ignores repo offset).

---@class DiffState
---@field hunks Hunk[]
---@field old_lines string[]
---@field last_update integer
---@field hunks_changedtick integer

---@class VcsState
---@field vcs VcsHandle|nil
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
      anchor = nil,
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

---@class RepoState
---@field offset integer Offset relative to anchor (-1 = anchor, 0 = parent, 1 = grandparent, etc.).

---@type table<string, RepoState>
local repo_state = {}

---Get (or create) the state for the given repository.
---@param repo_path string
function M.repo_get(repo_path)
  if not repo_state[repo_path] then
    repo_state[repo_path] = {
      offset = vim.g.vcsigns_target_commit or 0,
    }
  end
  return repo_state[repo_path]
end

return M

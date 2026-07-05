local M = {}

---@class BufferState
---@field diff DiffState
---@field vcs VcsState
---@field anchor string|nil

---@class DiffState
---@field hunks Hunk[]
---@field old_lines string[]
---@field last_update integer
---@field hunks_changedtick integer

---@class VcsState
---@field vcs VcsHandle|nil
---@field detecting boolean|nil

---@type VcsHandle?
local start_dir_vcs = nil

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
---@field revset string|nil Buffer-specific revset override.

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

--- Mark all VCSHandle instances associated with the one in the buffer as dirty, to be refreshed.
---@param bufnr integer The buffer number (0 for current buffer).
function M.mark_vcs_dirty(bufnr)
  local vcs = M.get(bufnr).vcs.vcs
  assert(vcs, "No VCS handle for buffer " .. bufnr)
  for _, s in pairs(buffers) do
    if
      s.vcs.vcs
      and s.vcs.vcs.name == vcs.name
      and s.vcs.vcs.root == vcs.root
    then
      s.vcs.vcs.dirty = true
    end
  end
end

return M

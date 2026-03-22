local M = {}

local util = require "vcsigns.util"
local vcrepo = require "vcrepo"
local state = require "vcsigns.state"
local async = require "async"

--- Get the target commit from the global state.
---@param repo_path string The repository path.
---@return integer The target commit.
local function _target_commit(repo_path)
  return state.repo_get(repo_path).commit_offset
end

--- Check if buffer is valid after an async operation.
--- Returns nil if buffer is invalid, otherwise returns the result of fn.
---@async
---@param bufnr integer The buffer number.
---@param fn fun(): any The function to call if buffer is valid.
---@return any|nil The result of fn, or nil if buffer is invalid.
local function _with_valid_buffer(bufnr, fn)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    util.verbose "Buffer no longer valid, skipping"
    return nil
  end
  return fn()
end

--- Get the relevant file contents of the file according to the VCS.
---@async
---@param bufnr integer The buffer number.
---@param vcs VcsHandle The version control system to use.
---@return string[]|nil The file lines or nil if unavailable.
function M.show_file(bufnr, vcs)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    util.verbose "Buffer no longer valid, skipping"
    return nil
  end

  local commit_offset = _target_commit(vcs.root)
  local target = vcrepo.create_target(bufnr, vcs, commit_offset)
  local lines, resolved_file = vcs:show_file(target, { follow_renames = true })

  -- Check buffer still valid after async operation.
  return _with_valid_buffer(bufnr, function()
    if resolved_file then
      util.verbose("Rename found: " .. target.file .. " -> " .. resolved_file)
      vim.b[bufnr].vcsigns_resolved_rename =
        { to = target.file, from = resolved_file }
    end
    return lines
  end)
end

--- Detect the VCS for the current buffer.
---@param bufnr integer The buffer number.
---@return VcsHandle|nil The detected VCS or nil if no VCS was detected.
function M.detect_vcs(bufnr)
  local file_dir = util.file_dir(bufnr)
  return vcrepo.detect(file_dir)
end

return M

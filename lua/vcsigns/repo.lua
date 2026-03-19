local M = {}

local util = require "vcsigns.util"
local repo_common = require "vcrepo.common"
local state = require "vcsigns.state"
local paths = require "vclib.paths"
local async = require "async"

--- List of VCSs, in priority order.
---@type VcsInterface[]
M.vcs = {
  require "vcrepo.jj",
  require "vcrepo.git",
  require "vcrepo.hg",
}

--- Register a custom VCS implementation.
--- The VCS will be added at the beginning of the detection priority list.
---@param vcs Vcs The VCS implementation to register.
function M.register_vcs(vcs)
  table.insert(M.vcs, 1, vcs)
end

--- Get the target commit from the global state.
---@param repo_path string The repository path.
---@return integer The target commit.
local function _target_commit(repo_path)
  return state.repo_get(repo_path).commit_offset
end

--- Get the target for the current buffer.
---@param bufnr integer The buffer number.
---@param vcs Vcs The version control system.
---@return Target
local function _get_target(bufnr, vcs)
  assert(vcs.root, "VCS root must be set")
  local path = paths.abs_path(bufnr)
  local file = paths.relativize(path, vcs.root)
  return {
    commit = _target_commit(vcs.root),
    file = file,
    path = path,
  }
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
---@param vcs Vcs The version control system to use.
---@return string[]|nil The file lines or nil if unavailable.
function M.show_file(bufnr, vcs)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    util.verbose "Buffer no longer valid, skipping"
    return nil
  end

  local target = _get_target(bufnr, vcs)

  if vcs.resolve_rename then
    util.verbose("Resolving rename for " .. target.file)
    local resolved_file = vcs:resolve_rename(target)

    -- Check buffer still valid after async operation.
    local result = _with_valid_buffer(bufnr, function()
      if resolved_file then
        util.verbose("Rename found: " .. target.file .. " -> " .. resolved_file)
        vim.b[bufnr].vcsigns_resolved_rename =
          { to = target.file, from = resolved_file }
        target.file = resolved_file
      end
      return true
    end)

    if not result then
      return nil
    end
  end

  local lines = vcs:show(target)

  -- Check buffer still valid after async operation.
  return _with_valid_buffer(bufnr, function()
    return lines
  end)
end

--- Detect the VCS for the current buffer.
---@param bufnr integer The buffer number.
---@return Vcs|nil The detected VCS or nil if no VCS was detected.
function M.detect_vcs(bufnr)
  local file_dir = util.file_dir(bufnr)
  return repo_common.detect_vcs(M.vcs, file_dir)
end

return M

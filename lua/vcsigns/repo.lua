local M = {}

local util = require "vcsigns.util"
local repo_common = require "vcrepo.common"
local state = require "vcsigns.state"
local paths = require "vclib.paths"

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

---@param bufnr integer The buffer number.
---@param vcs Vcs The version control system to use.
---@param target Target The target for the VCS command.
---@param cb fun(lines: string[]|nil) Callback function to handle the output.
local function _show_file_impl(bufnr, vcs, target, cb)
  vcs:show(target, function(lines)
    -- If the buffer was deleted, bail.
    if not vim.api.nvim_buf_is_valid(bufnr) then
      util.verbose "Buffer no longer valid, skipping diff"
      return
    end
    cb(lines)
  end)
end

--- Get the relevant file contents of the file according to the VCS.
---@param bufnr integer The buffer number.
---@param vcs Vcs The version control system to use.
---@param cb fun(lines: string[]|nil) Callback function to handle the output.
function M.show_file(bufnr, vcs, cb)
  local target = _get_target(bufnr, vcs)
  if vcs.resolve_rename then
    util.verbose("Resolving rename for " .. target.file)
    vcs:resolve_rename(target, function(resolved_file)
      -- If the buffer was deleted, bail.
      if not vim.api.nvim_buf_is_valid(bufnr) then
        util.verbose "Buffer no longer valid, skipping"
        return
      end
      if resolved_file then
        util.verbose("Rename found: " .. target.file .. " -> " .. resolved_file)
        vim.b[bufnr].vcsigns_resolved_rename =
          { to = target.file, from = resolved_file }
        target.file = resolved_file
      end
      _show_file_impl(bufnr, vcs, target, cb)
    end)
  else
    _show_file_impl(bufnr, vcs, target, cb)
  end
end

--- Detect the VCS for the current buffer.
---@param bufnr integer The buffer number.
---@return Vcs|nil The detected VCS or nil if no VCS was detected.
function M.detect_vcs(bufnr)
  local file_dir = util.file_dir(bufnr)
  return repo_common.detect_vcs(M.vcs, file_dir)
end

return M

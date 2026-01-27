local M = {}

local util = require "vcsigns.util"
local repo_common = require "vcsigns.repo_def.common"

--- List of VCSs, in priority order.
---@type VcsInterface[]
M.vcs = {
  require "vcsigns.repo_def.jj",
  require "vcsigns.repo_def.git",
  require "vcsigns.repo_def.hg",
}

--- Register a custom VCS implementation.
--- The VCS will be added at the beginning of the detection priority list.
---@param vcs Vcs The VCS implementation to register.
function M.register_vcs(vcs)
  table.insert(M.vcs, 1, vcs)
end

--- Get the absolute path of the file in the buffer.
--- @param bufnr integer The buffer number.
--- @return string The absolute path of the file.
local function _get_path(bufnr)
  return vim.fn.resolve(
    vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":p")
  )
end

local function _target_commit()
  return vim.g.vcsigns_target_commit or 0
end

--- Get the target for the current buffer.
---@param bufnr integer The buffer number.
---@param vcs Vcs The version control system.
---@return Target
local function _get_target(bufnr, vcs)
  local path = _get_path(bufnr)
  assert(vcs.root, "VCS root must be set")

  -- Make file path relative to repo root.
  local root = vcs.root
  local file
  if path:sub(1, #root) == root then
    file = path:sub(#root + 2) -- +2 to skip root and the path separator.
  else
    -- File is outside the repo root.
    error(string.format("File %s is not under repo root %s", path, root))
  end

  return {
    commit = _target_commit(),
    file = file,
    path = path,
  }
end

local function _is_available(vcs)
  local programs = {
    vcs.detect.cmd()[1],
  }
  for _, program in ipairs(programs) do
    if vim.fn.executable(program) == 0 then
      util.verbose("VCS command not executable: " .. program)
      return false
    end
  end
  return true
end

---@param bufnr integer The buffer number.
---@param vcs Vcs The version control system to use.
---@param target Target The target for the VCS command.
---@param cb fun(lines: string[]|nil) Callback function to handle the output.
local function _show_file_impl(bufnr, vcs, target, cb)
  vcs.show(target, vcs.root, function(lines)
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
    vcs.resolve_rename(target, vcs.root, function(resolved_file)
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
  -- If the file dir does not exist, things will end poorly.
  if vim.fn.isdirectory(file_dir) == 0 then
    util.verbose("File directory does not exist: " .. file_dir)
    return nil
  end
  for _, vcs in ipairs(M.vcs) do
    util.verbose("Trying to detect VCS " .. vcs.name)
    if not _is_available(vcs) then
      util.verbose("VCS " .. vcs.name .. " is not available")
      goto continue
    end
    local detect_cmd = vcs.detect.cmd()
    local res = util.run_with_timeout(detect_cmd, { cwd = file_dir }):wait()
    local detection_result = vcs.detect.check(res)
    if detection_result.detected then
      return repo_common.vcs_with_root(vcs, detection_result.root)
    end
    ::continue::
  end
  return nil
end

return M

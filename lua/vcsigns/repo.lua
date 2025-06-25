local M = {}

local util = require "vcsigns.util"

--- List of VCSs, in priority order.
---@type Vcs[]
M.vcs = {
  require "vcsigns.repo_def.jj",
  require "vcsigns.repo_def.git",
  require "vcsigns.repo_def.hg",
}

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
---@return Target
local function _get_target(bufnr)
  local path = _get_path(bufnr)
  local file = vim.fn.fnamemodify(path, ":t")
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
---@param cb fun(content: string|nil) Callback function to handle the output.
local function _show_file_impl(bufnr, vcs, target, cb)
  local file_dir = util.file_dir(bufnr)
  util.run_with_timeout(vcs.show.cmd(target), { cwd = file_dir }, function(out)
    -- If the buffer was deleted, bail.
    if not vim.api.nvim_buf_is_valid(bufnr) then
      util.verbose "Buffer no longer valid, skipping diff"
      return nil
    end
    local old_contents = out.stdout
    if not old_contents then
      util.verbose "No output from command, skipping diff"
      return nil
    end
    if not vcs.show.check(out) then
      util.verbose "VCS decided to not produce a file, skipping diff"
      return nil
    end
    cb(old_contents)
  end)
end

--- Get the relevant file contents of the file according to the VCS.
---@param bufnr integer The buffer number.
---@param vcs Vcs The version control system to use.
---@param cb fun(content: string|nil) Callback function to handle the output.
function M.show_file(bufnr, vcs, cb)
  local target = _get_target(bufnr)
  if vcs.resolve_rename then
    util.verbose("Resolving rename for " .. target.file)
    local file_dir = util.file_dir(bufnr)
    util.run_with_timeout(
      vcs.resolve_rename.cmd(target),
      { cwd = file_dir },
      function(out)
        -- If the buffer was deleted, bail.
        if not vim.api.nvim_buf_is_valid(bufnr) then
          util.verbose "Buffer no longer valid, skipping"
          return
        end
        local resolved_file = vcs.resolve_rename.extract(out)
        if resolved_file then
          util.verbose(
            "Rename found: " .. target.file .. " -> " .. resolved_file
          )
          target.file = resolved_file
        end
        _show_file_impl(bufnr, vcs, target, cb)
      end
    )
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
    if vcs.detect.check(res) then
      return vcs
    end
    ::continue::
  end
  return nil
end

return M

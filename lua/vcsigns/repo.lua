local M = {}

local util = require "vcsigns.util"

---@class Detector
---@field cmd fun(): string[]
---@field check fun(cmd_out: vim.SystemCompleted): boolean
local Detector = {}

---@class FileShower
---@field cmd fun(target: Target): string[]
---@field check fun(cmd_out: vim.SystemCompleted): boolean
local FileShower = {}

---@class RenameResolver
---@field cmd fun(target: Target): string[]
---@field extract fun(cmd_out: vim.SystemCompleted): string|nil
local RenameResolver = {}

---@class Vcs
---@field name string Human-readable name of the VCS.
---@field detect Detector
---@field show FileShower
---@field resolve_rename RenameResolver|nil
local Vcs = {}

---@class Target
---@field commit integer Target commit.
---@field file string The file name.
---@field path string The absolute path to the file.
local Target = {}

---@param out vim.SystemCompleted
---@return boolean
---@diagnostic disable-next-line: unused-local
local function _accept_any(out)
  return true
end

---@param out vim.SystemCompleted
---@return boolean
local function _successful_command(out)
  return out.code == 0
end

local function _jj_target(target)
  return string.format("roots(ancestors(@, %d))", target + 2)
end

---@type table<string, Vcs>
M.vcs = {
  jj = {
    name = "Jujutsu",
    detect = {
      cmd = function()
        return { "jj", "root" }
      end,
      check = _successful_command,
    },
    show = {
      cmd = function(target)
        return {
          "jj",
          "file",
          "show",
          "-r",
          _jj_target(target.commit),
          "--",
          target.file,
        }
      end,
      check = _accept_any,
    },
    resolve_rename = {
      cmd = function(target)
        return {
          'jj',
          'diff',
          '-r',
          _jj_target(target.commit-1) .. "::@",
          '-s',
          target.file,
        }
      end,
      extract = function(out)
        if out.code ~= 0 then
          return nil
        end
        if not out.stdout then
          return nil
        end
        local lines = vim.split(vim.trim(out.stdout), "\n")
        local move_spec = lines[#lines]:sub(3)
        local res, replacements = move_spec:gsub('{(.*) => (.*)}', '%1')
        if replacements == 0 then
          -- Not a rename.
          return nil
        end
        return res
      end,
    }
  },
  git = {
    name = "Git",
    detect = {
      cmd = function()
        return { "git", "rev-parse", "--is-inside-work-tree" }
      end,
      check = _successful_command,
    },
    show = {
      cmd = function(target)
        return {
          "git",
          "show",
          string.format("HEAD~%d", target.commit) .. ":./" .. target.file,
        }
      end,
      check = _accept_any,
    },
  },
  hg = {
    name = "Mercurial",
    detect = {
      cmd = function()
        return { "hg", "root" }
      end,
      check = _successful_command,
    },
    show = {
      cmd = function(target)
        return {
          "hg",
          "cat",
          "--config",
          "extensions.color=!",
          "--rev",
          string.format(".~%d", target.commit),
          "--",
          target.file,
        }
      end,
      check = _accept_any,
    },
  },
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
      util.verbose("VCS command not executable: " .. program, "is_available")
      return false
    end
  end
  return true
end

---@param vcs_name string The version control system to use.
---@return Vcs|nil The VCS object or nil if the VCS is not available.
function M.get_vcs(vcs_name)
  local vcs = M.vcs[vcs_name]
  if not vcs then
    error("Unknown VCS: " .. vcs_name)
  end
  if not _is_available(vcs) then
    util.verbose("VCS " .. vcs_name .. " is not available", "get_vcs")
    return nil
  end
  return vcs
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
      util.verbose("Buffer no longer valid, skipping diff", "update_signs")
      return nil
    end
    local old_contents = out.stdout
    if not old_contents then
      util.verbose("No output from command, skipping diff", "update_signs")
      return nil
    end
    if not vcs.show.check(out) then
      util.verbose(
        "VCS decided to not produce a file, skipping diff",
        "update_signs"
      )
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
    util.verbose(
      "Resolving rename for " .. target.file,
      "show_file"
    )
    local file_dir = util.file_dir(bufnr)
    util.run_with_timeout(vcs.resolve_rename.cmd(target), { cwd = file_dir }, function(out)
      local resolved_file = vcs.resolve_rename.extract(out)
      if resolved_file then
        util.verbose(
          "Rename found: " .. target.file .. " -> " .. resolved_file,
          "show_file"
        )
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
  -- TODO(algmyr): Take into account the current working directory?
  local file_dir = util.file_dir(bufnr)
  -- If the file dir does not exist, things will end poorly.
  if vim.fn.isdirectory(file_dir) == 0 then
    util.verbose("File directory does not exist: " .. file_dir, "detect_vcs")
    return nil
  end
  for name, _ in pairs(M.vcs) do
    util.verbose("Trying to detect VCS " .. name, "detect_vcs")
    local vcs = M.get_vcs(name)
    if not vcs then
      util.verbose("VCS " .. name .. " is not available", "detect_vcs")
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

local M = {}

---@class Vcs
---@field name string
---@field show_cmd fun(bufnr: integer): string[]
---@field detect_cmd fun(): string[]
local Vcs = {}

--- The expression to get the commit `target` steps back.
---@param target integer The target to check.
local function jj_target(target)
  return string.format("roots(ancestors(@, %d))", target + 2)
end

local function git_target(target)
  return string.format("HEAD~%d", target)
end
local function hg_target(target)
  return string.format(".~%d", target)
end

M.vcs = {
  jj = {
    detect_cmd = function()
      return { "jj", "root" }
    end,
    show_cmd = function(target)
      return {
        "jj",
        "file",
        "show",
        "-r",
        jj_target(target.commit),
        "--",
        target.file,
      }
    end,
  },
  git = {
    detect_cmd = function()
      return { "git", "rev-parse", "--is-inside-work-tree" }
    end,
    show_cmd = function(target)
      return { "git", "show", git_target(target.commit) .. ":./" .. target.file }
    end,
  },
  hg = {
    detect_cmd = function()
      return { "hg", "root" }
    end,
    show_cmd = function(target)
      return {
        "hg",
        "cat",
        "--config",
        "extensions.color=!",
        "--rev",
        hg_target(target.commit),
        "--",
        target.file,
      }
    end,
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
    vcs.detect_cmd()[1],
  }
  for _, program in ipairs(programs) do
    if vim.fn.executable(program) == 0 then
      require("vcsigns").util.verbose(
        "VCS command not executable: " .. program,
        "is_available"
      )
      return false
    end
  end
  return true
end

---@param vcs_name string The version control system to use.
---@return Vcs|nil The VCS object or nil if the VCS is not available.
function M.get_vcs(vcs_name)
  local vcs_base = M.vcs[vcs_name]
  if not vcs_base then
    error("Unknown VCS: " .. vcs_name)
  end
  if not _is_available(vcs_base) then
    require("vcsigns").util.verbose(
      "VCS " .. vcs_name .. " is not available",
      "get_vcs"
    )
    return nil
  end
  local vcs = {}
  vcs._base = vcs_base
  vcs.name = vcs_name
  vcs.show_cmd = function(bufnr)
    return vcs._base.show_cmd(_get_target(bufnr))
  end
  vcs.detect_cmd = function()
    return vcs._base.detect_cmd()
  end
  return vcs
end

--- Detect the VCS for the current buffer.
---@param bufnr integer The buffer number.
---@return Vcs|nil The detected VCS or nil if no VCS was detected.
function M.detect_vcs(bufnr)
  -- TODO(algmyr): Take into account the current working directory?
  local file_dir = require("vcsigns").util.file_dir(bufnr)
  -- If the file dir does not exist, things will end poorly.
  if vim.fn.isdirectory(file_dir) == 0 then
    require("vcsigns").util.verbose(
      "File directory does not exist: " .. file_dir,
      "detect_vcs"
    )
    return nil
  end
  for name, _ in pairs(M.vcs) do
    require("vcsigns").util.verbose(
      "Trying to detect VCS " .. name,
      "detect_vcs"
    )
    local vcs = M.get_vcs(name)
    if not vcs then
      require("vcsigns").util.verbose(
        "VCS " .. name .. " is not available",
        "detect_vcs"
      )
      goto continue
    end
    local detect_cmd = vcs.detect_cmd()
    local res = require("vcsigns").util
      .run_with_timeout(detect_cmd, { cwd = file_dir })
      :wait()
    if res.code == 0 then
      return vcs
    end
    ::continue::
  end
  return nil
end

return M

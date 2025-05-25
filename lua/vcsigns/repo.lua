local M = {}

---@class Vcs
---@field name string
---@field show_cmd fun(bufnr: integer): string[]
---@field diff_cmd fun(bufnr: integer): string[]
---@field detect_cmd fun(): string[]
local Vcs = {}

--- The expression to get the commit `target` steps back.
---@param target integer The target to check.
local function jj_target(target)
  return string.format("roots(ancestors(@, %d))", target + 2)
end

M.vcs = {
  jj = {
    detect_cmd = function()
      return { "jj", "root" }
    end,
    show_cmd = function(target, path)
      return { "jj", "file", "show", "-r", jj_target(target), "--", path }
    end,
    diff_cmd = function(target, path)
      return {
        "jj",
        "diff",
        "--git",
        "--context=0",
        "--from",
        jj_target(target),
        "--to",
        "@",
        "--",
        path,
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
  return vim.g.target_commit or 0
end

---@param vcs_name string The version control system to use.
---@return Vcs The VCS object.
function M.get_vcs(vcs_name)
  if not M.vcs[vcs_name] then
    error("Unknown VCS: " .. vcs_name)
  end
  local vcs = {}
  vcs._base = M.vcs[vcs_name]
  vcs.name = vcs_name
  vcs.diff_cmd = function(bufnr)
    return vcs._base.diff_cmd(_target_commit(), _get_path(bufnr))
  end
  vcs.show_cmd = function(bufnr)
    return vcs._base.show_cmd(_target_commit(), _get_path(bufnr))
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
  for name, _ in pairs(M.vcs) do
    require("vcsigns").util.verbose(
      "Trying to detect VCS " .. name,
      "detect_vcs"
    )
    local vcs = M.get_vcs(name)
    local detect_cmd = vcs.detect_cmd()
    local res = require("vcsigns").util.run_with_timeout(detect_cmd):wait()
    if res.code == 0 then
      return vcs
    end
  end
  return nil
end

return M

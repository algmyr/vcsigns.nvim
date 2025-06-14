local M = {}

--- The target of diff calculations.
--- This is a file at a particular commit in the VCS.
---@class Target
---@field commit integer Target commit.
---@field file string The file name.
---@field path string The absolute path to the file.
local Target = {}

--- Logic for detecting if a VCS is available.
---@class Detector
---@field cmd fun(): string[]
---@field check fun(cmd_out: vim.SystemCompleted): boolean
local Detector = {}

--- Logic for getting the file content from a VCS.
---@class FileShower
---@field cmd fun(target: Target): string[]
---@field check fun(cmd_out: vim.SystemCompleted): boolean
local FileShower = {}

--- Logic for resolving a rename in a VCS.
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

---@param out vim.SystemCompleted
---@return boolean
---@diagnostic disable-next-line: unused-local
function M.check_accept_any(out)
  return true
end

---@param out vim.SystemCompleted
---@return boolean
function M.check_successful_command(out)
  return out.code == 0
end

return M

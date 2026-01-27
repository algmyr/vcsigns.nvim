local M = {}

--- The target of diff calculations.
--- This is a file at a particular commit in the VCS.
---@class Target
---@field commit integer Target commit.
---@field file string The file name.
---@field path string The absolute path to the file.
local Target = {}

--- Result of VCS detection.
---@class DetectionResult
---@field detected boolean Whether the VCS was detected.
---@field root string|nil The root directory of the repository (only set if detected is true).
local DetectionResult = {}

--- Logic for detecting if a VCS is available.
---@class Detector
---@field cmd fun(): string[]
---@field check fun(cmd_out: vim.SystemCompleted): DetectionResult
local Detector = {}

--- Logic for getting the file content from a VCS.
---@alias FileShower fun(target: Target, root: string, callback: fun(lines: string[]|nil))

--- Logic for resolving a rename in a VCS.
---@alias RenameResolver fun(target: Target, root: string, callback: fun(resolved_file: string|nil))

---@class VcsInterface
---@field name string Human-readable name of the VCS.
---@field detect Detector
---@field show FileShower
---@field resolve_rename RenameResolver|nil
local VcsInterface = {}

---@class Vcs: VcsInterface
---@field root string The root directory of the repository.
local Vcs = {}

--- Create a VCS instance with the given root.
---@param vcs_interface VcsInterface The VCS interface.
---@param root string The root directory of the repository.
---@return Vcs
function M.vcs_with_root(vcs_interface, root)
  local vcs_instance = vim.deepcopy(vcs_interface)
  ---@cast vcs_instance Vcs
  vcs_instance.root = root
  return vcs_instance
end

---@param out vim.SystemCompleted
---@return boolean
---@diagnostic disable-next-line: unused-local
function M.check_accept_any(out)
  return true
end

---@param out vim.SystemCompleted
---@return DetectionResult
function M.check_and_extract_root(out)
  if out.code ~= 0 or not out.stdout then
    return { detected = false, root = nil }
  end
  return { detected = true, root = vim.trim(out.stdout) }
end

--- Convert file contents to lines.
---@param contents string|nil
---@return string[]|nil
function M.content_to_lines(contents)
  if not contents then
    return nil
  end
  if contents == "" then
    return {}
  end
  if contents:sub(-1) == "\n" then
    contents = contents:sub(1, -2)
  end
  return vim.split(contents, "\n", { plain = true })
end

return M

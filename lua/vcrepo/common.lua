local M = {}

local util = require "vcrepo.util"

--- Target VCS revision.
---@class TargetRevision
---@field anchor string|nil Anchor commit (VCS-specific revset; nil = working copy).
---@field offset integer Offset relative to anchor (0 = anchor, 1 = parent, etc.).
---@field revset string|nil VCS-specific revset (optional; overrides anchor + offset if provided).

--- The file target of VCS operations.
--- This is a file at a particular commit in the VCS.
---@class Target
---@field rev TargetRevision The base revision of the target.
---@field file string The file name.
---@field path string The absolute path to the file.
local Target = {}

--- Blame annotation for a single line.
---@class BlameAnnotation
---@field line_num integer The line number in the current file (1-based).
---@field annotation string The formatted blame annotation (from template).
---@field content string The content of the line.
local BlameAnnotation = {}

--- Template string for blame output formatting.
--- For git: Uses git's pretty-format placeholders (see git-log).
--- For jj: Uses jujutsu template language expressions.
--- For hg: Uses mercurial template language.
--- If nil, uses VCS-specific defaults.
---@alias BlameTemplate string|nil

--- Logic for detecting if a VCS is available in a directory.
--- Returns the repository root if detected, nil otherwise.
---@alias VcsDetector fun(dir: string): string|nil

--- Logic for getting the file content from a VCS.
--- Expected to be async.
---@alias FileShower fun(self: Vcs, target: Target): string[]|nil

--- Logic for getting blame annotations for a file.
--- Expected to be async.
---@alias BlameGetter fun(self: Vcs, file: string, template: BlameTemplate): BlameAnnotation[]|nil

--- Logic for resolving a rename in a VCS.
--- Expected to be async.
---@alias RenameResolver fun(self: Vcs, target: Target): string|nil

--- Logic for checking if VCS state changed and refresh is needed.
--- Returns true if refresh is needed, false if cached data can be reused.
--- Expected to be async.
---@alias RefreshChecker fun(self: Vcs): boolean

---@alias ChangedFileGetter fun(self: Vcs, target_rev: TargetRevision): VcsDiffEntry[]

---@class VcsInterface
---@field name string Human-readable name of the VCS.
---@field head_revision string The VCS-specific revset for the current working copy.
---@field detect VcsDetector
---@field show FileShower
---@field get_changed_files ChangedFileGetter Get list of changed files for a commit.
---@field blame BlameGetter|nil Get blame annotations for a file (optional).
---@field needs_refresh RefreshChecker Check if VCS state changed and refresh is needed (optional).
---@field resolve_rename RenameResolver|nil
local VcsInterface = {}

---@class VcsDiffEntry
--- Represents a single file diff entry.
---@field target Target The target file path.

---@class Vcs: VcsInterface
---@field root string The root directory of the repository.
local Vcs = {}

--- Create a VCS instance with the given root.
---@param vcs_interface VcsInterface The VCS interface.
---@param root string The root directory of the repository.
---@return Vcs
local function _vcs_with_root(vcs_interface, root)
  local vcs_instance = vim.deepcopy(vcs_interface)
  ---@cast vcs_instance Vcs
  vcs_instance.root = root
  return vcs_instance
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

M.SEP = "#SEP#"

function M.parse_blame_annotations(raw_lines)
  local annotations = {}

  for _, line in ipairs(raw_lines) do
    local parts = vim.split(line, M.SEP, { plain = true })
    if #parts == 3 then
      local annotation = parts[1]
      local line_num = tonumber(parts[2])
      local content = parts[3]

      if line_num then
        table.insert(annotations, {
          line_num = line_num,
          annotation = vim.trim(annotation),
          content = content,
        })
      end
    end
  end

  return annotations
end

--- Detect the VCS for the current buffer.
---@param VcsInterface[] vcs_list List of VCS interfaces to try, in priority order.
---@param string file_dir The directory of the file to detect the VCS for.
---@return Vcs|nil The detected VCS or nil if no VCS was detected.
function M.detect_vcs(vcs_list, file_dir)
  -- If the file dir does not exist, things will end poorly.
  if vim.fn.isdirectory(file_dir) == 0 then
    util.verbose("File directory does not exist: " .. file_dir)
    return nil
  end

  -- Try each VCS in priority order.
  for _, vcs in ipairs(vcs_list) do
    util.verbose("Trying to detect VCS " .. vcs.name)
    local root = vcs.detect(file_dir)
    if root then
      util.verbose("Detected " .. vcs.name .. " at " .. root)
      return _vcs_with_root(vcs, root)
    end
    util.verbose("VCS " .. vcs.name .. " not detected")
  end

  return nil
end

--- Create a target from an absolute path for VCS operations.
---@param abs_path string The absolute file path.
---@param vcs_root string The root directory of the repository.
---@param target_rev TargetRevision The target revision for the file.
---@return Target
function M.create_target_from_path(abs_path, vcs_root, target_rev)
  local paths = require "vclib.paths"
  local file = paths.relativize(abs_path, vcs_root)
  return {
    rev = target_rev,
    file = file,
    path = abs_path,
  }
end

--- Create a target from a buffer for VCS operations.
---@param bufnr integer The buffer number.
---@param vcs_root string The root directory of the repository.
---@param target_rev TargetRevision The target revision for the file.
---@return Target
function M.create_target(bufnr, vcs_root, target_rev)
  local paths = require "vclib.paths"
  local abs_path = paths.abs_path(bufnr)
  return M.create_target_from_path(abs_path, vcs_root, target_rev)
end

---@param diff_output vim.SystemObj
---@param root string The root directory of the repository.
---@param target_rev TargetRevision The target revision.
function M.process_diff_result(diff_output, root, target_rev)
  if diff_output.code ~= 0 or not diff_output.stdout then
    return nil
  end
  if #diff_output.stdout == 0 then
    return {}
  end
  local lines = vim.split(vim.trim(diff_output.stdout), "\n", { plain = true })
  return vim
    .iter(lines)
    :map(function(line)
      local abs_path = root .. "/" .. line
      return {
        target = M.create_target_from_path(abs_path, root, target_rev),
      }
    end)
    :totable()
end

--- Resolve the target revision for a VCS operation, in-place.
---@param vcs Vcs The VCS instance.
---@param target_rev TargetRevision The target revision to resolve.
local function _resolve_target_revision_in_place(vcs, target_rev)
  target_rev.anchor = target_rev.anchor or vcs.head_revision
  return target_rev
end

--- Resolve the target revision for a VCS operation.
--- In particular, resolve default anchor if needed.
---@param vcs Vcs The VCS instance.
---@param target_rev TargetRevision The target revision to resolve.
function M.resolve_target_revision(vcs, target_rev)
  local resolved_target_rev = vim.deepcopy(target_rev)
  return _resolve_target_revision_in_place(vcs, resolved_target_rev)
end

--- Resolve the target for a VCS operation.
--- In particular, resolve default anchor if needed.
---@param vcs Vcs The VCS instance.
---@param target Target The target to resolve.
function M.resolve_target(vcs, target)
  local resolved_target = vim.deepcopy(target)
  resolved_target.rev =
    _resolve_target_revision_in_place(vcs, resolved_target.rev)
  return resolved_target
end

return M

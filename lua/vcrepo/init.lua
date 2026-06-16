-- Public API for vcrepo.
-- This module provides a higher-level interface over the internal VCS implementations.

local M = {}

local common = require "vcrepo.common"

--- Global registry of VCS implementations.
--- Custom implementations can be added via add_backend().
---@type VcsInterface[]
local _registry = {
  require "vcrepo.jj",
  require "vcrepo.git",
  require "vcrepo.hg",
}

--- Public VCS handle that wraps the internal VCS interface.
---@class VcsHandle
---@field name string Human-readable name of the VCS.
---@field root string The root directory of the repository.
---@field dirty boolean Whether a forced refresh is needed.
---@field _internal Vcs Internal VCS implementation (private).
local VcsHandle = {}
VcsHandle.__index = VcsHandle

--- Show file contents at a target commit.
--- Optionally follows renames if the VCS supports it.
---@async
---@param target Target The target to retrieve.
---@param opts? {follow_renames?: boolean} Options for the show operation.
---@return string[]|nil lines The file lines, or nil if unavailable.
---@return string|nil resolved_file The resolved file path if a rename was followed.
function VcsHandle:show_file(target, opts)
  opts = opts or {}
  local follow_renames = opts.follow_renames
  local resolved_file = nil

  -- Handle rename resolution if requested and supported.
  if follow_renames and self._internal.resolve_rename then
    resolved_file = self._internal:resolve_rename(target)
    if resolved_file then
      target.file = resolved_file
    end
  end

  local lines = self._internal:show(target)
  return lines, resolved_file
end

--- Get blame annotations for a file.
---@async
---@param file string Relative file path from repo root.
---@param template? BlameTemplate Optional template for formatting blame output.
---@return BlameAnnotation[]|nil annotations The blame annotations, or nil if unavailable.
function VcsHandle:blame(file, template)
  if not self._internal.blame then
    return nil
  end
  return self._internal:blame(file, template)
end

--- Check if the VCS state has changed and a refresh is needed.
---@async
---@return boolean needs_refresh True if refresh is needed, false otherwise.
function VcsHandle:needs_refresh()
  if not self._internal.needs_refresh then
    -- If VCS doesn't support refresh checking, always refresh.
    return true
  end
  return self._internal:needs_refresh()
end

--- Create a target from an absolute path for VCS operations.
---@param abs_path string The absolute file path.
---@param target_rev TargetRevision The target revision for the file.
---@return Target
function VcsHandle:create_target_from_path(abs_path, target_rev)
  return common.create_target_from_path(abs_path, self.root, target_rev)
end

--- Create a target from a buffer for VCS operations.
---@param bufnr integer The buffer number.
---@param target_rev TargetRevision The target revision for the file.
---@return Target
function VcsHandle:create_target(bufnr, target_rev)
  return common.create_target(bufnr, self.root, target_rev)
end

--- List changed files.
---@param bufnr integer The buffer number to check for changes.
---@param target_rev TargetRevision The target revision to compare against.
---@return VcsDiffEntry[]|nil changed_files List of changed file paths, or nil if unavailable.
function VcsHandle:get_changed_files(target_rev)
  if not self._internal.get_changed_files then
    return nil
  end
  return self._internal:get_changed_files(target_rev)
end

--- Register a custom VCS implementation.
--- The VCS will be added at the beginning of the detection priority list.
---@param vcs VcsInterface The VCS implementation to register.
function M.add_backend(vcs)
  table.insert(_registry, 1, vcs)
end

--- Detect a VCS for the given directory.
--- Uses the global registry of VCS implementations.
---@param file_dir string The directory to detect the VCS in.
---@return VcsHandle|nil handle The VCS handle, or nil if no VCS was detected.
function M.detect(file_dir)
  local vcs = common.detect_vcs(_registry, file_dir)
  if not vcs then
    return nil
  end

  local handle = {
    name = vcs.name,
    root = vcs.root,
    dirty = true,
    _internal = vcs,
  }
  setmetatable(handle, VcsHandle)
  return handle
end

--- Export common utilities.
M.content_to_lines = common.content_to_lines
M.parse_blame_annotations = common.parse_blame_annotations
M.SEP = common.SEP

return M

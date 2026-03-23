-- Public API for vcrepo.
-- This module provides a higher-level interface over the internal VCS implementations.

local M = {}

local common = require "vcrepo.common"

--- The target of VCS operations.
--- This represents a file at a particular commit in the VCS.
---@class Target
---@field anchor string|nil Anchor commit (VCS-specific revset; nil = working copy).
---@field offset integer Offset relative to anchor (-1 = anchor, 0 = parent, 1 = grandparent, etc.).
---@field file string The file path relative to VCS root.
---@field path string The absolute path to the file.

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
    _internal = vcs,
  }
  setmetatable(handle, VcsHandle)
  return handle
end

--- Create a target from an absolute path for VCS operations.
---@param abs_path string The absolute file path.
---@param vcs VcsHandle The VCS handle.
---@param offset integer Offset relative to anchor (-1 = anchor, 0 = parent, 1 = grandparent, etc.).
---@param anchor string|nil Anchor commit (VCS-specific revset; nil = working copy).
---@return Target
function M.create_target_from_path(abs_path, vcs, offset, anchor)
  local paths = require "vclib.paths"
  assert(vcs.root, "VCS root must be set")
  local file = paths.relativize(abs_path, vcs.root)
  return {
    anchor = anchor,
    offset = offset,
    file = file,
    path = abs_path,
  }
end

--- Create a target from a buffer for VCS operations.
---@param bufnr integer The buffer number.
---@param vcs VcsHandle The VCS handle.
---@param offset integer Offset relative to anchor (-1 = anchor, 0 = parent, 1 = grandparent, etc.).
---@param anchor string|nil Anchor commit (VCS-specific revset; nil = working copy).
---@return Target
function M.create_target(bufnr, vcs, offset, anchor)
  local paths = require "vclib.paths"
  local abs_path = paths.abs_path(bufnr)
  return M.create_target_from_path(abs_path, vcs, offset, anchor)
end

--- Export common utilities.
M.content_to_lines = common.content_to_lines
M.parse_blame_annotations = common.parse_blame_annotations
M.SEP = common.SEP

return M

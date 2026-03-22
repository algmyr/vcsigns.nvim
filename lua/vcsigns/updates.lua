local M = {}

local diff = require "vcsigns.diff"
local high = require "vcsigns.high"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local state = require "vcsigns.state"
local util = require "vcsigns.util"
local ignore = require "vclib.ignore"
local async = require "async"

--- Cheap update assuming the old file contents are still fresh.
---@param bufnr integer The buffer number.
function M.shallow_update(bufnr)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local s = state.get(bufnr)
  local old_lines = s.diff.old_lines

  if not old_lines then
    util.verbose "No old contents available, skipping diff."
    return
  end

  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":f")
  if
    vim.g.vcsigns_respect_gitignore
    and #old_lines == 0
    and ignore.is_ignored(path)
  then
    -- Rough proxy for checking if file is ignored and not tracked.
    util.verbose "File ignored and had no previous contents, skipping diff."
    return
  end

  local hunks = diff.compute_diff(old_lines, buffer_lines)
  s.diff.hunks = hunks
  sign.add_signs(bufnr, hunks)

  if vim.b[bufnr].vcsigns_show_hunk_diffs then
    high.highlight_hunks(bufnr, hunks)
  else
    high.highlight_hunks(bufnr, {})
  end
end

--- Actually fetch the file contents from VCS.
---@async
---@param bufnr integer The buffer number.
---@param vcs VcsHandle The VCS handle for the buffer.
---@return boolean fetched Whether the fetch was successful and state was updated.
local function _do_vcs_fetch(bufnr, vcs)
  local start_time = vim.uv.now() ---@diagnostic disable-line: undefined-field

  local old_lines = repo.show_file(bufnr, vcs)
  if not old_lines then
    -- Some kind of failure, skip the diff.
    return false
  end
  local s = state.get(bufnr)
  local last = s.diff.last_update
  if start_time <= last then
    util.verbose "Skipping updating old file, we already have a newer update."
    return false
  end
  s.diff.old_lines = old_lines
  s.diff.last_update = start_time
  s.diff.hunks_changedtick = vim.b[bufnr].changedtick
  return true
end

--- Refresh the old file contents from VCS.
---@async
---@param bufnr integer The buffer number.
---@param vcs VcsHandle The VCS handle for the buffer.
---@param force_refresh boolean Whether to force refresh.
---@return boolean fetched Whether a VCS fetch was performed.
local function _refresh_old_file_contents(bufnr, vcs, force_refresh)
  local needs_refresh = vcs:needs_refresh()
  if not force_refresh and not needs_refresh then
    util.verbose "VCS state unchanged, skipping fetch."
    return false
  end
  return _do_vcs_fetch(bufnr, vcs)
end

--- Get the VCS object for a buffer if it's ready.
---@param bufnr integer The buffer number.
---@return VcsHandle|nil The VCS handle if ready, nil otherwise.
local function _get_vcs_if_ready(bufnr)
  local vcs_state = state.get(bufnr).vcs
  local detecting = vcs_state.detecting
  if detecting == nil then
    util.verbose "Buffer not initialized yet."
  end
  if detecting then
    util.verbose "Busy detecting, skipping."
    return
  end
  return vcs_state.vcs
end

--- Expensive update including VCS querying for file contents.
---@param bufnr integer The buffer number.
---@param force_refresh boolean|nil Whether to clear the gitignore cache.
function M.deep_update(bufnr, force_refresh)
  if force_refresh then
    ignore.clear_ignored_cache()
  end
  if util.is_special_buffer(bufnr) then
    -- Not a normal file buffer, don't do anything.
    util.verbose "Not a normal file buffer, skipping."
    return
  end
  local vcs = _get_vcs_if_ready(bufnr)
  if not vcs then
    util.verbose "No VCS detected for buffer, skipping."
    return
  end

  async.run(function()
    local ok, err = pcall(function()
      _refresh_old_file_contents(bufnr, vcs, force_refresh)
      -- Always run shallow update after, regardless of whether VCS fetch happened.
      -- Buffer content may have changed even if VCS state didn't.
      M.shallow_update(bufnr)
    end)
    if not ok then
      util.verbose("Error during update: " .. tostring(err))
    end
  end)
end

return M

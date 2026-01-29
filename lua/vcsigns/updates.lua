local M = {}

local diff = require "vcsigns.diff"
local high = require "vcsigns.high"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local state = require "vcsigns.state"
local util = require "vcsigns.util"
local ignore = require "vclib.ignore"

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

--- Refresh the old file contents from VCS and invoke callback.
---@param bufnr integer The buffer number.
---@param vcs Vcs The VCS object for the buffer.
---@param cb fun(bufnr: integer) Callback to call after the old file contents are refreshed.
local function _refresh_old_file_contents(bufnr, vcs, cb)
  local start_time = vim.uv.now() ---@diagnostic disable-line: undefined-field

  repo.show_file(bufnr, vcs, function(old_lines)
    if not old_lines then
      -- Some kind of failure, skip the diff.
      return
    end
    local s = state.get(bufnr)
    local last = s.diff.last_update
    if start_time <= last then
      util.verbose "Skipping updating old file, we already have a newer update."
      return
    end
    s.diff.old_lines = old_lines
    s.diff.last_update = start_time
    s.diff.hunks_changedtick = vim.b[bufnr].changedtick
    cb(bufnr)
  end)
end

--- Get the VCS object for a buffer if it's ready.
---@param bufnr integer The buffer number.
---@return Vcs|nil The VCS object if ready, nil otherwise.
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
---@param clear_ignore_cache boolean|nil Whether to clear the gitignore cache.
function M.deep_update(bufnr, clear_ignore_cache)
  if clear_ignore_cache then
    ignore.clear_ignored_cache()
  end
  if vim.bo[bufnr].buftype ~= "" then
    -- Not a normal file buffer, don't do anything.
    util.verbose "Not a normal file buffer, skipping."
    return
  end
  local vcs = _get_vcs_if_ready(bufnr)
  if not vcs then
    util.verbose "No VCS detected for buffer, skipping."
    return
  end

  _refresh_old_file_contents(bufnr, vcs, M.shallow_update)
end

return M

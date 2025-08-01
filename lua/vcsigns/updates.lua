local M = {}

local diff = require "vcsigns.diff"
local high = require "vcsigns.high"
local repo = require "vcsigns.repo"
local sign = require "vcsigns.sign"
local util = require "vcsigns.util"
local ignore = require "vclib.ignore"

--- Cheap update assuming the old file contents are still fresh.
---@param bufnr integer The buffer number.
function M.shallow_update(bufnr)
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local new_contents = table.concat(buffer_lines, "\n") .. "\n"
  local old_contents = vim.b[bufnr].vcsigns_old_contents

  if not old_contents then
    util.verbose "No old contents available, skipping diff."
    return
  end

  local path = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":f")
  if
    vim.g.vcsigns_respect_gitignore
    and old_contents == ""
    and ignore.is_ignored(path)
  then
    -- Rough proxy for checking if file is ignored and not tracked.
    util.verbose "File ignored and had no previous contents, skipping diff."
    return
  end

  if old_contents == "" and new_contents == "\n" then
    -- Special case of a newly created but empty file.
    -- This is just to avoid showing an "empty" buffer as a line added.
    -- Just a cosmetic thing.
    old_contents = "\n"
  end

  local compute_fine_diff = vim.b[bufnr].vcsigns_show_hunk_diffs
  local hunks = diff.compute_diff(old_contents, new_contents, compute_fine_diff)
  vim.b[bufnr].vcsigns_hunks = hunks
  sign.add_signs(bufnr, hunks)

  if vim.b[bufnr].vcsigns_show_hunk_diffs then
    high.highlight_hunks(bufnr, hunks)
  else
    high.highlight_hunks(bufnr, {})
  end
end

---@param bufnr integer The buffer number.
---@param vcs Vcs The VCS object for the buffer.
---@param cb fun(bufnr: integer) Callback to call after the old file contents are refreshed.
local function _refresh_old_file_contents(bufnr, vcs, cb)
  local start_time = vim.uv.now() ---@diagnostic disable-line: undefined-field

  repo.show_file(bufnr, vcs, function(old_contents)
    if not old_contents then
      -- Some kind of failure, skip the diff.
      return
    end
    local last = vim.b[bufnr].vcsigns_last_update or 0
    if start_time <= last then
      util.verbose "Skipping updating old file, we already have a newer update."
      return
    end
    vim.b[bufnr].vcsigns_old_contents = old_contents
    vim.b[bufnr].vcsigns_last_update = start_time
    vim.b[bufnr].vcsigns_hunks_changedtick = vim.b[bufnr].changedtick
    cb(bufnr)
  end)
end

---@param bufnr integer The buffer number.
---@return Vcs|nil The VCS object if ready, nil otherwise.
local function _get_vcs_if_ready(bufnr)
  local detecting = vim.b[bufnr].vcsigns_detecting
  if detecting == nil then
    util.verbose "Buffer not initialized yet."
  end
  if detecting then
    util.verbose "Busy detecting, skipping."
    return
  end
  return vim.b[bufnr].vcsigns_vcs
end

--- Expensive update including vcs querying for file contents.
---@param bufnr integer The buffer number.
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
